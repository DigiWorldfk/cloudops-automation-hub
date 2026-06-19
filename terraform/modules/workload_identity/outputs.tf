output "identity_client_ids" {
  description = "Map of workload name → Azure managed identity client ID."
  value       = { for k, v in azurerm_user_assigned_identity.this : k => v.client_id }
}

output "identity_principal_ids" {
  description = "Map of workload name → Azure managed identity principal ID."
  value       = { for k, v in azurerm_user_assigned_identity.this : k => v.principal_id }
}

output "identity_ids" {
  description = "Map of workload name → Azure managed identity resource ID (for pod spec annotation)."
  value       = { for k, v in azurerm_user_assigned_identity.this : k => v.id }
}

output "service_account_annotations" {
  description = "Map of workload name → Kubernetes ServiceAccount annotation block (for Helm values / manifests)."
  value = {
    for k, v in azurerm_user_assigned_identity.this : k => {
      "azure.workload.identity/client-id" = v.client_id
    }
  }
}
