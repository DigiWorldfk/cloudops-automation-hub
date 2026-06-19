terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.50"
    }
  }

  # Backend values are intentionally empty here.
  # Pass them via a gitignored backend.hcl file:
  #   terraform init -backend-config=backend.hcl
  # See backend.hcl.example for the required keys.
  backend "azurerm" {}
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = false
    }
  }
}

# ── Locals ────────────────────────────────────────────────────────────────────
locals {
  env         = "prod"
  location    = var.location
  project     = "aks-enterprise"
  name_prefix = "${local.project}-${local.env}"

  tags = {
    environment = local.env
    project     = local.project
    managed_by  = "terraform"
  }
}

# ── Resource Group ────────────────────────────────────────────────────────────
resource "azurerm_resource_group" "main" {
  name     = "rg-${local.name_prefix}"
  location = local.location
  tags     = local.tags
}

# ── Key Vault (stores TLS certificate for App Gateway) ────────────────────────
data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "main" {
  name                       = "kv-${local.name_prefix}"
  resource_group_name        = azurerm_resource_group.main.name
  location                   = local.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  enable_rbac_authorization  = true
  soft_delete_retention_days = 90
  purge_protection_enabled   = true   # prod: prevent accidental purge

  network_acls {
    default_action             = "Deny"   # prod: locked to specific IPs/VNet
    bypass                     = "AzureServices"
    virtual_network_subnet_ids = [module.vnet.aks_subnet_id, module.vnet.mysql_subnet_id]
  }

  tags = local.tags
}

# ── VNet + Subnets ────────────────────────────────────────────────────────────
module "vnet" {
  source = "../../modules/vnet"

  name_prefix         = local.name_prefix
  resource_group_name = azurerm_resource_group.main.name
  location            = local.location

  vnet_cidr         = var.vnet_cidr
  aks_subnet_cidr   = var.aks_subnet_cidr
  appgw_subnet_cidr = var.appgw_subnet_cidr
  mysql_subnet_cidr = var.mysql_subnet_cidr

  tags = local.tags
}

# ── AKS Cluster ───────────────────────────────────────────────────────────────
module "aks" {
  source = "../../modules/aks"

  name                = "${local.name_prefix}-aks"
  resource_group_name = azurerm_resource_group.main.name
  location            = local.location
  environment         = local.env

  vnet_subnet_id         = module.vnet.aks_subnet_id
  application_gateway_id = module.waf.application_gateway_id

  default_node_count = var.aks_node_count
  default_vm_size    = var.aks_vm_size
  min_node_count     = var.aks_min_node_count
  max_node_count     = var.aks_max_node_count
  kubernetes_version = var.kubernetes_version

  tags = local.tags
}

# ── WAF + Application Gateway ─────────────────────────────────────────────────
module "waf" {
  source = "../../modules/waf"

  name_prefix         = local.name_prefix
  resource_group_name = azurerm_resource_group.main.name
  location            = local.location

  appgw_subnet_id            = module.vnet.appgw_subnet_id
  log_analytics_workspace_id = module.aks.log_analytics_workspace_id
  key_vault_id               = azurerm_key_vault.main.id

  tls_cert_keyvault_secret_id = var.tls_cert_keyvault_secret_id

  aks_kubelet_identity_object_id = module.aks.kubelet_identity

  # Prod: Prevention mode — actively blocks WAF-matched requests
  waf_mode           = "Prevention"
  appgw_min_capacity = 2
  appgw_max_capacity = 20
  blocked_countries  = var.blocked_countries

  tags = local.tags

  depends_on = [module.aks]
}

# ── Azure Front Door (global entry point + CDN + WAF) ─────────────────────────
# Traffic path:
#   Internet → Front Door Premium (global WAF, geo-blocking, rate-limit, CDN)
#            → App Gateway WAF_v2 (regional WAF, AGIC)
#            → AKS pods
module "frontdoor" {
  source = "../../modules/frontdoor"

  name_prefix         = local.name_prefix
  resource_group_name = azurerm_resource_group.main.name
  location            = local.location

  # Prod: Premium SKU enables bot protection, Private Link, and DDoS mitigation
  sku_name = "Premium_AzureFrontDoor"

