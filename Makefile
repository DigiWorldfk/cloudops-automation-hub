.PHONY: help bootstrap plan apply destroy fmt validate lint \
        aks-creds kubeconfig port-forward logs health \
        velero-install argocd-install otel-install \
        pre-commit-install pre-commit-run clean

SHELL := /bin/bash
ENV    ?= dev
ROOT   := $(shell pwd)
TF_DIR := $(ROOT)/terraform/environments/$(ENV)

# ─── Help ─────────────────────────────────────────────────────────────────────
help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-28s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "  Usage: make <target> ENV=<dev|staging|prod>"

# ─── Terraform ────────────────────────────────────────────────────────────────
bootstrap: ## Provision Terraform remote state storage (one-time)
	cd $(ROOT)/terraform/bootstrap && \
	terraform init && \
	terraform apply -auto-approve

fmt: ## Format all Terraform code
	terraform fmt -recursive $(ROOT)/terraform

validate: ## Validate all Terraform modules
	@for env in dev staging prod; do \
		echo "→ Validating $$env..."; \
		cd $(ROOT)/terraform/environments/$$env && \
		terraform init -backend=false -reconfigure && \
		terraform validate; \
	done

lint: ## Run tflint on all environments
	@which tflint || (echo "Install tflint: https://github.com/terraform-linters/tflint" && exit 1)
	@for env in dev staging prod; do \
		echo "→ Linting $$env..."; \
		cd $(ROOT)/terraform/environments/$$env && tflint; \
	done

plan: ## Terraform plan for ENV (default: dev). Requires backend.hcl
	@echo "Planning $(ENV)..."
	cd $(TF_DIR) && \
	terraform init -backend-config=backend.hcl -reconfigure && \
	terraform plan

apply: ## Terraform apply for ENV (default: dev). Requires backend.hcl
	@echo "Applying $(ENV)..."
	@if [ "$(ENV)" = "prod" ]; then \
		read -p "⚠️  You are about to apply to PROD. Type 'yes' to confirm: " confirm && \
		[ "$$confirm" = "yes" ] || (echo "Aborted." && exit 1); \
	fi
	cd $(TF_DIR) && \
	terraform init -backend-config=backend.hcl -reconfigure && \
	terraform apply

destroy: ## Terraform destroy for ENV (default: dev). Never run on prod without caution.
	@if [ "$(ENV)" = "prod" ]; then \
		echo "❌ Refusing to destroy prod via Makefile. Use terraform CLI directly." && exit 1; \
	fi
	cd $(TF_DIR) && terraform destroy

output: ## Show Terraform outputs for ENV
	cd $(TF_DIR) && terraform output

# ─── AKS ──────────────────────────────────────────────────────────────────────
aks-creds: ## Fetch AKS credentials and merge into kubeconfig
	@CLUSTER=$$(cd $(TF_DIR) && terraform output -raw aks_cluster_name) && \
	RG=$$(cd $(TF_DIR) && terraform output -raw resource_group_name 2>/dev/null || echo "rg-aks-$(ENV)") && \
	az aks get-credentials --resource-group $$RG --name $$CLUSTER --overwrite-existing
	@echo "✅ kubeconfig updated for $(ENV)"

port-forward: ## Port-forward ArgoCD UI to localhost:8080
	kubectl port-forward svc/argocd-server -n argocd 8080:443

logs: ## Stream backend pod logs
	kubectl logs -n backend -l app=backend -f --tail=100

health: ## Check all pod health across namespaces
	@for ns in frontend backend monitoring observability argocd velero; do \
		echo "=== $$ns ==="; \
		kubectl get pods -n $$ns 2>/dev/null || echo "(namespace not found)"; \
	done

# ─── Component Installers ─────────────────────────────────────────────────────
velero-install: ## Install Velero via Helm using Terraform outputs
	@echo "Installing Velero for $(ENV)..."
	@STORAGE_ACCOUNT=$$(cd $(TF_DIR) && terraform output -raw velero_storage_account) && \
	IDENTITY_CLIENT_ID=$$(cd $(TF_DIR) && terraform output -raw velero_identity_client_id) && \
	SUBSCRIPTION_ID=$$(az account show --query id -o tsv) && \
	helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts && \
	helm repo update && \
	helm upgrade --install velero vmware-tanzu/velero \
	  --namespace velero --create-namespace \
	  --set configuration.provider=azure \
	  --set configuration.backupStorageLocation.bucket=velero \
	  --set configuration.backupStorageLocation.config.storageAccount=$$STORAGE_ACCOUNT \
	  --set configuration.backupStorageLocation.config.subscriptionId=$$SUBSCRIPTION_ID \
	  --set serviceAccount.server.annotations."azure\.workload\.identity/client-id"=$$IDENTITY_CLIENT_ID \
	  --set podLabels."azure\.workload\.identity/use"=true \
	  --set credentials.useSecret=false \
	  --set initContainers[0].name=velero-plugin-for-microsoft-azure \
	  --set initContainers[0].image=velero/velero-plugin-for-microsoft-azure:v1.10.0 \
	  --set initContainers[0].volumeMounts[0].mountPath=/target \
	  --set initContainers[0].volumeMounts[0].name=plugins
	@echo "✅ Velero installed"

argocd-install: ## Install ArgoCD with RBAC config
	kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
	kubectl apply -f $(ROOT)/gitops/argocd/rbac.yaml
	kubectl apply -f $(ROOT)/gitops/applications/app-of-apps.yaml
	@echo "✅ ArgoCD installed. Run: make port-forward"

otel-install: ## Deploy OpenTelemetry collector DaemonSet
	kubectl apply -f $(ROOT)/kubernetes/monitoring/otel-collector.yaml
	@echo "✅ OpenTelemetry Collector deployed"

apply-k8s-policy: ## Apply all Kubernetes hardening policies
	kubectl apply -f $(ROOT)/kubernetes/policy/namespace-security.yaml
	kubectl apply -f $(ROOT)/kubernetes/policy/resource-quotas.yaml
	kubectl apply -f $(ROOT)/kubernetes/policy/pod-disruption-budgets.yaml
	kubectl apply -f $(ROOT)/kubernetes/network-policies/
	kubectl apply -f $(ROOT)/kubernetes/rbac/
	@echo "✅ Kubernetes policies applied"

# ─── Developer Tooling ────────────────────────────────────────────────────────
pre-commit-install: ## Install pre-commit hooks
	@which pre-commit || pip install pre-commit
	pre-commit install
	pre-commit install --hook-type commit-msg
	@echo "✅ Pre-commit hooks installed"

pre-commit-run: ## Run all pre-commit hooks on staged files
	pre-commit run --all-files

clean: ## Remove Terraform lock files and plan artifacts
	find $(ROOT)/terraform -name ".terraform.lock.hcl" -delete
	find $(ROOT)/terraform -name "tfplan" -delete
	find $(ROOT)/terraform -name "plan.json" -delete
	@echo "✅ Cleaned Terraform artifacts"
