output "zone_id" {
  description = "Resource ID of the Azure DNS zone."
  value       = azurerm_dns_zone.main.id
}

output "zone_name" {
  description = "The domain name hosted in this DNS zone (e.g. 'example.com')."
  value       = azurerm_dns_zone.main.name
}

output "name_servers" {
  description = <<-EOT
    Azure DNS nameservers for this zone.
    *** ACTION REQUIRED: Copy these 4 nameservers to your domain registrar ***
    (GoDaddy → Manage DNS → Nameservers | Namecheap → Domain → Nameservers)
    DNS will not resolve until you delegate to these servers.
  EOT
  value = azurerm_dns_zone.main.name_servers
}

output "apex_record_fqdn" {
  description = "FQDN of the apex ALIAS record (root domain → Front Door)."
  value       = var.apex_alias_enabled ? azurerm_dns_a_record.apex[0].fqdn : null
}

output "subdomain_fqdns" {
  description = "Map of subdomain label → fully-qualified domain name."
  value = {
    for k, v in azurerm_dns_cname_record.subdomains :
    k => v.fqdn
  }
}

output "validation_record_names" {
  description = "Map of subdomain → TXT record name created for Front Door domain validation."
  value = {
    for k, v in azurerm_dns_txt_record.frontdoor_validation :
    k => v.name
  }
}

output "max_number_of_record_sets" {
  description = "Maximum number of record sets allowed in the zone."
  value       = azurerm_dns_zone.main.max_number_of_record_sets
}
