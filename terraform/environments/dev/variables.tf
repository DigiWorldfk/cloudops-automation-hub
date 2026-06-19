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
  default     = "10.10.0.0/16"
}

variable "aks_subnet_cidr" {
  description = "CIDR for the AKS node/pod subnet (Azure CNI). Needs enough IPs for max_node_count × max_pods_per_node."
  type        = string
  default     = "10.10.0.0/22" # 1022 usable IPs
}

variable "appgw_subnet_cidr" {
  description = "CIDR for the Application Gateway subnet. /24 gives 251 usable IPs."
  type        = string
  default     = "10.10.4.0/24"
}

variable "mysql_subnet_cidr" {
  description = "CIDR for the MySQL delegated subnet. /28 gives 11 usable IPs."
  type        = string
  default     = "10.10.5.0/28"
}

# ─── AKS ──────────────────────────────────────────────────────────────────────

variable "kubernetes_version" {
  description = "Kubernetes version for the AKS cluster."
  type        = string
  default     = "1.29"
}

variable "aks_node_count" {
  description = "Initial / static node count (when autoscaling is disabled)."
  type        = number
  default     = 2
}

variable "aks_vm_size" {
  description = "VM size for the default AKS node pool."
  type        = string
  default     = "Standard_D2s_v3"
}

# ─── Secrets (never commit real values — use gitignored terraform.tfvars) ─────

variable "tls_cert_keyvault_secret_id" {
  description = "Key Vault secret URI for the TLS certificate. Must NOT be committed — pass via terraform.tfvars (gitignored) or CI secret."
  type        = string
  sensitive   = true
}

variable "mysql_admin_password" {
  description = "MySQL administrator password. Must NOT be committed — pass via terraform.tfvars (gitignored) or CI secret."
  type        = string
  sensitive   = true
}

# ─── Front Door ───────────────────────────────────────────────────────────────

variable "custom_domains" {
  description = "Custom hostnames to attach to Front Door (e.g. ['dev.app.example.com']). AFD provisions TLS automatically."
  type        = list(string)
  default     = []
}

# ─── DNS ────────────────────────────────────────────────────────────────────

variable "domain_name" {
  description = "Root domain name to host in Azure DNS (e.g. 'dev.example.com'). Must be delegated to Azure DNS nameservers at your registrar."
  type        = string
  default     = ""
}

variable "subdomains" {
  description = "Subdomain labels to create CNAME records for, all pointing to Front Door (e.g. ['www', 'api', 'app'])."
  type        = list(string)
  default     = ["www", "api"]
}

variable "apex_alias_enabled" {
  description = "Create an ALIAS A record for the root domain (@) pointing to Front Door."
  type        = bool
  default     = true
}

variable "mx_records" {
  description = "MX records for email routing. Leave empty if not using email on this domain."
  type = list(object({
    preference = number
    exchange   = string
  }))
  default = []
}

variable "spf_record" {
  description = "SPF TXT record value (e.g. 'v=spf1 include:sendgrid.net ~all'). Set null to skip."
  type        = string
  default     = null
}

variable "dmarc_record" {
  description = "DMARC TXT record value. Set null to skip."
  type        = string
  default     = null
}
