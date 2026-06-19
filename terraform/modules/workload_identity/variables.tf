variable "cluster_name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type    = string
  default = "norwayeast"
}

variable "aks_oidc_issuer_url" {
  description = "OIDC issuer URL from the AKS cluster (azurerm_kubernetes_cluster.oidc_issuer_url)."
  type        = string
}

variable "workloads" {
  description = "Map of workloads to create identities for."
  type = map(object({
    namespace            = string
    service_account_name = string
    azure_roles = list(object({
      role_definition_name = string
      scope                = string
    }))
  }))
  default = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}
