#!/usr/bin/env bash
# ─── Dev Container Post-Create Setup ─────────────────────────────────────────
set -euo pipefail

echo "→ Installing pre-commit..."
pip install --quiet pre-commit

echo "→ Installing gitleaks..."
GITLEAKS_VERSION="8.18.3"
wget -q "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" -O /tmp/gitleaks.tar.gz
tar -xzf /tmp/gitleaks.tar.gz -C /tmp
sudo mv /tmp/gitleaks /usr/local/bin/
rm /tmp/gitleaks.tar.gz

echo "→ Installing kubelogin (Azure AD AKS auth)..."
az aks install-cli --only-show-errors || true

echo "→ Installing velero CLI..."
VELERO_VERSION="1.13.2"
wget -q "https://github.com/vmware-tanzu/velero/releases/download/v${VELERO_VERSION}/velero-v${VELERO_VERSION}-linux-amd64.tar.gz" -O /tmp/velero.tar.gz
tar -xzf /tmp/velero.tar.gz -C /tmp
sudo mv /tmp/velero-v${VELERO_VERSION}-linux-amd64/velero /usr/local/bin/
rm /tmp/velero.tar.gz

echo "→ Installing argocd CLI..."
wget -q "https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64" -O /usr/local/bin/argocd
chmod +x /usr/local/bin/argocd

echo "→ Setting up pre-commit hooks..."
cd /workspaces/DigitalFreelanceWorld/azure-aks-enterprise-platform && \
  pre-commit install && \
  pre-commit install --hook-type commit-msg || true

echo "✅ Dev container setup complete."
echo ""
echo "Quick start:"
echo "  make help           — see all available commands"
echo "  az login            — authenticate with Azure"
echo "  make plan ENV=dev   — run Terraform plan"
