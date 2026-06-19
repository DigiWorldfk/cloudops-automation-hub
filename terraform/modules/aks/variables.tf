variable "name" {
  description = "Name of the AKS cluster"
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

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.29"
}

variable "default_node_count" {
  description = "Initial node count for the default node pool"
  type        = number
  default     = 2
}

variable "default_vm_size" {
  description = "VM size for the default node pool"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "min_node_count" {
  description = "Minimum node count for autoscaling (null to disable)"
  type        = number
  default     = null
}

variable "max_node_count" {
  description = "Maximum node count for autoscaling (null to disable)"
  type        = number
  default     = null
}

variable "vnet_subnet_id" {
  description = "Subnet ID for AKS nodes (Azure CNI). Required when WAF/VNet integration is enabled."
  type        = string
  default     = null
}

variable "application_gateway_id" {
  description = "Resource ID of the Application Gateway to wire via the AGIC addon. Set null to disable AGIC."
  type        = string
  default     = null
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}

variable "api_server_authorized_ip_ranges" {
  description = "CIDR ranges allowed to reach the AKS API server. Set to your CI/CD agent IPs, VPN, and bastion CIDR. Empty list = unrestricted access (acceptable for dev only)."
  type        = list(string)
  default     = []
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics Workspace ID for OMS agent diagnostics."
  type        = string
  default     = null
}

variable "os_disk_size_gb" {
  description = "OS disk size in GB for AKS node pool VMs."
  type        = number
  default     = 128
}

variable "node_pool_max_surge" {
  description = "Maximum number or percentage of nodes added during an upgrade. E.g. '10%' or '1'."
  type        = string
  default     = "10%"
}

variable "load_balancer_sku" {
  description = "SKU for the AKS load balancer. 'standard' is required for availability zones and multiple node pools."
  type        = string
  default     = "standard"
  validation {
    condition     = contains(["basic", "standard"], var.load_balancer_sku)
    error_message = "load_balancer_sku must be 'basic' or 'standard'."
  }
}
