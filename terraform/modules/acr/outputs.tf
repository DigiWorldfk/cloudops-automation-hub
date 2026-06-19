output "acr_id" {
  value = azurerm_container_registry.this.id
}

output "acr_name" {
  value = azurerm_container_registry.this.name
}

output "login_server" {
  description = "ACR login server FQDN (e.g. myacr.azurecr.io)"
  value       = azurerm_container_registry.this.login_server
}

output "acr_resource_group" {
  value = azurerm_container_registry.this.resource_group_name
}

output "private_endpoint_id" {
  value = var.public_network_access_enabled ? null : azurerm_private_endpoint.acr[0].id
}

output "private_dns_zone_id" {
  value = (var.public_network_access_enabled == false && var.create_private_dns_zone) ? azurerm_private_dns_zone.acr[0].id : var.private_dns_zone_id
}
