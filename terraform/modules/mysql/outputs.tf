output "server_id" {
  description = "Resource ID of the MySQL Flexible Server"
  value       = azurerm_mysql_flexible_server.main.id
}

output "server_name" {
  description = "Name of the MySQL Flexible Server"
  value       = azurerm_mysql_flexible_server.main.name
}

output "fqdn" {
  description = "Fully-qualified domain name of the MySQL server (private, resolved inside the VNet)"
  value       = azurerm_mysql_flexible_server.main.fqdn
}

output "private_dns_zone_id" {
  description = "Resource ID of the private DNS zone"
  value       = azurerm_private_dns_zone.mysql.id
}

output "databases" {
  description = "List of database names created on the server"
  value       = keys(azurerm_mysql_flexible_database.databases)
}

output "connection_string_secret_id" {
  description = "Key Vault secret ID for the MySQL connection string (use with CSI Key Vault driver)"
  value       = azurerm_key_vault_secret.mysql_connection_string.id
}

output "connection_string_secret_name" {
  description = "Key Vault secret name for the MySQL connection string"
  value       = azurerm_key_vault_secret.mysql_connection_string.name
}

output "admin_password_secret_name" {
  description = "Key Vault secret name for the MySQL admin password"
  value       = azurerm_key_vault_secret.mysql_admin_password.name
}
