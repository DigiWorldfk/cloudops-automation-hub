variable "name_prefix" {
  description = "Prefix for all resource names (e.g. 'aks-enterprise-dev')"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group to deploy Front Door into"
  type        = string
}

variable "location" {
  description = "Azure region (used for Private Link origin)"
  type        = string
}

variable "sku_name" {
  description = "Front Door SKU. 'Premium_AzureFrontDoor' enables Private Link + bot protection; 'Standard_AzureFrontDoor' is cheaper for dev."
  type        = string
  default     = "Premium_AzureFrontDoor"

  validation {
    condition     = contains(["Standard_AzureFrontDoor", "Premium_AzureFrontDoor"], var.sku_name)
    error_message = "sku_name must be 'Standard_AzureFrontDoor' or 'Premium_AzureFrontDoor'."
  }
}

variable "waf_mode" {
  description = "Front Door WAF mode. 'Prevention' blocks; 'Detection' only logs."
  type        = string
  default     = "Prevention"

  validation {
    condition     = contains(["Prevention", "Detection"], var.waf_mode)
    error_message = "waf_mode must be 'Prevention' or 'Detection'."
  }
}

variable "waf_redirect_url" {
  description = "URL to redirect blocked requests to. If null, returns 403 with custom HTML body."
  type        = string
  default     = null
}

variable "blocked_countries" {
  description = "ISO 3166-1 alpha-2 country codes to block at the Front Door WAF level."
  type        = list(string)
  default     = []
}

variable "api_rate_limit_threshold" {
  description = "Maximum requests per minute per IP on /api/ paths before blocking."
  type        = number
  default     = 300
}

variable "custom_domains" {
  description = "List of custom hostnames to attach to the Front Door endpoint (e.g. ['app.example.com', 'api.example.com']). AFD provisions and auto-renews TLS for each."
  type        = list(string)
  default     = []
}

variable "appgw_public_ip_address" {
  description = "Public IP address of the Application Gateway — used as the Front Door origin host."
  type        = string
}

variable "appgw_private_link_resource_id" {
  description = "Resource ID of the App Gateway Private Link configuration. Required for Premium SKU Private Link origins. Set null to use public origin."
  type        = string
  default     = null
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID for Front Door diagnostic logs."
  type        = string
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
