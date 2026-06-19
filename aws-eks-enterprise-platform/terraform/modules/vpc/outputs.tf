output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets (EKS nodes)"
  value       = aws_subnet.private[*].id
}

output "isolated_subnet_ids" {
  description = "IDs of the isolated subnets (RDS/ElastiCache)"
  value       = aws_subnet.isolated[*].id
}

output "nat_gateway_ids" {
  description = "IDs of the NAT Gateways"
  value       = aws_nat_gateway.main[*].id
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.main.id
}

output "private_route_table_ids" {
  description = "IDs of the private route tables (one per AZ)"
  value       = aws_route_table.private[*].id
}

output "transit_gateway_id" {
  description = "ID of the Transit Gateway (null if not enabled)"
  value       = var.enable_transit_gateway && var.transit_gateway_id == null ? aws_ec2_transit_gateway.main[0].id : var.transit_gateway_id
}

output "vpc_peering_connection_id" {
  description = "ID of the VPC Peering Connection (null if not enabled)"
  value       = var.enable_vpc_peering ? aws_vpc_peering_connection.main[0].id : null
}

output "vpn_connection_id" {
  description = "ID of the Site-to-Site VPN Connection (null if not enabled)"
  value       = var.enable_vpn ? aws_vpn_connection.main[0].id : null
}

output "vpn_tunnel1_address" {
  description = "Outside IP of VPN tunnel 1 (null if not enabled)"
  value       = var.enable_vpn ? aws_vpn_connection.main[0].tunnel1_address : null
}

output "vpn_tunnel2_address" {
  description = "Outside IP of VPN tunnel 2 (null if not enabled)"
  value       = var.enable_vpn ? aws_vpn_connection.main[0].tunnel2_address : null
}
