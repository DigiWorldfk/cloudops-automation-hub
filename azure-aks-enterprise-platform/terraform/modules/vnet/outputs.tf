output "vnet_id" {
  description = "Resource ID of the virtual network"
  value       = azurerm_virtual_network.main.id
}

output "vnet_name" {
  description = "Name of the virtual network"
  value       = azurerm_virtual_network.main.name
}

output "aks_subnet_id" {
  description = "Resource ID of the AKS node subnet"
  value       = azurerm_subnet.aks.id
}

output "appgw_subnet_id" {
  description = "Resource ID of the Application Gateway subnet"
  value       = azurerm_subnet.appgw.id
}

output "mysql_subnet_id" {
  description = "Resource ID of the MySQL Flexible Server delegated subnet"
  value       = azurerm_subnet.mysql.id
}
