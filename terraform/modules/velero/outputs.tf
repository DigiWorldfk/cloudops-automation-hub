output "velero_identity_client_id" {
  description = "Client ID of the Velero managed identity — set in Velero Helm values."
  value       = azurerm_user_assigned_identity.velero.client_id
}

output "velero_identity_id" {
  description = "Resource ID of the Velero managed identity."
  value       = azurerm_user_assigned_identity.velero.id
}

output "storage_account_name" {
  value = azurerm_storage_account.velero.name
}

output "storage_container_name" {
  value = azurerm_storage_container.velero.name
}

output "resource_group_name" {
  value = azurerm_storage_account.velero.resource_group_name
}
