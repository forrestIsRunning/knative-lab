.PHONY: create delete nodes status context-check register unregister help \
	kubeconfig verify load-image

# Do not export KUBECONFIG. A global export leaks into kubectl --kubeconfig
# calls against ~/.kube/config and can rewrite current-context.
include versions.env

LAB_KUBECONFIG := $(CURDIR)/.kube/config
SYS_KUBECONFIG := $(HOME)/.kube/config
CLUSTER := $(CLUSTER_NAME)
CONTEXT := $(KUBE_CONTEXT)
KIND_CONFIG := cluster/kind.yaml
KUBECTL_LAB := kubectl --kubeconfig $(LAB_KUBECONFIG)
KUBECTL_SYS := env -u KUBECONFIG kubectl --kubeconfig $(SYS_KUBECONFIG)
KIND := env -u KUBECONFIG kind

# Docker Desktop CLI. A leftover OrbStack symlink at /usr/local/bin/docker is broken.
ifneq ($(wildcard /Applications/Docker.app/Contents/Resources/bin/docker),)
export PATH := /Applications/Docker.app/Contents/Resources/bin:$(PATH)
endif

help:
	@echo "Targets:"
	@echo "  make create         - kind cluster $(CLUSTER) if missing, then install Serving + Istio"
	@echo "  make register       - add $(CONTEXT) to kubectx, keep current-context"
	@echo "  make nodes          - kubectl get nodes -o wide"
	@echo "  make status         - nodes + istio-system + knative-serving pods"
	@echo "  make verify         - apply manifests/echo-server.yaml and curl the gateway"
	@echo "  make context-check  - system current-context vs lab kubeconfig"
	@echo "  make unregister     - remove $(CONTEXT) from ~/.kube/config"
	@echo "  make delete         - delete kind cluster $(CLUSTER) + unregister"
	@echo ""
	@echo "  make load-image IMG=<ref>  - host docker pull + import into kind nodes"
	@echo "  make kubeconfig            - write $(LAB_KUBECONFIG) without touching current-context"
	@echo ""
	@echo "make create does not delete an existing cluster named $(CLUSTER)."
	@echo "Host ports are $(HOST_HTTP_PORT) and $(HOST_HTTPS_PORT). 8080/8443 belong to k8s-lab."
	@echo "kind create writes $(LAB_KUBECONFIG), then register merges into $(SYS_KUBECONFIG)."
	@echo "kind export kubeconfig --name $(CLUSTER) also switches current-context;"
	@echo "use make register instead."

create:
	./cluster/up.sh
	@$(MAKE) register
	@$(MAKE) nodes
	@$(MAKE) context-check

kubeconfig:
	@mkdir -p .kube
	$(KIND) get kubeconfig --name $(CLUSTER) > $(LAB_KUBECONFIG)
	@chmod 600 $(LAB_KUBECONFIG)

register:
	@test -n "$$($(KIND) get clusters | grep -x $(CLUSTER))" || (echo "kind cluster $(CLUSTER) is not present" >&2; exit 1)
	@mkdir -p "$(dir $(SYS_KUBECONFIG))"
	@current=$$($(KUBECTL_SYS) config current-context 2>/dev/null || true); \
	$(KIND) export kubeconfig --name $(CLUSTER) --kubeconfig $(SYS_KUBECONFIG); \
	if [ -z "$$current" ]; then \
	  echo "registered $(CONTEXT); no previous current-context"; \
	else \
	  $(KUBECTL_SYS) config use-context "$$current" >/dev/null; \
	  got=$$($(KUBECTL_SYS) config current-context); \
	  if [ "$$got" != "$$current" ]; then \
	    echo "ERROR: current-context is $$got, expected $$current"; \
	    exit 1; \
	  fi; \
	  echo "registered $(CONTEXT); current-context still $$got"; \
	fi

unregister:
	@bash -c 'source cluster/lib.sh && unregister_system_context'
	@echo "unregistered $(CONTEXT)"

nodes: kubeconfig
	$(KUBECTL_LAB) get nodes -o wide

status: kubeconfig
	$(KUBECTL_LAB) get nodes -o wide
	$(KUBECTL_LAB) get pods -n istio-system
	$(KUBECTL_LAB) get pods -n knative-serving

context-check:
	@echo "system current-context: $$($(KUBECTL_SYS) config current-context)"
	@echo "lab current-context:    $$($(KUBECTL_LAB) config current-context 2>/dev/null || echo '(missing)')"
	@$(KUBECTL_SYS) config get-contexts -o name | grep -qx $(CONTEXT) \
		&& echo "kubectx has $(CONTEXT)" \
		|| echo "kubectx missing $(CONTEXT) (run make register)"

verify:
	./cluster/verify.sh

delete:
	./cluster/down.sh

load-image:
	@test -n "$(IMG)" || (echo "IMG=<image> required" >&2; exit 2)
	KIND_CLUSTER_NAME=$(CLUSTER) ./scripts/kind-load-image.sh $(IMG)
