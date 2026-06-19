# ─── Infrastructure Tuning ────────────────────────────────────────────────────

variable "location" {
  description = "Azure region to deploy all resources into."
  type        = string
  default     = "norwayeast"
}

# ─── Networking ───────────────────────────────────────────────────────────────

variable "vnet_cidr" {
  description = "Address space for the Virtual Network."
  type        = string
  default     = "10.20.0.0/16"
}

variable "aks_subnet_cidr" {
  description = "CIDR for the AKS node/pod subnet (Azure CNI). Larger than dev to support prod node pool scaling."
  type        = string
  default     = "10.20.0.0/21" # 2046 usable IPs
}

variable "appgw_subnet_cidr" {
  description = "CIDR for the Application Gateway subnet."
  type        = string
  default     = "10.20.8.0/24"
}

variable "mysql_subnet_cidr" {
  description = "CIDR for the MySQL delegated subnet."
  type        = string
  default     = "10.20.9.0/28"
}

# ─── AKS ──────────────────────────────────────────────────────────────────────

variable "kubernetes_version" {
  description = "Kubernetes version for the AKS cluster."
  type        = string
  default     = "1.29"
}

variable "aks_node_count" {
  description = "Initial node count for the default node pool."
  type        = number
  default     = 3
}

variable "aks_min_node_count" {
  description = "Minimum node count for cluster autoscaling."
  type        = number
  default     = 3
}

variable "aks_max_node_count" {
  description = "Maximum node count for cluster autoscaling."
  type        = number
  default     = 10
}

variable "aks_vm_size" {
  description = "VM size for the default AKS node pool."
  type        = string
  default     = "Standard_D4s_v3"
}

# ─── Secrets (never commit real values — use gitignored terraform.tfvars) ─────

variable "tls_cert_keyvault_secret_id" {
  description = "Key Vault secret URI for the TLS certificate. Pass via gitignored terraform.tfvars or CI secret."
  type        = string
  sensitive   = true
}

variable "mysql_admin_password" {
  description = "MySQL administrator password. Must NOT be committed — pass via terraform.tfvars (gitignored) or CI secret."
  type        = string
  sensitive   = true
}

# ─── Front Door ───────────────────────────────────────────────────────────────

variable "blocked_countries" {
  description = "ISO 3166-1 alpha-2 codes to geo-block at Front Door + App Gateway WAF (e.g. [\"KP\", \"IR\"])."
  type        = list(string)
  default     = []
}

variable "custom_domains" {
  description = "Custom hostnames to attach to Front Door (e.g. ['app.example.com', 'api.example.com']). AFD provisions TLS automatically."
  type        = list(string)
  default     = []
}

variable "appgw_private_link_resource_id" {
  description = "Resource ID of the App Gateway Private Link configuration (Premium SKU). Set null to use public origin."
  type        = string
  default     = null
}

# ─── DNS ────────────────────────────────────────────────────────────────────

variable "domain_name" {
  description = "Root domain name to host in Azure DNS (e.g. 'example.com'). Must be delegated to Azure DNS nameservers at your registrar."
  type        = string
  default     = ""
}

variable "subdomains" {
  description = "Subdomain labels to create CNAME records for, all pointing to Front Door (e.g. ['www', 'api', 'app'])."
  type        = list(string)
  default     = ["www", "api", "app"]
}

variable "apex_alias_enabled" {
  description = "Create an ALIAS A record for the root domain (@) pointing to Front Door."
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
