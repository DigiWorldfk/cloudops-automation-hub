# ─────────────────────────────────────────────────────────────────────────────
# Private DNS Zone — MySQL Flexible Server uses VNet injection + private DNS
# ─────────────────────────────────────────────────────────────────────────────
resource "azurerm_private_dns_zone" "mysql" {
  name                = "${var.name_prefix}.mysql.database.azure.com"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "mysql" {
  name                  = "${var.name_prefix}-mysql-dns-link"
  private_dns_zone_name = azurerm_private_dns_zone.mysql.name
  resource_group_name   = var.resource_group_name
  virtual_network_id    = var.virtual_network_id
  registration_enabled  = false
  tags                  = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# MySQL Flexible Server
# ─────────────────────────────────────────────────────────────────────────────
resource "azurerm_mysql_flexible_server" "main" {
  name                   = "${var.name_prefix}-mysql"
  resource_group_name    = var.resource_group_name
  location               = var.location
  administrator_login    = var.administrator_login
  administrator_password = var.administrator_password   # sensitive — injected from Key Vault / CI
  sku_name               = var.sku_name
  version                = var.mysql_version
  zone                   = var.primary_zone

  # VNet injection — no public endpoint; server is only reachable inside the VNet
  delegated_subnet_id = var.mysql_subnet_id
  private_dns_zone_id = azurerm_private_dns_zone.mysql.id

  storage {
    size_gb           = var.storage_size_gb
    auto_grow_enabled = true
    iops              = var.storage_iops
  }

  backup {
    backup_retention_days        = var.backup_retention_days
    geo_redundant_backup_enabled = var.geo_redundant_backup
  }

  dynamic "high_availability" {
    for_each = var.high_availability_enabled ? [1] : []
    content {
      mode                      = "ZoneRedundant"
      standby_availability_zone = var.standby_zone
    }
  }

  maintenance_window {
    day_of_week  = 0   # Sunday
    start_hour   = 2
    start_minute = 0
  }

  tags = var.tags

  depends_on = [azurerm_private_dns_zone_virtual_network_link.mysql]
}

# ─────────────────────────────────────────────────────────────────────────────
# Firewall — deny all public access; VNet injection handles connectivity
# This rule allows nothing from the internet but is required by some Azure
# policies. The delegated subnet provides the actual connectivity.
# ─────────────────────────────────────────────────────────────────────────────
resource "azurerm_mysql_flexible_server_firewall_rule" "deny_all_public" {
  name                = "DenyAllPublicAccess"
  resource_group_name = var.resource_group_name
  server_name         = azurerm_mysql_flexible_server.main.name
  start_ip_address    = "0.0.0.0"
  end_ip_address      = "0.0.0.0"
}

# ─────────────────────────────────────────────────────────────────────────────
# Databases
# ─────────────────────────────────────────────────────────────────────────────
resource "azurerm_mysql_flexible_database" "databases" {
  for_each = toset(var.databases)

  name                = each.key
  resource_group_name = var.resource_group_name
  server_name         = azurerm_mysql_flexible_server.main.name
  charset             = "utf8mb4"
  collation           = "utf8mb4_unicode_ci"
}

# ─────────────────────────────────────────────────────────────────────────────
# Server configuration — harden defaults
# ─────────────────────────────────────────────────────────────────────────────
resource "azurerm_mysql_flexible_server_configuration" "require_secure_transport" {
  name                = "require_secure_transport"
  resource_group_name = var.resource_group_name
  server_name         = azurerm_mysql_flexible_server.main.name
  value               = "ON"
}

resource "azurerm_mysql_flexible_server_configuration" "tls_version" {
  name                = "tls_version"
  resource_group_name = var.resource_group_name
  server_name         = azurerm_mysql_flexible_server.main.name
  value               = "TLSv1.2,TLSv1.3"
}

resource "azurerm_mysql_flexible_server_configuration" "slow_query_log" {
  name                = "slow_query_log"
  resource_group_name = var.resource_group_name
  server_name         = azurerm_mysql_flexible_server.main.name
  value               = "ON"
}

resource "azurerm_mysql_flexible_server_configuration" "long_query_time" {
  name                = "long_query_time"
  resource_group_name = var.resource_group_name
  server_name         = azurerm_mysql_flexible_server.main.name
  value               = "2"   # log queries taking more than 2 seconds
}

resource "azurerm_mysql_flexible_server_configuration" "max_connections" {
  name                = "max_connections"
  resource_group_name = var.resource_group_name
  server_name         = azurerm_mysql_flexible_server.main.name
  value               = tostring(var.max_connections)
}

# ─────────────────────────────────────────────────────────────────────────────
# Key Vault Secret — store the connection string so AKS pods can read it
# via the CSI Key Vault driver (never stored in Kubernetes etcd unencrypted)
# ─────────────────────────────────────────────────────────────────────────────
resource "azurerm_key_vault_secret" "mysql_connection_string" {
  name         = "${var.name_prefix}-mysql-connection-string"
  key_vault_id = var.key_vault_id

  # jdbc-style connection string — applications read this at runtime
  value = "mysql://${var.administrator_login}:${var.administrator_password}@${azurerm_mysql_flexible_server.main.fqdn}:3306/${length(var.databases) > 0 ? var.databases[0] : "app"}?sslMode=REQUIRED"

  content_type = "connection-string"

  tags = merge(var.tags, {
    secret_type = "database-connection-string"
    server      = azurerm_mysql_flexible_server.main.name
  })
}

resource "azurerm_key_vault_secret" "mysql_admin_password" {
  name         = "${var.name_prefix}-mysql-admin-password"
  key_vault_id = var.key_vault_id
  value        = var.administrator_password
  content_type = "password"

  tags = merge(var.tags, {
    secret_type = "database-password"
    server      = azurerm_mysql_flexible_server.main.name
  })
}

# ─────────────────────────────────────────────────────────────────────────────
# Diagnostic Settings — ship MySQL logs to Log Analytics
# ─────────────────────────────────────────────────────────────────────────────
resource "azurerm_monitor_diagnostic_setting" "mysql" {
  name                       = "${var.name_prefix}-mysql-diag"
  target_resource_id         = azurerm_mysql_flexible_server.main.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "MySqlSlowLogs"
  }

  enabled_log {
    category = "MySqlAuditLogs"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
