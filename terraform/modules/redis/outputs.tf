output "redis_id" {
  value = azurerm_redis_cache.this.id
}

output "redis_name" {
  value = azurerm_redis_cache.this.name
}

output "hostname" {
  value = azurerm_redis_cache.this.hostname
}

output "ssl_port" {
  value = azurerm_redis_cache.this.ssl_port
}

output "connection_string_secret_name" {
  value = azurerm_key_vault_secret.redis_connection_string.name
}

output "redis_key_secret_name" {
  value = azurerm_key_vault_secret.redis_key.name
}

output "private_endpoint_id" {
  value = azurerm_private_endpoint.redis.id
}
