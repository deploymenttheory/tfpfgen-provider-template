.DEFAULT_GOAL := all

.PHONY: all deps build install clean lint terraformfmt userdocs unittest acctest test \
	install-tools openapi-fetch sdk-generate draft bindings-check provider-generate generate

all: build unittest

# ------------------------------------------------------------------------------
# Project shape. The provider name derives from the repository directory, the
# way the pipeline derives it from the repository name; the SDK values mirror
# the pipeline's dispatch inputs.
# ------------------------------------------------------------------------------
PROVIDER_NAME  ?= $(patsubst terraform-provider-%,%,$(notdir $(CURDIR)))
OPENAPI_DIR    ?= openapi/$(PROVIDER_NAME)
BLUEPRINT_DIR  ?= blueprints/$(PROVIDER_NAME)
SDK_CLIENT_NAME ?= ApiClient
SDK_EXCLUDE    ?=
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
# names; tfpfgen refuses otherwise.
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
		$(if $(SDK_EXCLUDE),-exclude "$(SDK_EXCLUDE)")

draft:
	tfpfgen blueprint draft -openapi-dir "$(OPENAPI_DIR)" -sdk-dialect kiotaFluent \
		-sdk-models-package "$$(go list -m)/internal/sdk/models" -out "$(BLUEPRINT_DIR)"

bindings-check:
	tfpfgen bindings check -blueprint "$(BLUEPRINT_DIR)" -module .

provider-generate:
	tfpfgen provider generate -blueprint "$(BLUEPRINT_DIR)" -out . || \
		(go mod tidy && tfpfgen provider generate -blueprint "$(BLUEPRINT_DIR)" -out .)
	go mod tidy

generate:
	$(MAKE) sdk-generate
	$(MAKE) bindings-check
	$(MAKE) provider-generate
	$(MAKE) build
	$(MAKE) unittest
