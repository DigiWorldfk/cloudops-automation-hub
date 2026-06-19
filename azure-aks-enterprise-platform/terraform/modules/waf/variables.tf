variable "name_prefix" {
  description = "Prefix used for all resource names (e.g. 'aks-enterprise-dev')"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group to deploy into"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "appgw_subnet_id" {
  description = "ID of the dedicated /24 subnet for the Application Gateway"
  type        = string
}

variable "waf_mode" {
  description = "WAF mode: 'Prevention' blocks matched requests; 'Detection' only logs them"
  type        = string
  default     = "Prevention"

  validation {
    condition     = contains(["Prevention", "Detection"], var.waf_mode)
    error_message = "waf_mode must be 'Prevention' or 'Detection'."
  }
}

variable "blocked_countries" {
  description = "ISO 3166-1 alpha-2 country codes to block at the WAF level"
  type        = list(string)
  default     = []
}

variable "appgw_min_capacity" {
  description = "Minimum autoscale instance count for the Application Gateway"
  type        = number
  default     = 1
}

variable "appgw_max_capacity" {
  description = "Maximum autoscale instance count for the Application Gateway"
  type        = number
  default     = 10
}

variable "tls_cert_keyvault_secret_id" {
  description = "Key Vault secret URI for the TLS certificate (versioned or versionless)"
  type        = string
  sensitive   = true
}

variable "key_vault_id" {
  description = "Resource ID of the Key Vault that stores the TLS certificate"
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID for WAF and App Gateway diagnostic logs"
  type        = string
}

variable "aks_kubelet_identity_object_id" {
  description = "Object ID of the AKS kubelet managed identity — grants AGIC access to App Gateway"
  type        = string
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
