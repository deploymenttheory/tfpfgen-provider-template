# tfpfgen provider template

A template repository for building a Terraform provider with
[tfpfgen](https://github.com/deploymenttheory/terraform-plugin-framework-codegen):
point it at any OpenAPI document and the pipeline pins a snapshot, generates a
Go SDK with Microsoft Kiota, derives the blueprints, scaffolds the provider's
shell and emits the provider — every stage from committed state, with nothing
written by hand.

That last clause is the whole design. There is no curation step and no
hand-owned side of the tree: a provider built from this template is
reproducible from its pinned inputs alone, and anything the generator cannot
express it refuses by name rather than leaving for somebody to patch in.

## Getting started

1. **Create a repository from this template.** Name it
   `terraform-provider-<name>` — the Terraform Registry conventions, the
   release packaging and the docs generation all derive the provider name from
   the repository name.
2. **Run the `tfpfgen | Generate` workflow** (Actions → tfpfgen | Generate →
   Run workflow) with:
   - `openapi_url` — the OpenAPI document to pin. **First run only**; every run
     after re-fetches from the source the pinned snapshot itself records.

   Everything else has a default. The provider name comes from the repository
   name; the SDK's client name, path filters and kiota version come from the
   `internal/sdk/kiota-lock.json` the first run commits. The dispatch inputs
   exist to override those, not to carry them — a value a human retypes each
   run is a value that will one day be typed wrong.

   One run does the whole chain and opens one pull request: pin the document,
   generate the SDK, derive the provider block, draft blueprints pruned against
   the real SDK, fold in any committed probe evidence, check the bindings,
   scaffold the shell, generate the provider, then build and unit-test it on
   the runner.
3. **Run it again whenever an input changes** — a refreshed document, new probe
   recordings, a newer tfpfgen. The run re-derives everything and proposes the
   difference. If nothing changed, it says so and proposes nothing.
4. **Record live evidence (optional but recommended).** Configure the probe
   secrets below and dispatch `tfpfgen | Probe`. It exercises each resource's
   lifecycle against a sandbox tenant and commits the transcripts as
   `recordings/<name>/`. The next generate run folds their facts into the
   blueprints automatically.

   This is what a specification cannot tell you: which fields the API really
   requires, what it fills in when you omit them, what it silently rewrites.
   It also widens acceptance-test coverage mechanically, because a generated
   fixture can only use attributes the spec marks required or the probe
   observed as required.
5. **Release.** Push a `v*` tag (or dispatch `provider | Terraform Provider
   Release`). goreleaser builds linux/darwin/windows on amd64/arm64, with the
   signed checksums and registry manifest the Terraform Registry requires.

## Secrets to configure

| Secret | Needed by | Purpose |
|---|---|---|
| `GPG_PRIVATE_KEY` | release | signs the checksums (registry requirement) |
| `GPG_PRIVATE_KEY_PASSPHRASE` | release | only if the key has one |
| `TFPFGEN_PROBE_TOKEN` | probe | bearer token for the sandbox tenant |
| `TFPFGEN_PROBE_ENDPOINT` | probe | the API's base URL |
| `TFPFGEN_SANDBOX_EVIDENCE` | probe | a sentence (≥ 4 words) stating why this tenant is disposable |
| `TFPFGEN_ACCOUNT_GROUP_ID` | probe | the tenant scope the probe stays inside |

The generation pipeline needs no secrets: it uses the workflow's own
`GITHUB_TOKEN` to open pull requests, and the OpenAPI document is fetched
anonymously. If your document needs credentials, pin it locally with
`tfpfgen openapi fetch` and commit the snapshot instead.

The probe's guard treats `sandbox: true` as a *claim* and the evidence as
proof — it refuses to mutate anything until the tenant is demonstrably
disposable. The profile it reads is written from these secrets at run time and
never committed: a tenant identifier in a committed file turns a vulnerability
into a targeted one.

## Layout

Everything here is derived from something else. The only inputs are the pinned
document, the recordings, and this repository's own identity.

| Path | Written by | Regenerated |
|---|---|---|
| `openapi/<name>/` | `openapi fetch` — pinned, checksummed snapshots | on refresh |
| `openapi/<name>/patches/` | you, rarely — evidence-justified corrections where the published document is provably wrong about the live API | never |
| `recordings/<name>/` | `probe record` — replayable transcripts of live behaviour | per probe run |
| `internal/sdk/` | `sdk generate` (Kiota) | every run |
| `blueprints/<name>/{resources,datasources}/` | `blueprint draft -prune-module` — cleared and rewritten each run | every run |
| `blueprints/<name>/provider.blueprint.json` | `provider init` | every run |
| `blueprints/<name>/{actions,ephemerals}/`, `*.scenario.json` | you — inference does not yet produce these | never |
| `internal/{client,provider,services/common,acceptance}/`, `main.go` | `provider scaffold` — from the toolkit's templates | every run |
| everything else under `internal/services/`, `examples/`, `docs/` | `provider generate` | every run |
| `.tfpfgen/manifest.json` | the generator — the drift ledger | every run |

Every generated file carries a `DO NOT EDIT` header naming the blueprint and
its digest, and `-check` fails on any difference. To change generated output,
change its input; if no input can express what you need, that is a tfpfgen
feature request, not a hand edit.

## The local loop

`makefile` mirrors the pipeline exactly, reading the same committed lock, so
what you run locally and what CI runs cannot disagree:

```
make install-tools     # tfpfgen at TFPFGEN_REF; kiota must be on PATH at the locked version
make generate          # sdk-generate → init → draft → merge → bindings-check → scaffold → provider-generate → build → unittest
make unittest          # TestUnit_*  (no credentials)
make acctest           # TestAcc_*   (mutates the live tenant)
```

See the tfpfgen documentation for the full pipeline and its drift checks.
