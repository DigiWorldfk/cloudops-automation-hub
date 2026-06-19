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

variable "storage_account_name" {
  description = "Globally unique storage account name for Velero backup blobs (3-24 chars, lowercase alphanumeric)."
  type        = string
}

variable "replication_type" {
  description = "Storage replication: GRS for prod, LRS for dev."
  type        = string
  default     = "GRS"
}

variable "blob_soft_delete_days" {
  description = "Days to retain soft-deleted blobs and containers."
  type        = number
  default     = 14
}

variable "backup_retention_days" {
  description = "Days before Velero backup blobs are auto-deleted."
  type        = number
  default     = 90
}

variable "aks_oidc_issuer_url" {
  description = "OIDC issuer URL from AKS for Velero workload identity federated credential."
  type        = string
}

variable "allowed_subnet_ids" {
  description = "Subnet IDs allowed to access the Velero storage account. Add the AKS subnet ID here."
  type        = list(string)
  default     = []
}

variable "allowed_ip_ranges" {
  description = "Public IP CIDR ranges allowed to access the Velero storage account (e.g. CI/CD runner IPs)."
  type        = list(string)
  default     = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
