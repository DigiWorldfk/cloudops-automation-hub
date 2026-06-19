variable "name_prefix" {
  description = "Prefix for all resource names"
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

variable "vnet_cidr" {
  description = "CIDR block for the virtual network"
  type        = string
  default     = "10.0.0.0/16"
}

variable "aks_subnet_cidr" {
  description = "CIDR block for the AKS node subnet"
  type        = string
  default     = "10.0.0.0/22"
}

variable "appgw_subnet_cidr" {
  description = "CIDR block for the Application Gateway subnet (must be /24 or larger)"
  type        = string
  default     = "10.0.4.0/24"
}

variable "mysql_subnet_cidr" {
  description = "CIDR block for the MySQL Flexible Server delegated subnet (must be /28 or larger; no other resources allowed)"
  type        = string
  default     = "10.0.5.0/28"
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
