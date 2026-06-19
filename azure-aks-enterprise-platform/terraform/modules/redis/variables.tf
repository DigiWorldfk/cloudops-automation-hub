variable "name" {
  description = "Short name used to suffix resources."
  type        = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type    = string
  default = "norwayeast"
}

variable "vnet_id" {
  type = string
}

variable "private_endpoint_subnet_id" {
  description = "Subnet ID for the Redis private endpoint (can reuse aks subnet or dedicated)."
  type        = string
}

variable "sku_name" {
  description = "Redis SKU: Basic | Standard | Premium. Premium required for persistence and zone redundancy."
  type        = string
  default     = "Standard"
}

variable "family" {
  description = "C for Basic/Standard, P for Premium."
  type        = string
  default     = "C"
}

variable "capacity" {
  description = "Redis cache size: 0-6 for C family, 1-5 for P family."
  type        = number
  default     = 1
}

variable "maxmemory_policy" {
  description = "Redis eviction policy. allkeys-lru recommended for session cache."
  type        = string
  default     = "allkeys-lru"
}

variable "enable_persistence" {
  description = "Enable RDB persistence (Premium SKU only)."
  type        = bool
  default     = false
}

variable "backup_frequency_minutes" {
  description = "RDB backup frequency in minutes: 15, 30, 60, 360, 720, 1440."
  type        = number
  default     = 60
}

variable "zones" {
  description = "Availability zones (Premium SKU only)."
  type        = list(string)
  default     = []
}

variable "key_vault_id" {
  description = "Key Vault to store Redis connection string and primary key."
  type        = string
}

variable "log_analytics_workspace_id" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
