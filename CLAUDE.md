# Working in this repository

This repo is the **provider template**: the thing every generated Terraform
provider repository is stamped from. Nothing here is a provider. Everything
here is the contract a provider repo inherits on the day it is created —
`config.json`, the generate/probe pipeline, and the prose explaining both.

## This template must track the toolkit

The generator is
[`deploymenttheory/terraform-plugin-framework-codegen`](https://github.com/deploymenttheory/terraform-plugin-framework-codegen)
(tfpfgen). **A change there must be reflected here.**

The two repositories have no shared CI and nothing compares them, so drift is
silent. It does not surface in the toolkit's tests, and it does not surface
here — it surfaces as a failed pipeline in somebody's provider repo, weeks
later, with no obvious cause.

### What has to move

Anything this template hands to the toolkit or tells a user about it:

- `pipeline.yml` invokes the tfpfgen CLI directly — new verbs, renamed flags,
  and **changed flag defaults** all land here
- `config.json` must declare every key the pipeline reads, including keys only
  one auth method uses
- secret names must match exactly what the toolkit expects
- `CONFIGURING.md` must describe current behaviour, not previous behaviour

### The check worth running every time

Does `pipeline.yml` read a `config.json` key that `config.json` does not
declare?

```bash
grep -oE '\.(provider|openapi|sdk|generator|probe|auth)\.[a-zA-Z]+' \
  .github/workflows/pipeline.yml | sort -u
```

Compare that list against `config.json`. `jq` returns `null` for a missing key
rather than failing, so a gap does not announce itself — it produces an
empty argument in a generated pipeline and a confusing error much later.

## Placeholders are load-bearing

`config.json` ships with `PLACEHOLDER` values deliberately. They exist to fail
loudly on a first run that has not been configured. Do not replace them with
plausible-looking defaults; a wrong-but-working default is worse than a refusal,
because it generates a provider for the wrong API.

## Pull requests

Create pull requests; do not merge them. The repository owner merges.

Every change goes on its own branch cut fresh from `main` — never commit to
`main` directly.
