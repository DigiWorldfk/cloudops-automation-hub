variable "name_prefix" {
  description = "Prefix used in all resource names (e.g. eks-enterprise-prod)"
  type        = string
}

variable "environment" {
  description = "Deployment environment: dev | staging | prod"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of AZs to deploy subnets into"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets — EKS nodes (one per AZ)"
  type        = list(string)
}

variable "isolated_subnet_cidrs" {
  description = "CIDR blocks for isolated subnets — RDS/ElastiCache (one per AZ)"
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "Use a single NAT Gateway instead of one per AZ (cost saving for dev/staging)"
  type        = bool
  default     = false
}

# ── VPC Peering ────────────────────────────────────────────────────────────────
variable "enable_vpc_peering" {
  description = "Create a VPC Peering connection to a peer VPC"
  type        = bool
  default     = false
}

variable "peer_vpc_id" {
  description = "ID of the peer VPC (required when enable_vpc_peering = true)"
  type        = string
  default     = null
}

variable "peer_vpc_cidr" {
  description = "CIDR of the peer VPC — used to add route table entries"
  type        = string
  default     = null
}

variable "peer_owner_id" {
  description = "AWS account ID of the peer VPC owner (leave null for same account)"
  type        = string
  default     = null
}

variable "peer_region" {
  description = "Region of the peer VPC for cross-region peering (null = same region)"
  type        = string
  default     = null
}

# ── Transit Gateway ────────────────────────────────────────────────────────────
variable "enable_transit_gateway" {
  description = "Create and attach a Transit Gateway for hub-and-spoke routing"
  type        = bool
  default     = false
}

variable "transit_gateway_id" {
  description = "Attach to an existing Transit Gateway instead of creating a new one (null = create)"
  type        = string
  default     = null
}

variable "tgw_destination_cidrs" {
  description = "List of CIDRs to route through the Transit Gateway (e.g. on-prem ranges)"
  type        = list(string)
  default     = []
}

# ── Site-to-Site VPN ──────────────────────────────────────────────────────────
variable "enable_vpn" {
  description = "Create a Site-to-Site VPN with a Customer Gateway"
  type        = bool
  default     = false
}

variable "customer_gateway_ip" {
  description = "Public IP of the on-premises VPN device (required when enable_vpn = true)"
  type        = string
  default     = null
}

variable "customer_gateway_bgp_asn" {
  description = "BGP ASN of the on-premises VPN device"
  type        = number
  default     = 65000
}

variable "vpn_destination_cidrs" {
  description = "CIDRs reachable via the VPN tunnel — added to private route tables"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to every resource"
  type        = map(string)
  default     = {}
}
