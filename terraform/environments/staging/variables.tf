# ─── Infrastructure Tuning ────────────────────────────────────────────────────

variable "location" {
  description = "Azure region to deploy all resources into."
  type        = string
  default     = "norwayeast"
}

# ─── Networking ───────────────────────────────────────────────────────────────

variable "vnet_cidr" {
  description = "Address space for the staging Virtual Network. Must not overlap with dev (10.10.x.x) or prod (10.20.x.x)."
  type        = string
  default     = "10.15.0.0/16"
}

variable "aks_subnet_cidr" {
  description = "CIDR for the AKS node/pod subnet (Azure CNI)."
  type        = string
  default     = "10.15.0.0/22"
}

variable "appgw_subnet_cidr" {
  description = "CIDR for the Application Gateway subnet."
  type        = string
  default     = "10.20.2.0/24"
}

variable "mysql_subnet_cidr" {
  description = "CIDR for the MySQL delegated subnet."
  type        = string
  default     = "10.20.3.0/28"
}

# ─── AKS ──────────────────────────────────────────────────────────────────────

variable "kubernetes_version" {
  description = "Kubernetes version for the AKS cluster."
  type        = string
  default     = "1.29"
}

variable "aks_vm_size" {
  description = "VM size for the default AKS node pool."
  type        = string
  default     = "Standard_D2ds_v5"
}

variable "aks_min_node_count" {
  description = "Minimum node count for cluster autoscaling."
  type        = number
  default     = 2
}

variable "aks_max_node_count" {
  description = "Maximum node count for cluster autoscaling."
  type        = number
  default     = 4
}

# ─── Secrets (never commit real values — use gitignored terraform.tfvars) ─────

variable "tls_cert_keyvault_secret_id" {
  description = "Key Vault secret URI for the TLS certificate. Must NOT be committed."
  type        = string
  sensitive   = true
}

variable "mysql_admin_password" {
  description = "MySQL administrator password. Must NOT be committed."
  type        = string
  sensitive   = true
}

# ─── Front Door ───────────────────────────────────────────────────────────────

variable "custom_domains" {
  description = "Custom hostnames to attach to Front Door."
  type        = list(string)
  default     = []
}

# ─── DNS ────────────────────────────────────────────────────────────────────

variable "domain_name" {
  description = "Root domain name to host in Azure DNS (e.g. 'staging.example.com')."
  type        = string
  default     = ""
}

variable "subdomains" {
  description = "Subdomain labels to create CNAME records for (e.g. ['www', 'api'])."
  type        = list(string)
  default     = ["www", "api"]
}

variable "apex_alias_enabled" {
  description = "Create an ALIAS A record for the root domain pointing to Front Door."
  type        = bool
  default     = true
}

variable "mx_records" {
  description = "MX records for email routing."
  type = list(object({
    preference = number
    exchange   = string
  }))
  default = []
}

variable "spf_record" {
  description = "SPF TXT record value. Set null to skip."
  type        = string
  default     = null
}

variable "dmarc_record" {
  description = "DMARC TXT record value. Set null to skip."
  type        = string
  default     = null
}
