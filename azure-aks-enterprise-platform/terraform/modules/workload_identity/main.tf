terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.50"
    }
  }
}

# ─── User-Assigned Managed Identity per Workload ─────────────────────────────
# Each workload gets its own identity — follows principle of least privilege
resource "azurerm_user_assigned_identity" "this" {
  for_each = var.workloads

  name                = "id-${var.cluster_name}-${each.key}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

# ─── Federated Credentials ────────────────────────────────────────────────────
# Links the Kubernetes ServiceAccount to the Azure managed identity via OIDC
resource "azurerm_federated_identity_credential" "this" {
  for_each = var.workloads

  name                = "fic-${var.cluster_name}-${each.key}"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.this[each.key].id

  # AKS OIDC issuer URL — passed in from AKS module output
  issuer    = var.aks_oidc_issuer_url
  subject   = "system:serviceaccount:${each.value.namespace}:${each.value.service_account_name}"
  audience  = ["api://AzureADTokenExchange"]
}

# ─── Azure Role Assignments per Workload ──────────────────────────────────────
resource "azurerm_role_assignment" "this" {
  for_each = {
    for item in flatten([
      for workload_key, workload in var.workloads : [
        for role_idx, role in workload.azure_roles : {
          key          = "${workload_key}-${role_idx}"
          principal_id = azurerm_user_assigned_identity.this[workload_key].principal_id
          role         = role.role_definition_name
          scope        = role.scope
        }
      ]
    ]) : item.key => item
  }

  principal_id         = each.value.principal_id
  role_definition_name = each.value.role
  scope                = each.value.scope
  skip_service_principal_aad_check = true
}

# ─── Kubernetes RBAC — Namespace-Scoped Roles ─────────────────────────────────
# These are output as YAML for kubectl/ArgoCD — Terraform manages Azure side only
# See outputs for the ServiceAccount annotations to apply
