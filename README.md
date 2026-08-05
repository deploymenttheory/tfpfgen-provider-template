# tfpfgen provider template

A template repository for building a Terraform provider with
[tfpfgen](https://github.com/deploymenttheory/terraform-plugin-framework-codegen):
point it at any OpenAPI document and the pipeline pins a snapshot, generates a
Go SDK with Microsoft Kiota, drafts blueprints, and — once the blueprints are
curated — regenerates the provider in place.

## Getting started

1. **Create a repository from this template.** Name it
   `terraform-provider-<name>` — the Terraform Registry conventions, the
   release packaging and the docs generation all derive the provider name from
   the repository name.
2. **Run the `tfpfgen | Generate` workflow** (Actions → tfpfgen | Generate →
   Run workflow) with at least:
   - `provider_name` — e.g. `thousandeyes`
   - `openapi_url` — the OpenAPI document to pin (first run only; later runs
     re-fetch from the pinned source)

   The run opens a pull request holding the pinned snapshot
   (`openapi/<name>/`), the generated SDK (`internal/sdk/`), and drafted
   resource blueprints (`blueprints/<name>/`). It also claims the Go module
   path from the repository name on the first run.
3. **Curate.** Drafted blueprints are proposals: probe the live API with
   `tfpfgen probe record`, fold the evidence in with `tfpfgen blueprint merge`,
   author the provider block (`blueprints/<name>/provider.blueprint.json` —
   the one file drafting never writes, and the pipeline's readiness signal),
   and commit. From then on every pipeline run regenerates the provider from
   the curated blueprints — `bindings check`, `provider generate`, build and
   tests.
4. **Release.** Push a `v*` tag (or dispatch `provider | Terraform Provider
   Release`). goreleaser builds linux/darwin/windows on amd64/arm64, with the
   signed checksums and registry manifest the Terraform Registry requires.

## Secrets to configure

| Secret | Needed by | Purpose |
|---|---|---|
| `GPG_PRIVATE_KEY` | release | signs the checksums (registry requirement) |
| `GPG_PRIVATE_KEY_PASSPHRASE` | release | only if the key has one |

The generation pipeline needs no secrets: it uses the workflow's own
`GITHUB_TOKEN` to open pull requests, and the OpenAPI document is fetched
anonymously. If your document needs credentials, pin it locally with
`tfpfgen openapi fetch` and commit the snapshot instead.

## Layout

| Path | Owner | Written by |
|---|---|---|
| `openapi/<name>/` | pipeline | `tfpfgen openapi fetch` — pinned, checksummed snapshots |
| `openapi/<name>/patches/` | you | document patches: curated, evidence-justified corrections |
| `internal/sdk/` | pipeline | `tfpfgen sdk generate` — the embedded Kiota SDK |
| `blueprints/<name>/` | you | curated blueprints (drafted by the pipeline, curated by you; the provider block is always hand-authored) |
| everything `provider generate` emits | pipeline | regenerated on every run; edit blueprints, not output |
| `go.mod`, `main.go`, scaffolds | you | generated once (or shipped here), then yours |

See the tfpfgen documentation for the full pipeline:
`openapi fetch → sdk generate → blueprint draft → probe record → blueprint
merge → provider generate`, with drift checks (`-check`) on every generating
stage.
