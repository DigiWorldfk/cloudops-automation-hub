variable "name_prefix" {
  description = "Prefix for all resource names (e.g. 'aks-enterprise-dev')"
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

variable "virtual_network_id" {
  description = "Resource ID of the VNet — required to link the private DNS zone"
  type        = string
}

variable "mysql_subnet_id" {
  description = "Resource ID of the subnet delegated to 'Microsoft.DBforMySQL/flexibleServers'"
  type        = string
}

variable "key_vault_id" {
  description = "Resource ID of the Key Vault where connection strings and passwords are stored"
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID for MySQL diagnostic logs"
  type        = string
}

variable "administrator_login" {
  description = "MySQL administrator username. Must not be 'admin', 'root', or 'azure_superuser'."
  type        = string
  default     = "mysqladmin"
}

variable "administrator_password" {
  description = "MySQL administrator password. Injected from CI secret — never committed."
  type        = string
  sensitive   = true
}

variable "mysql_version" {
  description = "MySQL engine version"
  type        = string
  default     = "8.0.21"
}

variable "sku_name" {
  description = "SKU for the MySQL Flexible Server. Format: <tier>_<family>_<vCores>. e.g. 'B_Standard_B1ms' (burstable dev), 'GP_Standard_D4ds_v4' (prod)."
  type        = string
  default     = "B_Standard_B1ms"
}

variable "storage_size_gb" {
  description = "Storage size in GB (20–16384)"
  type        = number
  default     = 32
}

variable "storage_iops" {
  description = "Storage IOPS. Minimum 396; higher tiers support up to 20000."
  type        = number
  default     = 396
}

variable "backup_retention_days" {
  description = "Number of days to retain automated backups (1–35)"
  type        = number
  default     = 7
}

variable "geo_redundant_backup" {
  description = "Enable geo-redundant backups. Doubles the cost — use true for prod."
  type        = bool
  default     = false
}

variable "high_availability_enabled" {
  description = "Enable Zone-Redundant High Availability (standby replica in a different AZ). Requires General Purpose or Memory Optimised SKU."
  type        = bool
  default     = false
}

variable "primary_zone" {
  description = "Availability zone for the primary replica"
  type        = string
  default     = "1"
}

variable "standby_zone" {
  description = "Availability zone for the standby replica (HA mode)"
  type        = string
  default     = "2"
}

variable "databases" {
  description = "List of database names to create on the server"
  type        = list(string)
  default     = ["app"]
}

variable "max_connections" {
  description = "MySQL max_connections parameter"
  type        = number
  default     = 200
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
