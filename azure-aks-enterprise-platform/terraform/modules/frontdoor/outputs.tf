output "frontdoor_id" {
  description = "Resource ID of the Front Door profile"
  value       = azurerm_cdn_frontdoor_profile.main.id
}

output "frontdoor_name" {
  description = "Name of the Front Door profile"
  value       = azurerm_cdn_frontdoor_profile.main.name
}

output "endpoint_hostname" {
  description = "Default *.z01.azurefd.net hostname — use for DNS CNAME until custom domains are validated"
  value       = azurerm_cdn_frontdoor_endpoint.main.host_name
}

output "waf_policy_id" {
  description = "Resource ID of the Front Door WAF policy"
  value       = azurerm_cdn_frontdoor_firewall_policy.main.id
}

output "custom_domain_validation_tokens" {
  description = "DNS TXT validation tokens per custom domain — add these as TXT records to prove domain ownership"
  value = {
    for k, v in azurerm_cdn_frontdoor_custom_domain.main :
    v.host_name => v.validation_token
  }
}

output "custom_domain_cname_targets" {
  description = "CNAME targets per custom domain — point your DNS CNAME records here"
  value = {
    for k, v in azurerm_cdn_frontdoor_custom_domain.main :
    v.host_name => azurerm_cdn_frontdoor_endpoint.main.host_name
  }
}

output "resource_guid" {
  description = "Unique GUID for the Front Door profile (used in DNS validation records)"
  value       = azurerm_cdn_frontdoor_profile.main.resource_guid
}
