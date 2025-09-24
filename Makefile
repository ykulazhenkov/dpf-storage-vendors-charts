#
#Copyright 2025 NVIDIA
#
#Licensed under the Apache License, Version 2.0 (the "License");
#you may not use this file except in compliance with the License.
#You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
#Unless required by applicable law or agreed to in writing, software
#distributed under the License is distributed on an "AS IS" BASIS,
#WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#See the License for the specific language governing permissions and
#limitations under the License.

# Get the directory of this Makefile, regardless of where make was invoked
PROJECT_DIR := $(shell cd $(dir $(lastword $(MAKEFILE_LIST))) && pwd -L)
PROJECT_DIR := $(patsubst %/,%,$(PROJECT_DIR))

# Export is needed here so that the envsubst used in make targets has access to those variables even when they are not
# explicitly set when calling make.
export TAG ?= v0.0.1
export REGISTRY ?= example.com


# By default the helm registry is assumed to be an OCI registry.
export HELM_REGISTRY ?= oci://$(REGISTRY)

# Chart configuration
CHARTS_DIR = $(PROJECT_DIR)/charts
CHARTS_OUTPUT_DIR = $(PROJECT_DIR)/output

# Detect architecture and platform
TOOL_ARCH ?= $(shell uname -m)
TOOL_OS ?= $(shell uname -s | tr A-Z a-z)

HELM_ARCH = $(TOOL_ARCH)
ifeq ($(TOOL_ARCH),x86_64)
  HELM_ARCH = amd64
else ifeq ($(TOOL_ARCH),aarch64)
  HELM_ARCH = arm64
endif

# Tool versions
HELM_VER ?= v3.18.3
HELM_CM_PUSH_VERSION ?= 0.10.4

# Tool binaries
TOOLSDIR = $(PROJECT_DIR)/bin
HELM ?= $(TOOLSDIR)/helm-$(HELM_VER)

# Setting SHELL to bash allows bash commands to be executed by recipes.
SHELL = /usr/bin/env bash -o pipefail
.SHELLFLAGS = -ec

##@ General

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

$(TOOLSDIR) $(CHARTS_OUTPUT_DIR):
	@mkdir -p $@

##@ Tools

.PHONY: helm
helm: $(HELM) ## Download helm locally if necessary.
$(HELM): | $(TOOLSDIR)
	@echo "Installing helm-$(HELM_VER) to $(TOOLSDIR)"
	@curl -fsSL https://get.helm.sh/helm-$(HELM_VER)-$(TOOL_OS)-$(HELM_ARCH).tar.gz | tar -xzf - --no-same-owner -C $(TOOLSDIR) --strip-components=1
	@mv $(TOOLSDIR)/helm $(HELM)
	@chmod +x $(HELM)

.PHONY: helm-cm-push
helm-cm-push: helm
	@$(HELM) plugin list | grep cm-push | grep $(HELM_CM_PUSH_VERSION) || \
		( \
			($(HELM) plugin uninstall cm-push || true) && \
			$(HELM) plugin install https://github.com/chartmuseum/helm-push --version $(HELM_CM_PUSH_VERSION) \
		)

##@ Helm

HELM_PUSH_CMD ?= $(shell if echo $(HELM_REGISTRY) | grep -q '^http'; then echo cm-push; else echo push; fi)

# Individual chart targets

# spdk-csi-controller chart
.PHONY: helm-package-spdk-csi-controller
helm-package-spdk-csi-controller: $(CHARTS_OUTPUT_DIR) helm ## Package spdk-csi-controller chart
	$(HELM) package $(CHARTS_DIR)/spdk-csi-controller --destination $(CHARTS_OUTPUT_DIR) --version $(TAG)

.PHONY: helm-push-spdk-csi-controller
helm-push-spdk-csi-controller: helm-package-spdk-csi-controller helm-cm-push ## Package and push spdk-csi-controller chart
	$(HELM) $(HELM_PUSH_CMD) $(CHARTS_OUTPUT_DIR)/spdk-csi-controller-$(TAG).tgz $(HELM_REGISTRY)

.PHONY: lint-spdk-csi-controller
lint-spdk-csi-controller: helm ## Run helm lint on spdk-csi-controller chart
	$(HELM) lint $(CHARTS_DIR)/spdk-csi-controller

.PHONY: template-spdk-csi-controller
template-spdk-csi-controller: helm ## Run helm template on spdk-csi-controller chart
	$(HELM) template --set dpu.enabled=true $(CHARTS_DIR)/spdk-csi-controller
	$(HELM) template --set host.enabled=true --set host.config.dpuClusterSecret=test-secret $(CHARTS_DIR)/spdk-csi-controller

# nfs-csi-controller chart
.PHONY: helm-package-nfs-csi-controller
helm-package-nfs-csi-controller: $(CHARTS_OUTPUT_DIR) helm ## Package nfs-csi-controller chart
	$(HELM) package $(CHARTS_DIR)/nfs-csi-controller --destination $(CHARTS_OUTPUT_DIR) --version $(TAG)

.PHONY: helm-push-nfs-csi-controller
helm-push-nfs-csi-controller: helm-package-nfs-csi-controller helm-cm-push ## Package and push nfs-csi-controller chart
	$(HELM) $(HELM_PUSH_CMD) $(CHARTS_OUTPUT_DIR)/nfs-csi-controller-$(TAG).tgz $(HELM_REGISTRY)

.PHONY: lint-nfs-csi-controller
lint-nfs-csi-controller: helm ## Run helm lint on nfs-csi-controller chart
	$(HELM) lint $(CHARTS_DIR)/nfs-csi-controller

.PHONY: template-nfs-csi-controller
template-nfs-csi-controller: helm ## Run helm template on nfs-csi-controller chart
	$(HELM) template --set dpu.enabled=true $(CHARTS_DIR)/nfs-csi-controller
	$(HELM) template --set host.enabled=true --set host.config.dpuClusterSecret=test-secret $(CHARTS_DIR)/nfs-csi-controller


.PHONY: helm-package
helm-package: helm-package-spdk-csi-controller helm-package-nfs-csi-controller ## Package all helm charts

.PHONY: helm-push
helm-push: helm-push-spdk-csi-controller helm-push-nfs-csi-controller ## Push all helm charts

.PHONY: lint
lint: lint-spdk-csi-controller lint-nfs-csi-controller ## Run helm lint to validate all charts

.PHONY: template
template: template-spdk-csi-controller template-nfs-csi-controller ## Run helm template to generate all charts

.PHONY: clean
clean: ## Clean generated files
	@rm -rf $(CHARTS_OUTPUT_DIR)
	@rm -rf $(TOOLSDIR)
