terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }
}

# ─── Azure Container Registry ─────────────────────────────────────────────────
resource "azurerm_container_registry" "this" {
  name                          = var.acr_name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  sku                           = var.sku # Premium required for private endpoints + geo-replication
  admin_enabled                 = false   # Use managed identity, never admin credentials
  public_network_access_enabled = var.public_network_access_enabled
  zone_redundancy_enabled       = var.zone_redundancy_enabled

  # Retention policy — delete untagged manifests after N days
  retention_policy {
    days    = var.retention_days
    enabled = true
  }

  # Trust policy — content trust for image signing
  trust_policy {
    enabled = var.enable_content_trust
  }

  # Quarantine policy — images scanned before pushable to prod
  quarantine_policy_enabled = var.quarantine_policy_enabled

  # Export policy — prevent image export to untrusted registries
  export_policy_enabled = var.export_policy_enabled

  network_rule_set {
    default_action = var.public_network_access_enabled ? "Allow" : "Deny"

    dynamic "ip_rule" {
      for_each = var.allowed_ip_ranges
      content {
        action   = "Allow"
        ip_range = ip_rule.value
      }
    }

    dynamic "virtual_network" {
      for_each = var.allowed_subnet_ids
      content {
        action    = "Allow"
        subnet_id = virtual_network.value
      }
    }
  }

  tags = var.tags
}

# ─── Geo-Replication (Premium SKU only, for prod) ─────────────────────────────
resource "azurerm_container_registry_replication" "this" {
  for_each = toset(var.geo_replication_locations)

  name                    = each.value
  container_registry_name = azurerm_container_registry.this.name
  resource_group_name     = var.resource_group_name
  location                = each.value
  zone_redundancy_enabled = var.zone_redundancy_enabled

  tags = var.tags
}

# ─── Private Endpoint (for non-public registries) ─────────────────────────────
resource "azurerm_private_endpoint" "acr" {
  count = var.public_network_access_enabled ? 0 : 1

  name                = "pe-${var.acr_name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "psc-${var.acr_name}"
    private_connection_resource_id = azurerm_container_registry.this.id
    subresource_names              = ["registry"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = var.private_dns_zone_id != null ? [1] : []
    content {
      name                 = "acr-dns-zone-group"
      private_dns_zone_ids = [var.private_dns_zone_id]
    }
  }

  tags = var.tags
}

# ─── Private DNS Zone for ACR ─────────────────────────────────────────────────
resource "azurerm_private_dns_zone" "acr" {
  count = var.public_network_access_enabled ? 0 : var.create_private_dns_zone ? 1 : 0

  name                = "privatelink.azurecr.io"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "acr" {
  count = var.public_network_access_enabled ? 0 : var.create_private_dns_zone ? 1 : 0

  name                  = "link-acr-${var.acr_name}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.acr[0].name
  virtual_network_id    = var.vnet_id
  registration_enabled  = false
  tags                  = var.tags
}

# ─── AKS Pull Role Assignment ──────────────────────────────────────────────────
# Grant AKS kubelet identity AcrPull on this registry
resource "azurerm_role_assignment" "aks_acr_pull" {
  principal_id                     = var.aks_kubelet_identity_principal_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.this.id
  skip_service_principal_aad_check = true
}

# ─── Microsoft Defender for Containers ────────────────────────────────────────
resource "azurerm_security_center_subscription_pricing" "acr" {
  count         = var.enable_defender ? 1 : 0
  tier          = "Standard"
  resource_type = "ContainerRegistry"
}

# ─── Diagnostic Settings → Log Analytics ──────────────────────────────────────
resource "azurerm_monitor_diagnostic_setting" "acr" {
  name                       = "diag-${var.acr_name}"
  target_resource_id         = azurerm_container_registry.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log { category = "ContainerRegistryRepositoryEvents" }
  enabled_log { category = "ContainerRegistryLoginEvents" }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
