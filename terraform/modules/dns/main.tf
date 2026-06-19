terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Azure DNS Zone
# ─────────────────────────────────────────────────────────────────────────────
# This is the authoritative DNS zone for your domain.
# After creation, copy the name_servers output to your domain registrar
# (GoDaddy, Namecheap, Cloudflare, etc.) to delegate DNS to Azure.
#
# Traffic flow:
#   User browser
#     → DNS lookup: app.example.com
#     → Azure DNS Zone (this module) → CNAME → Front Door endpoint
#     → Front Door global WAF + CDN
#     → App Gateway WAF (regional)
#     → AKS pods
# ─────────────────────────────────────────────────────────────────────────────
resource "azurerm_dns_zone" "main" {
  name                = var.domain_name
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Root apex record  (@)
# Azure DNS ALIAS record → Front Door endpoint
# (Apex domains cannot use CNAME — ALIAS solves this without flattening)
# ─────────────────────────────────────────────────────────────────────────────
resource "azurerm_dns_a_record" "apex" {
  count               = var.apex_alias_enabled ? 1 : 0
  name                = "@"
  zone_name           = azurerm_dns_zone.main.name
  resource_group_name = var.resource_group_name
  ttl                 = var.dns_ttl

  target_resource_id = var.frontdoor_endpoint_resource_id
  tags               = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Subdomain CNAME records → Front Door endpoint
# e.g. www.example.com, api.example.com, staging.example.com
# ─────────────────────────────────────────────────────────────────────────────
resource "azurerm_dns_cname_record" "subdomains" {
  for_each = var.subdomain_cname_records

  name                = each.key                          # e.g. "www", "api", "app"
  zone_name           = azurerm_dns_zone.main.name
  resource_group_name = var.resource_group_name
  ttl                 = var.dns_ttl
  record              = each.value.target                 # Front Door or custom target
  tags                = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Front Door domain ownership validation TXT records
# Azure Front Door requires a TXT record to prove you own the domain before
# it issues a managed TLS certificate for each custom domain.
#
# The validation tokens come from the frontdoor module output:
#   module.frontdoor.custom_domain_validation_tokens
# ─────────────────────────────────────────────────────────────────────────────
resource "azurerm_dns_txt_record" "frontdoor_validation" {
  for_each = var.frontdoor_validation_records

  # AFD validation prefix: _dnsauth.<subdomain>
  name                = "_dnsauth.${each.key == "@" ? "" : "${each.key}."}"
  zone_name           = azurerm_dns_zone.main.name
  resource_group_name = var.resource_group_name
  ttl                 = 3600 # Validation records can use a longer TTL

  record {
    value = each.value # Token from module.frontdoor.custom_domain_validation_tokens
  }

  tags = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# SPF record (anti-spam)
# Prevents others from sending email as your domain.
# Include your mail provider's SPF mechanism here.
# ─────────────────────────────────────────────────────────────────────────────
resource "azurerm_dns_txt_record" "spf" {
  count               = var.spf_record != null ? 1 : 0
  name                = "@"
  zone_name           = azurerm_dns_zone.main.name
  resource_group_name = var.resource_group_name
  ttl                 = var.dns_ttl

  record {
    value = var.spf_record # e.g. "v=spf1 include:sendgrid.net ~all"
  }

  tags = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# DMARC record (email authentication policy)
# ─────────────────────────────────────────────────────────────────────────────
resource "azurerm_dns_txt_record" "dmarc" {
  count               = var.dmarc_record != null ? 1 : 0
  name                = "_dmarc"
  zone_name           = azurerm_dns_zone.main.name
  resource_group_name = var.resource_group_name
  ttl                 = var.dns_ttl

  record {
    value = var.dmarc_record # e.g. "v=DMARC1; p=quarantine; rua=mailto:dmarc@example.com"
  }

  tags = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# MX records (email routing)
# ─────────────────────────────────────────────────────────────────────────────
resource "azurerm_dns_mx_record" "main" {
  count               = length(var.mx_records) > 0 ? 1 : 0
  name                = "@"
  zone_name           = azurerm_dns_zone.main.name
  resource_group_name = var.resource_group_name
  ttl                 = var.dns_ttl

  dynamic "record" {
    for_each = var.mx_records
    content {
      preference = record.value.preference
      exchange   = record.value.exchange
    }
  }

  tags = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Diagnostic settings — log DNS query metrics to Log Analytics
# ─────────────────────────────────────────────────────────────────────────────
resource "azurerm_monitor_diagnostic_setting" "dns" {
  count                      = var.log_analytics_workspace_id != null ? 1 : 0
  name                       = "dns-diagnostics"
  target_resource_id         = azurerm_dns_zone.main.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "DnsRequests"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
