terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }
}

# ─── Private DNS Zone for Redis ───────────────────────────────────────────────
resource "azurerm_private_dns_zone" "redis" {
  name                = "privatelink.redis.cache.windows.net"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "redis" {
  name                  = "link-redis-${var.name}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.redis.name
  virtual_network_id    = var.vnet_id
  registration_enabled  = false
  tags                  = var.tags
}

# ─── Redis Cache ──────────────────────────────────────────────────────────────
resource "azurerm_redis_cache" "this" {
  name                          = "redis-${var.name}"
  resource_group_name           = var.resource_group_name
  location                      = var.location
  capacity                      = var.capacity
  family                        = var.family
  sku_name                      = var.sku_name
  public_network_access_enabled = false # Always private
  minimum_tls_version           = "1.2"

  # Non-SSL port disabled — TLS only
  enable_non_ssl_port = false

  redis_configuration {
    # Auth: AAD-based authentication via Entra ID (preview) or access keys via Key Vault
    # Persistence for reliability
    rdb_backup_enabled            = var.sku_name == "Premium" ? var.enable_persistence : false
    rdb_backup_frequency          = var.sku_name == "Premium" ? var.backup_frequency_minutes : null
    rdb_backup_max_snapshot_count = var.sku_name == "Premium" ? 1 : null
    maxmemory_policy              = var.maxmemory_policy # allkeys-lru recommended for session cache
  }

  zones = var.zones # Zone redundancy for Premium SKU

  patch_schedule {
    day_of_week    = "Sunday"
    start_hour_utc = 2
  }

  tags = var.tags
}

# ─── Private Endpoint ─────────────────────────────────────────────────────────
resource "azurerm_private_endpoint" "redis" {
  name                = "pe-redis-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "psc-redis-${var.name}"
    private_connection_resource_id = azurerm_redis_cache.this.id
    subresource_names              = ["redisCache"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "redis-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.redis.id]
  }

  tags = var.tags
}

# ─── Store Redis connection string in Key Vault ───────────────────────────────
resource "azurerm_key_vault_secret" "redis_connection_string" {
  name         = "redis-connection-string"
  value        = "${azurerm_redis_cache.this.hostname}:${azurerm_redis_cache.this.ssl_port},password=${azurerm_redis_cache.this.primary_access_key},ssl=True,abortConnect=False"
  key_vault_id = var.key_vault_id

  content_type = "text/plain"
  tags         = var.tags
}

resource "azurerm_key_vault_secret" "redis_host" {
  name         = "redis-host"
  value        = azurerm_redis_cache.this.hostname
  key_vault_id = var.key_vault_id
  tags         = var.tags
}

resource "azurerm_key_vault_secret" "redis_key" {
  name         = "redis-primary-key"
  value        = azurerm_redis_cache.this.primary_access_key
  key_vault_id = var.key_vault_id

  content_type = "text/plain"
  tags         = var.tags
}

# ─── Diagnostic Settings ──────────────────────────────────────────────────────
resource "azurerm_monitor_diagnostic_setting" "redis" {
  name                       = "diag-redis-${var.name}"
  target_resource_id         = azurerm_redis_cache.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log { category = "ConnectedClientList" }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