  # Prod: Prevention mode — actively blocks at the global edge
  waf_mode                 = "Prevention"
  api_rate_limit_threshold = 300
  blocked_countries        = var.blocked_countries

  # The App Gateway public IP is the single origin behind Front Door
  appgw_public_ip_address        = module.waf.public_ip_address
  appgw_private_link_resource_id = var.appgw_private_link_resource_id

  # Custom domains: set via gitignored terraform.tfvars or CI variable
  custom_domains = var.custom_domains

  log_analytics_workspace_id = module.aks.log_analytics_workspace_id

  tags = local.tags

  depends_on = [module.waf]
}

# ── MySQL Flexible Server ─────────────────────────────────────────────────────
# Private, VNet-injected — no public endpoint. AKS pods connect via the
# private DNS FQDN. Connection string stored in Key Vault, mounted into
# pods via the CSI Key Vault driver (never in Kubernetes Secrets unencrypted).
module "mysql" {
  source = "../../modules/mysql"

  name_prefix         = local.name_prefix
  resource_group_name = azurerm_resource_group.main.name
  location            = local.location

  virtual_network_id         = module.vnet.vnet_id
  mysql_subnet_id            = module.vnet.mysql_subnet_id
  key_vault_id               = azurerm_key_vault.main.id
  log_analytics_workspace_id = module.aks.log_analytics_workspace_id

  # Credentials injected from CI — never committed
  administrator_login    = "mysqladmin"
  administrator_password = var.mysql_admin_password

  # Prod: General Purpose SKU, Zone-Redundant HA, geo-redundant backup
  sku_name                  = "GP_Standard_D4ds_v4"
  storage_size_gb           = 128
  storage_iops              = 6400
  backup_retention_days     = 35
  geo_redundant_backup      = true
  high_availability_enabled = true
  primary_zone              = "1"
  standby_zone              = "2"

  databases       = ["app"]
  max_connections = 500

  tags = local.tags
}

# ── Azure Container Registry ───────────────────────────────────────────────────
module "acr" {
  source = "../../modules/acr"

  acr_name                          = "acrprod${replace(local.name_prefix, "-", "")}"
  resource_group_name               = azurerm_resource_group.main.name
  location                          = local.location
  sku                               = "Premium"
  public_network_access_enabled     = false  # Prod: private endpoint only
  zone_redundancy_enabled           = true
  geo_replication_locations         = ["westeurope"] # DR replication
  private_endpoint_subnet_id        = module.vnet.aks_subnet_id
  vnet_id                           = module.vnet.vnet_id
  create_private_dns_zone           = true
  aks_kubelet_identity_principal_id = module.aks.kubelet_identity
  log_analytics_workspace_id        = module.aks.log_analytics_workspace_id
  enable_defender                   = true
  quarantine_policy_enabled         = true
  export_policy_enabled             = false
  tags                              = local.tags
}

# ── Redis Cache ────────────────────────────────────────────────────────────────
module "redis" {
  source = "../../modules/redis"

  name                       = local.name_prefix
  resource_group_name        = azurerm_resource_group.main.name
  location                   = local.location
  vnet_id                    = module.vnet.vnet_id
  private_endpoint_subnet_id = module.vnet.aks_subnet_id
  sku_name                   = "Premium"
  family                     = "P"
  capacity                   = 1
  enable_persistence         = true
  zones                      = ["1", "2", "3"]
  key_vault_id               = azurerm_key_vault.main.id
  log_analytics_workspace_id = module.aks.log_analytics_workspace_id
  tags                       = local.tags
}

# ── Workload Identity ─────────────────────────────────────────────────────────
module "workload_identity" {
  source = "../../modules/workload_identity"

  cluster_name        = module.aks.cluster_name
  resource_group_name = azurerm_resource_group.main.name
  location            = local.location
  aks_oidc_issuer_url = module.aks.oidc_issuer_url

  workloads = {
    frontend = {
      namespace            = "frontend"
      service_account_name = "frontend-sa"
      azure_roles          = []
    }
    backend = {
      namespace            = "backend"
      service_account_name = "backend-sa"
      azure_roles = [
        {
          role_definition_name = "Key Vault Secrets User"
          scope                = azurerm_key_vault.main.id
        }
      ]
    }
  }
  tags = local.tags
}

# ── Velero Backup ─────────────────────────────────────────────────────────────
module "velero" {
  source = "../../modules/velero"

