# OPA/Conftest policies for Terraform plan validation
# Run with: conftest test plan.json --policy policies/
#
# These policies enforce security guardrails before any Terraform apply.
# They evaluate the JSON Terraform plan output (terraform show -json tfplan).

package main

import future.keywords.if
import future.keywords.in

# ─── Helpers ─────────────────────────────────────────────────────────────────

# All resources being created or updated in the plan
planned_resources[resource] {
  resource := input.resource_changes[_]
  resource.change.actions[_] in ["create", "update"]
}

# ─── Rule 1: MySQL must enforce TLS ──────────────────────────────────────────
deny[msg] {
  resource := planned_resources[_]
  resource.type == "azurerm_mysql_flexible_server_configuration"
  resource.change.after.name == "require_secure_transport"
  resource.change.after.value == "OFF"
  msg := sprintf("DENY: MySQL '%s' has require_secure_transport=OFF. TLS is mandatory.", [resource.name])
}

# ─── Rule 2: Storage accounts must enforce HTTPS ─────────────────────────────
deny[msg] {
  resource := planned_resources[_]
  resource.type == "azurerm_storage_account"
  resource.change.after.https_traffic_only_enabled == false
  msg := sprintf("DENY: Storage account '%s' does not enforce HTTPS-only traffic.", [resource.name])
}

# ─── Rule 3: Storage accounts min TLS version must be 1.2 ───────────────────
deny[msg] {
  resource := planned_resources[_]
  resource.type == "azurerm_storage_account"
  resource.change.after.min_tls_version != "TLS1_2"
  msg := sprintf("DENY: Storage account '%s' must use min TLS 1.2 (found: %s).", [resource.name, resource.change.after.min_tls_version])
}

# ─── Rule 4: Storage containers must NOT be publicly accessible ──────────────
deny[msg] {
  resource := planned_resources[_]
  resource.type == "azurerm_storage_container"
  resource.change.after.container_access_type != "private"
  msg := sprintf("DENY: Storage container '%s' has public access type '%s'. Must be 'private'.", [resource.name, resource.change.after.container_access_type])
}

# ─── Rule 5: AKS must have OIDC issuer enabled ───────────────────────────────
deny[msg] {
  resource := planned_resources[_]
  resource.type == "azurerm_kubernetes_cluster"
  resource.change.after.oidc_issuer_enabled != true
  msg := sprintf("DENY: AKS cluster '%s' must have oidc_issuer_enabled = true for workload identity.", [resource.name])
}

# ─── Rule 6: AKS must have workload identity enabled ─────────────────────────
deny[msg] {
  resource := planned_resources[_]
  resource.type == "azurerm_kubernetes_cluster"
  resource.change.after.workload_identity_enabled != true
  msg := sprintf("DENY: AKS cluster '%s' must have workload_identity_enabled = true.", [resource.name])
}

# ─── Rule 7: AKS must have Azure AD RBAC enabled ─────────────────────────────
deny[msg] {
  resource := planned_resources[_]
  resource.type == "azurerm_kubernetes_cluster"
  not resource.change.after.azure_active_directory_role_based_access_control
  msg := sprintf("DENY: AKS cluster '%s' must have Azure AD RBAC configured.", [resource.name])
}

# ─── Rule 8: Key Vault must have RBAC authorization enabled ──────────────────
deny[msg] {
  resource := planned_resources[_]
  resource.type == "azurerm_key_vault"
  resource.change.after.enable_rbac_authorization != true
  msg := sprintf("DENY: Key Vault '%s' must use RBAC authorization (not access policies).", [resource.name])
}

# ─── Rule 9: Key Vault must have soft delete ─────────────────────────────────
deny[msg] {
  resource := planned_resources[_]
  resource.type == "azurerm_key_vault"
  resource.change.after.soft_delete_retention_days < 7
  msg := sprintf("DENY: Key Vault '%s' must have soft_delete_retention_days >= 7.", [resource.name])
}

# ─── Rule 10: Redis must not allow non-SSL connections ───────────────────────
deny[msg] {
  resource := planned_resources[_]
  resource.type == "azurerm_redis_cache"
  resource.change.after.enable_non_ssl_port == true
  msg := sprintf("DENY: Redis cache '%s' must not enable non-SSL port.", [resource.name])
}

# ─── Rule 11: Redis must not allow public network access ─────────────────────
deny[msg] {
  resource := planned_resources[_]
  resource.type == "azurerm_redis_cache"
  resource.change.after.public_network_access_enabled == true
  msg := sprintf("DENY: Redis cache '%s' must have public_network_access_enabled = false.", [resource.name])
}

# ─── Rule 12: Container Registry must have admin account disabled ────────────
deny[msg] {
  resource := planned_resources[_]
  resource.type == "azurerm_container_registry"
  resource.change.after.admin_enabled == true
  msg := sprintf("DENY: ACR '%s' must have admin_enabled = false. Use RBAC/managed identity instead.", [resource.name])
}

# ─── Warnings (non-blocking) ─────────────────────────────────────────────────

warn[msg] {
  resource := planned_resources[_]
  resource.type == "azurerm_kubernetes_cluster"
  not resource.change.after.automatic_channel_upgrade
  msg := sprintf("WARN: AKS cluster '%s' does not have automatic_channel_upgrade configured.", [resource.name])
}

warn[msg] {
  resource := planned_resources[_]
  resource.type == "azurerm_mysql_flexible_server"
  resource.change.after.backup_retention_days < 7
  msg := sprintf("WARN: MySQL server '%s' has backup_retention_days < 7.", [resource.name])
}
