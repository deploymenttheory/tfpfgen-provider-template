# Configuring the pipeline

Everything the generator needs to know about your API lives in one committed
file: **`config.json`** at the repository root. The pipeline reads it on every
run. Nothing else configures generation — no dispatch form to fill in, no
settings held in somebody's memory.

That is the point of the file. A setting typed into a form each run is a
setting that will one day be typed wrong, and the wrong value will be
indistinguishable from a deliberate one. A setting in `config.json` arrives
through a pull request: it can be reviewed, explained in a commit message,
compared against the last version, and reverted.

## The shape of the file

```json
{
  "provider": {
    "name": "PLACEHOLDER"
  },
  "openapi": {
    "documentUrl": "https://example.com/path/to/api.yaml"
  },
  "sdk": {
    "clientTypeName": "ApiClient",
    "includeOnlyPaths": [],
    "skipPaths": [
      "/endpoint/tests/dynamic-tests/**"
    ],
    "kiotaVersion": "1.34.1",
    "kiotaDownloadChecksum": ""
  },
  "generator": {
    "version": "main"
  },
  "probe": {
    "namePrefix": "tfpfgen-probe",
    "maxExistingObjects": 25,
    "accountScopeParam": "aid",
    "accountScopeJsonPath": "aid"
  }
}
```

## What each setting does

### `provider.name`

The provider's registry name, which also names `openapi/<name>/` and
`blueprints/<name>/`. Defaults to this repository's name without the
`terraform-provider-` prefix, which is almost always right — set it only when
the provider should be called something else.

### `openapi.documentUrl`

**The one setting you must supply.** The API's OpenAPI (Swagger) document.
The first run downloads it and pins a checksummed copy under
`openapi/<name>/`; later runs re-fetch from the same address to notice when
the vendor changes it.

If the document is not reachable anonymously — it needs a login, or it is
generated internally — leave this empty and pin the snapshot from your own
machine instead:

```
tfpfgen openapi fetch -url <url> -out openapi/<name>
```

then commit the result. The pipeline uses the pinned copy and never needs the
address.

### `sdk.clientTypeName`

What to call the generated Go client type, e.g. `ThousandEyesClient`. Cosmetic
— it appears throughout the generated SDK — but changing it later rewrites
every file that names it, so it is worth choosing once.

### `sdk.includeOnlyPaths` and `sdk.skipPaths`

Which parts of the API become SDK code, as lists of path globs:

```json
"includeOnlyPaths": ["/tags", "/tags/**"],
"skipPaths": ["/endpoint/agents/transfer/**"]
```

Leave `includeOnlyPaths` empty to take the whole document, which is the usual
choice. `skipPaths` is for endpoints that break generation or that this
provider will never manage; each one you add is a piece of the API the
provider cannot reach, so prefer skipping narrowly and say why in the commit.

### `sdk.kiotaVersion`

Which release of [Microsoft Kiota](https://github.com/microsoft/kiota) builds
the SDK. Pinned rather than floating because a different version rewrites the
whole SDK tree, and an unexplained thousand-file diff is worse than an old
generator. The committed `internal/sdk/kiota-lock.json` records the version
that actually produced the current SDK; the generator refuses to run a
different one, so raising this here is how you deliberately take an upgrade.

### `sdk.kiotaDownloadChecksum`

Optional. The expected SHA-256 of the Kiota release archive. When set, a run
whose download does not match fails instead of generating from an unexpected
binary. Every run prints the digest it computed, so the value to paste here is
in the log of any successful run.

### `generator.version`

Which release of `tfpfgen` runs the pipeline: a tag, branch or commit. `main`
follows the generator as it improves. Pin a tag when you want the provider to
stop moving underneath you.

### `probe` (only used when you run the probe)

The probe creates and deletes real objects in a sandbox tenant to learn how the
API actually behaves. These settings say how to reach it and bound what it may
do; the credentials themselves are repository secrets, never config.

```json
"probe": {
  "authMethod": "bearerToken",
  "secrets": { "token": "TFPFGEN_PROBE_TOKEN" },
  "namePrefix": "tfpfgen-probe",
  "maxExistingObjects": 25,
  "accountScopeParam": "",
  "accountScopeJsonPath": ""
}
```

**`authMethod`** is how the probe proves who it is, and it takes the same three
values the generated provider supports:

| Method | Secrets it reads | Notes |
|---|---|---|
| `bearerToken` | `token` | The default. A static token. |
| `clientCredentials` | `clientId`, `clientSecret` | The probe exchanges them for a token before it starts. Add `"tokenUrl"` here if the exchange happens somewhere other than the `auth.tokenUrl` above; a path is resolved against the endpoint. |
| `usernamePassword` | `username`, `password` | Sent as HTTP Basic. |

**`secrets`** maps each credential the method needs onto the **name of a
repository secret** — never the value. The defaults are
`TFPFGEN_PROBE_TOKEN`, `TFPFGEN_PROBE_CLIENT_ID`,
`TFPFGEN_PROBE_CLIENT_SECRET`, `TFPFGEN_PROBE_USERNAME` and
`TFPFGEN_PROBE_PASSWORD`, so most repositories can leave this out entirely and
just create the secrets. Name them here when your organisation's secrets are
called something else.

The pipeline checks only the secrets the chosen method actually needs, so an
API that issues no tokens is not refused for lacking one, and it reports every
missing secret at once rather than one per run.

The rest bound what the probe may do:

| Setting | Meaning |
|---|---|
| `namePrefix` | Every object the probe creates is named with this prefix, so anything it leaves behind is identifiable as its own |
| `maxExistingObjects` | The probe refuses to run if the tenant already holds more than this many objects — the cheapest evidence that a tenant is a sandbox and not production |
| `accountScopeParam` | The query parameter that scopes requests to one account, if the API has one (`aid` for Jamf Pro and ThousandEyes, for example). Omit when it does not |
| `accountScopeJsonPath` | The field in a response carrying that account identifier, used to confirm the probe is talking to the tenant it was pointed at |

## Making a change

1. Edit `config.json` and open a pull request. The change is small and the
   reason belongs in the commit message.
2. Merge it, then run **`tfpfgen | Pipeline`** (Actions → tfpfgen | Pipeline →
   Run workflow). It reads the new config and proposes whatever the change
   implies as its own pull request.

The dispatch form asks only about the run itself: whether to probe the live
API first, whether to limit that to one resource, whether to re-record
evidence it already has, and — rarely — a generator version to try without
committing it. Everything declarative is in the file.

## What is not configured here

- **Credentials.** Repository secrets. The probe always needs
  `TFPFGEN_PROBE_ENDPOINT`, `TFPFGEN_SANDBOX_EVIDENCE` and
  `TFPFGEN_ACCOUNT_GROUP_ID`, plus whichever credential secrets its
  `authMethod` names above. Releases need `GPG_PRIVATE_KEY` and
  `GPG_PRIVATE_KEY_PASSPHRASE`.

  `config.json` names secrets; it never holds them.
- **What the provider looks like.** Which resources exist, what their
  attributes are called, how they are validated: all derived from the API
  document and from recorded evidence, not chosen here.
- **Corrections to the API document.** When the published document is provably
  wrong about the live API, that goes in `openapi/<name>/patches/` as a patch
  carrying the evidence that justifies it.
