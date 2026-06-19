output "application_gateway_id" {
  description = "Resource ID of the Application Gateway"
  value       = azurerm_application_gateway.main.id
}

output "application_gateway_name" {
  description = "Name of the Application Gateway (referenced by AGIC Helm values)"
  value       = azurerm_application_gateway.main.name
}

output "waf_policy_id" {
  description = "Resource ID of the WAF policy"
  value       = azurerm_web_application_firewall_policy.main.id
}

output "public_ip_address" {
  description = "Public IP address of the Application Gateway (front-end ingress IP)"
  value       = azurerm_public_ip.appgw.ip_address
}

output "public_ip_id" {
  description = "Resource ID of the front-end public IP"
  value       = azurerm_public_ip.appgw.id
}

output "appgw_identity_client_id" {
  description = "Client ID of the App Gateway managed identity (for Key Vault federated auth)"
  value       = azurerm_user_assigned_identity.appgw.client_id
}

output "appgw_identity_principal_id" {
  description = "Principal/Object ID of the App Gateway managed identity"
  value       = azurerm_user_assigned_identity.appgw.principal_id
}
