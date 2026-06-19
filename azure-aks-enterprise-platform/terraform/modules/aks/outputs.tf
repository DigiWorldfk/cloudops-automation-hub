output "cluster_id" {
  description = "The AKS cluster resource ID"
  value       = azurerm_kubernetes_cluster.main.id
}

output "cluster_name" {
  description = "The AKS cluster name"
  value       = azurerm_kubernetes_cluster.main.name
}

output "kube_config_raw" {
  description = "Raw kubeconfig for the cluster"
  value       = azurerm_kubernetes_cluster.main.kube_config_raw
  sensitive   = true
}

output "kubelet_identity" {
  description = "Kubelet managed identity"
  value       = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}

output "log_analytics_workspace_id" {
  description = "Log Analytics Workspace ID — consumed by the WAF diagnostic settings"
  value       = azurerm_log_analytics_workspace.main.id
}

output "oidc_issuer_url" {
  description = "AKS OIDC issuer URL — used to create federated credentials for Workload Identity."
  value       = azurerm_kubernetes_cluster.main.oidc_issuer_url
}
