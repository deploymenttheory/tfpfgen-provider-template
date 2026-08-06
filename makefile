.DEFAULT_GOAL := all

.PHONY: all deps build install clean lint terraformfmt userdocs unittest acctest test \
	install-tools openapi-fetch sdk-generate init draft merge bindings-check scaffold provider-generate generate

all: build unittest

# ------------------------------------------------------------------------------
# Project shape. The provider name derives from the repository directory, the
# way the pipeline derives it from the repository name. The SDK settings come
# from the committed kiota-lock.json -- the same source of truth the pipeline
# reads -- so there is no second copy to drift.
# ------------------------------------------------------------------------------
PROVIDER_NAME  ?= $(patsubst terraform-provider-%,%,$(notdir $(CURDIR)))
OPENAPI_DIR    ?= openapi/$(PROVIDER_NAME)
BLUEPRINT_DIR  ?= blueprints/$(PROVIDER_NAME)
KIOTA_LOCK     := internal/sdk/kiota-lock.json
SDK_CLIENT_NAME ?= $(shell jq -r '.clientClassName // "ApiClient"' $(KIOTA_LOCK) 2>/dev/null || echo ApiClient)
SDK_INCLUDE    ?= $(shell jq -r '(.includePatterns // []) | join(",")' $(KIOTA_LOCK) 2>/dev/null)
SDK_EXCLUDE    ?= $(shell jq -r '(.excludePatterns // []) | join(",")' $(KIOTA_LOCK) 2>/dev/null)
TFPFGEN_REF    ?= main

# ------------------------------------------------------------------------------
# Everyday Go loop
# ------------------------------------------------------------------------------
deps:
	go version
	go mod tidy

build:
	$(MAKE) deps
	go build -o ./bin/

install:
	$(MAKE) deps
	go install

clean:
	go clean -testcache
	rm -rf ./bin

lint:
	golangci-lint run

terraformfmt:
	find . -type f -name "*.tf" -exec terraform fmt {} \;

userdocs:
	go generate .

# Test names follow the generated convention: TestUnit_* needs nothing,
# TestAcc_* mutates the live tenant and needs the provider's credential in the
# environment. Narrow either with TEST=..., e.g. make unittest TEST=_Client.
unittest:
	TF_ACC=0 go test -p 16 -timeout 10m -cover ./... -run "^TestUnit$(TEST)"

acctest:
	TF_ACC=1 go test -p 1 -timeout 90m -v ./... -run "^TestAcc$(TEST)"

test:
	$(MAKE) unittest

# ------------------------------------------------------------------------------
# The tfpfgen loop -- the same chain the generate pipeline runs, for driving it
# locally. kiota must be on PATH at the version the committed kiota-lock.json
# names; tfpfgen refuses otherwise. Nothing here is curated: blueprints are
# drafted canonically and pruned against the real SDK, the provider block and
# the shell are derived, and probe facts fold in from committed recordings.
# ------------------------------------------------------------------------------
install-tools:
	go install "github.com/deploymenttheory/terraform-plugin-framework-codegen/cmd/tfpfgen@$(TFPFGEN_REF)"
	tfpfgen version
	kiota --version

openapi-fetch:
	tfpfgen openapi fetch -out "$(OPENAPI_DIR)"

sdk-generate:
	go mod download all
	tfpfgen sdk generate -openapi-dir "$(OPENAPI_DIR)" -out internal/sdk \
		-client-name "$(SDK_CLIENT_NAME)" -clean \
		$(if $(SDK_INCLUDE),-include "$(SDK_INCLUDE)") \
		$(if $(SDK_EXCLUDE),-exclude "$(SDK_EXCLUDE)")

init:
	tfpfgen provider init -module . -name "$(PROVIDER_NAME)" \
		-openapi-dir "$(OPENAPI_DIR)" -out "$(BLUEPRINT_DIR)" -force

draft:
	@find "$(BLUEPRINT_DIR)/resources" "$(BLUEPRINT_DIR)/datasources" \
		-name '*.blueprint.json' -delete 2>/dev/null || true
	tfpfgen blueprint draft -openapi-dir "$(OPENAPI_DIR)" -sdk-dialect kiotaFluent \
		-sdk-models-package "$$(go list -m)/internal/sdk/models" \
		-out "$(BLUEPRINT_DIR)" -prune-module .

merge:
	@if [ -d "recordings/$(PROVIDER_NAME)" ]; then \
		for facts in recordings/$(PROVIDER_NAME)/*/*/facts.json; do \
			[ -e "$$facts" ] || continue; \
			[ "$$(jq 'length' "$$facts")" -eq 0 ] && continue; \
			echo "merging $$facts"; \
			tfpfgen blueprint merge -blueprint "$(BLUEPRINT_DIR)" \
				-facts "$$facts" -strategy apply -allow-conflicts; \
		done; \
	else echo "no recordings committed; blueprints stay spec-derived"; fi

bindings-check:
	tfpfgen bindings check -blueprint "$(BLUEPRINT_DIR)" -module .

scaffold:
	tfpfgen provider scaffold -blueprint "$(BLUEPRINT_DIR)" -out .

provider-generate:
	@if [ -d examples ]; then \
		grep -rL "Code generated" examples --include='*.tf' --include='*.sh' 2>/dev/null \
			| xargs rm -- 2>/dev/null || true; \
	fi
	tfpfgen provider generate -blueprint "$(BLUEPRINT_DIR)" -out . -clean || \
		(go mod tidy && tfpfgen provider generate -blueprint "$(BLUEPRINT_DIR)" -out . -clean)
	go mod tidy

generate:
	$(MAKE) sdk-generate
	$(MAKE) init
	$(MAKE) draft
	$(MAKE) merge
	$(MAKE) bindings-check
	$(MAKE) scaffold
	$(MAKE) provider-generate
	$(MAKE) build
	$(MAKE) unittest
