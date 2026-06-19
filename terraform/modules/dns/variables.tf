variable "domain_name" {
  description = "The root domain name to host in Azure DNS (e.g. 'example.com'). Must be a domain you own — you will need to update your registrar's nameservers to the Azure DNS nameservers output."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group to deploy the DNS zone into."
  type        = string
}

variable "dns_ttl" {
  description = "Default DNS record TTL in seconds. Lower values allow faster propagation during initial setup; increase to 3600+ once stable."
  type        = number
  default     = 300
}

# ─── Apex / root domain ───────────────────────────────────────────────────────

variable "apex_alias_enabled" {
  description = "Create an ALIAS A record for the apex domain (@) pointing to the Front Door endpoint. Set false if you don't want the root domain to resolve."
  type        = bool
  default     = true
}

variable "frontdoor_endpoint_resource_id" {
  description = "Resource ID of the Front Door endpoint to create the apex ALIAS record against. Required when apex_alias_enabled = true."
  type        = string
  default     = null
}

# ─── Subdomain CNAME records ──────────────────────────────────────────────────

variable "subdomain_cname_records" {
  description = <<-EOT
    Map of subdomain → CNAME target.
    Each key is the subdomain label (e.g. "www", "api", "app").
    The target should be the Front Door endpoint hostname.

    Example:
      subdomain_cname_records = {
        www = { target = "myapp-afd.z01.azurefd.net" }
        api = { target = "myapp-afd.z01.azurefd.net" }
        app = { target = "myapp-afd.z01.azurefd.net" }
      }
  EOT
  type = map(object({
    target = string
  }))
  default = {}
}

# ─── Front Door domain validation ────────────────────────────────────────────

variable "frontdoor_validation_records" {
  description = <<-EOT
    Map of subdomain label → Front Door validation token.
    These TXT records prove domain ownership so Front Door can issue managed TLS certs.
    Obtain tokens from: module.frontdoor.custom_domain_validation_tokens

    Example:
      frontdoor_validation_records = {
        "www"  = "abc123validationtoken"
        "api"  = "xyz789validationtoken"
        "@"    = "root_domain_token"
      }
  EOT
  type    = map(string)
  default = {}
}

# ─── Email records ────────────────────────────────────────────────────────────

variable "mx_records" {
  description = <<-EOT
    List of MX records for email routing.
    Example (Microsoft 365):
      mx_records = [
        { preference = 0,  exchange = "mycompany-com.mail.protection.outlook.com." }
      ]
    Example (Google Workspace):
      mx_records = [
        { preference = 1,  exchange = "aspmx.l.google.com." },
        { preference = 5,  exchange = "alt1.aspmx.l.google.com." },
        { preference = 10, exchange = "alt2.aspmx.l.google.com." }
      ]
  EOT
  type = list(object({
    preference = number
    exchange   = string
  }))
  default = []
}

variable "spf_record" {
  description = "SPF TXT record value. Prevents email spoofing. E.g. 'v=spf1 include:sendgrid.net ~all'. Set null to skip."
  type        = string
  default     = null
}

variable "dmarc_record" {
  description = "DMARC TXT record value. E.g. 'v=DMARC1; p=quarantine; rua=mailto:dmarc@example.com'. Set null to skip."
  type        = string
  default     = null
}

# ─── Observability ───────────────────────────────────────────────────────────

variable "log_analytics_workspace_id" {
  description = "Log Analytics Workspace ID for DNS query diagnostic logs. Set null to disable."
  type        = string
  default     = null
}

# ─── Tags ─────────────────────────────────────────────────────────────────────

variable "tags" {
  description = "Resource tags applied to all DNS resources."
  type        = map(string)
  default     = {}
}