  cluster_name         = module.aks.cluster_name
  resource_group_name  = azurerm_resource_group.main.name
  location             = local.location
  storage_account_name = "velprd${substr(replace(local.name_prefix, "-", ""), 0, 14)}"
  replication_type     = "GRS" # Geo-redundant for prod DR
  backup_retention_days = 90
  aks_oidc_issuer_url  = module.aks.oidc_issuer_url
  # Restrict storage access to the AKS subnet only
  allowed_subnet_ids   = [module.vnet.aks_subnet_id]
  tags                 = local.tags
}

# ── DNS Zone ───────────────────────────────────────────────────────────────────────
# Production DNS zone. After apply, delegate domain to Azure DNS at your registrar.
module "dns" {
  source = "../../modules/dns"

  domain_name         = var.domain_name
  resource_group_name = azurerm_resource_group.main.name

  # Apex ALIAS record (@) → Front Door endpoint
  apex_alias_enabled             = var.apex_alias_enabled
  frontdoor_endpoint_resource_id = module.frontdoor.frontdoor_id

  # Subdomains → Front Door CNAME
  subdomain_cname_records = {
    for subdomain in var.subdomains :
    subdomain => { target = module.frontdoor.endpoint_hostname }
  }

  # Front Door validation tokens
  frontdoor_validation_records = merge(
    var.apex_alias_enabled ? { "@" = lookup(module.frontdoor.custom_domain_validation_tokens, var.domain_name, "") } : {},
    {
      for subdomain in var.subdomains :
      subdomain => lookup(module.frontdoor.custom_domain_validation_tokens, "${subdomain}.${var.domain_name}", "")
    }
  )

  # Email records
  mx_records   = var.mx_records
  spf_record   = var.spf_record
  dmarc_record = var.dmarc_record

  log_analytics_workspace_id = module.aks.log_analytics_workspace_id
  tags                       = local.tags
}

# ── Outputs ───────────────────────────────────────────────────────────────────
output "aks_cluster_name" {
  value = module.aks.cluster_name
}

output "frontdoor_endpoint" {
  description = "Default AFD hostname — use as CNAME target until custom domains are validated"
  value       = module.frontdoor.endpoint_hostname
}

output "frontdoor_waf_policy_id" {
  value = module.frontdoor.waf_policy_id
}

output "appgw_public_ip" {
  description = "App Gateway IP (origin behind Front Door — do not expose in public DNS)"
  value       = module.waf.public_ip_address
}

output "appgw_waf_policy_id" {
  value = module.waf.waf_policy_id
}

output "key_vault_name" {
  value = azurerm_key_vault.main.name
}

output "custom_domain_dns_instructions" {
  description = "DNS records required to validate custom domains and route traffic through Front Door"
  value       = module.frontdoor.custom_domain_validation_tokens
}

output "mysql_fqdn" {
  description = "Private FQDN of the MySQL server (resolvable only inside the VNet)"
  value       = module.mysql.fqdn
}

output "mysql_connection_string_secret" {
  description = "Key Vault secret name for the MySQL connection string — mount into pods via CSI driver"
  value       = module.mysql.connection_string_secret_name
}

output "acr_login_server" {
  description = "ACR private login server FQDN — use in Helm values and image references"
  value       = module.acr.login_server
}

output "redis_hostname" {
  value = module.redis.hostname
}

output "velero_storage_account" {
  value = module.velero.storage_account_name
}

output "velero_identity_client_id" {
  description = "Velero managed identity client ID — set in Velero Helm chart values"
  value       = module.velero.velero_identity_client_id
}

output "workload_identity_client_ids" {
  description = "Map of workload → Azure managed identity client ID. Use to annotate Kubernetes ServiceAccounts."
  value       = module.workload_identity.identity_client_ids
}

output "dns_name_servers" {
  description = "*** ACTION REQUIRED: Set these 4 nameservers at your domain registrar to delegate DNS to Azure ***"
  value       = module.dns.name_servers
}

output "dns_zone_name" {
  description = "The DNS zone name hosted in Azure."
  value       = module.dns.zone_name
}

output "dns_subdomain_fqdns" {
  description = "Fully-qualified domain names for each subdomain record."
  value       = module.dns.subdomain_fqdns
}
