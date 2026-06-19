variable "acr_name" {
  description = "Globally unique name for the Azure Container Registry (alphanumeric, 5-50 chars)"
  type        = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type    = string
  default = "norwayeast"
}

variable "sku" {
  description = "ACR SKU: Basic | Standard | Premium. Premium required for private endpoints and geo-replication."
  type        = string
  default     = "Premium"
}

variable "public_network_access_enabled" {
  description = "Set false for production — all access via private endpoint only."
  type        = bool
  default     = false
}

variable "zone_redundancy_enabled" {
  type    = bool
  default = false # Only available in Premium and specific regions
}

variable "retention_days" {
  description = "Days to retain untagged manifests before purging."
  type        = number
  default     = 30
}

variable "enable_content_trust" {
  description = "Enable Docker Content Trust (Notary v1) image signing."
  type        = bool
  default     = false
}

variable "quarantine_policy_enabled" {
  description = "Hold newly pushed images in quarantine until scanned."
  type        = bool
  default     = false
}

variable "export_policy_enabled" {
  description = "Allow images to be exported. Set false to prevent exfiltration."
  type        = bool
  default     = false
}

variable "geo_replication_locations" {
  description = "List of Azure regions to replicate the registry to (Premium SKU only)."
  type        = list(string)
  default     = []
}

variable "allowed_ip_ranges" {
  description = "CIDR ranges allowed to access ACR when public access is enabled."
  type        = list(string)
  default     = []
}

variable "allowed_subnet_ids" {
  description = "Subnet IDs allowed to access ACR via service endpoint."
  type        = list(string)
  default     = []
}

variable "private_endpoint_subnet_id" {
  description = "Subnet ID to place the ACR private endpoint in."
  type        = string
  default     = null
}

variable "private_dns_zone_id" {
  description = "Existing private DNS zone ID for privatelink.azurecr.io. Leave null to create one."
  type        = string
  default     = null
}

variable "create_private_dns_zone" {
  description = "Create a new private DNS zone. Set false if you already have one."
  type        = bool
  default     = true
}

variable "vnet_id" {
  description = "VNet ID to link the private DNS zone to."
  type        = string
  default     = null
}

variable "aks_kubelet_identity_principal_id" {
  description = "Principal ID of the AKS kubelet managed identity for AcrPull role."
  type        = string
}

variable "enable_defender" {
  description = "Enable Microsoft Defender for Containers on the subscription."
  type        = bool
  default     = true
}

variable "log_analytics_workspace_id" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
