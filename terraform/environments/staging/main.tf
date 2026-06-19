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

  # Backend config loaded via: terraform init -backend-config=backend.hcl (never committed)
  backend "azurerm" {}
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
  }
}

locals {
  environment = "staging"
  location    = var.location
  prefix      = "aks-stg"

  tags = {
    environment  = local.environment
    project      = "digital-freelance-world"
    managed-by   = "terraform"
    cost-center  = "engineering"
    owner        = "platform-team"
  }
}

# ─── Resource Group ───────────────────────────────────────────────────────────
resource "azurerm_resource_group" "main" {
  name     = "rg-${local.prefix}"
  location = local.location
  tags     = local.tags
}

# ─── VNet Module ──────────────────────────────────────────────────────────────
module "vnet" {
  source = "../../modules/vnet"

  resource_group_name = azurerm_resource_group.main.name
  location            = local.location
  vnet_name           = "vnet-${local.prefix}"
  address_space       = [var.vnet_cidr]
  aks_subnet_cidr     = var.aks_subnet_cidr
  appgw_subnet_cidr   = var.appgw_subnet_cidr
  mysql_subnet_cidr   = var.mysql_subnet_cidr
  tags                = local.tags
}

# ─── Key Vault ────────────────────────────────────────────────────────────────
data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "main" {
  name                       = "kv-${local.prefix}"
  resource_group_name        = azurerm_resource_group.main.name
  location                   = local.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  enable_rbac_authorization  = true   # Use Azure RBAC for access control (consistent with dev/prod)
  purge_protection_enabled   = true
  soft_delete_retention_days = 7

  network_acls {
    default_action = "Allow" # Staging is more permissive than prod
    bypass         = "AzureServices"
  }

  tags = local.tags
}

# ─── Log Analytics ────────────────────────────────────────────────────────────
resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-${local.prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = local.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

# ─── ACR Module ───────────────────────────────────────────────────────────────
module "acr" {
  source = "../../modules/acr"

  acr_name                          = "acrstg${replace(local.prefix, "-", "")}"
  resource_group_name               = azurerm_resource_group.main.name
  location                          = local.location
  sku                               = "Standard"   # Standard is sufficient for staging
  public_network_access_enabled     = true         # Staging allows public for ease of testing
  aks_kubelet_identity_principal_id = module.aks.kubelet_identity
  log_analytics_workspace_id        = azurerm_log_analytics_workspace.main.id
  enable_defender                   = false        # Cost saving for staging
  tags                              = local.tags
}

# ─── AKS Module ───────────────────────────────────────────────────────────────
module "aks" {
  source = "../../modules/aks"

  cluster_name                = "aks-${local.prefix}"
  resource_group_name         = azurerm_resource_group.main.name
  location                    = local.location
  kubernetes_version          = var.kubernetes_version
  vnet_subnet_id              = module.vnet.aks_subnet_id
  application_gateway_id      = module.waf.application_gateway_id
  log_analytics_workspace_id  = azurerm_log_analytics_workspace.main.id

  # Staging uses smaller, cheaper nodes — same generation as prod to catch issues
  default_node_pool = {
    name                = "system"
    vm_size             = var.aks_vm_size
    min_count           = var.aks_min_node_count
    max_count           = var.aks_max_node_count
    os_disk_size_gb     = 128
    availability_zones  = ["1", "2"]
  }

  tags = local.tags
}

# ─── WAF Module ───────────────────────────────────────────────────────────────
module "waf" {
  source = "../../modules/waf"

  name                       = local.prefix
  resource_group_name        = azurerm_resource_group.main.name
  location                   = local.location
  subnet_id                  = module.vnet.appgw_subnet_id
  key_vault_id               = azurerm_key_vault.main.id
  tls_cert_keyvault_secret_id = var.tls_cert_keyvault_secret_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  waf_mode                   = "Detection" # Detection in staging — flip to Prevention for pre-prod soak

  tags = local.tags
}

# ─── Front Door Module ────────────────────────────────────────────────────────
module "frontdoor" {
  source = "../../modules/frontdoor"

  name                       = local.prefix
  resource_group_name        = azurerm_resource_group.main.name
  sku_name                   = "Standard_AzureFrontDoor" # Standard for staging (cheaper)
  origin_hostname            = module.waf.public_ip_address
  custom_domains             = var.custom_domains
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  tags = local.tags
}

# ─── MySQL Module ─────────────────────────────────────────────────────────────
module "mysql" {
  source = "../../modules/mysql"

  name                       = local.prefix
  resource_group_name        = azurerm_resource_group.main.name
  location                   = local.location
  delegated_subnet_id        = module.vnet.mysql_subnet_id
  private_dns_zone_vnet_id   = module.vnet.vnet_id
  key_vault_id               = azurerm_key_vault.main.id
  administrator_login        = "mysqladmin"
  administrator_password     = var.mysql_admin_password
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  sku_name               = "B_Standard_B2ms" # Slightly larger than dev for realistic perf testing
  mysql_version          = "8.0.21"
  high_availability_mode = "Disabled"
  backup_retention_days  = 7
  geo_redundant_backup   = "Disabled"

  tags = local.tags
}

# ─── Redis Module ─────────────────────────────────────────────────────────────
module "redis" {
  source = "../../modules/redis"

  name                       = local.prefix
  resource_group_name        = azurerm_resource_group.main.name
  location                   = local.location
  vnet_id                    = module.vnet.vnet_id
  private_endpoint_subnet_id = module.vnet.aks_subnet_id
  sku_name                   = "Standard"
  family                     = "C"
  capacity                   = 1
  key_vault_id               = azurerm_key_vault.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tags                       = local.tags
}

# ─── Workload Identity Module ─────────────────────────────────────────────────
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

# ─── Velero Backup ────────────────────────────────────────────────────────────
module "velero" {
  source = "../../modules/velero"

  cluster_name         = module.aks.cluster_name
  resource_group_name  = azurerm_resource_group.main.name
  location             = local.location
  storage_account_name = "velstg${substr(replace(local.prefix, "-", ""), 0, 14)}"
  replication_type     = "LRS"
  backup_retention_days = 30
  aks_oidc_issuer_url  = module.aks.oidc_issuer_url
  tags                 = local.tags
}

# ─── DNS Zone ─────────────────────────────────────────────────────────────────
module "dns" {
  source = "../../modules/dns"

  domain_name         = var.domain_name
  resource_group_name = azurerm_resource_group.main.name

  apex_alias_enabled             = var.apex_alias_enabled
  frontdoor_endpoint_resource_id = module.frontdoor.frontdoor_id

  subdomain_cname_records = {
    for subdomain in var.subdomains :
    subdomain => { target = module.frontdoor.endpoint_hostname }
  }

  frontdoor_validation_records = merge(
    var.apex_alias_enabled ? { "@" = lookup(module.frontdoor.custom_domain_validation_tokens, var.domain_name, "") } : {},
    {
      for subdomain in var.subdomains :
      subdomain => lookup(module.frontdoor.custom_domain_validation_tokens, "${subdomain}.${var.domain_name}", "")
    }
  )

  mx_records   = var.mx_records
  spf_record   = var.spf_record
  dmarc_record = var.dmarc_record

  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tags                       = local.tags
}

# ─── Outputs ──────────────────────────────────────────────────────────────────
output "aks_cluster_name" {
  value = module.aks.cluster_name
}

output "acr_login_server" {
  value = module.acr.login_server
}

output "frontdoor_endpoint" {
  value = module.frontdoor.endpoint_hostname
}

output "appgw_public_ip" {
  value = module.waf.public_ip_address
}

output "mysql_fqdn" {
  value = module.mysql.fqdn
}

output "velero_storage_account" {
  value = module.velero.storage_account_name
}

output "velero_identity_client_id" {
  value = module.velero.velero_identity_client_id
}

output "workload_identity_client_ids" {
  value = module.workload_identity.identity_client_ids
}

output "dns_name_servers" {
  description = "*** ACTION REQUIRED: Set these 4 nameservers at your domain registrar to delegate DNS to Azure ***"
  value       = module.dns.name_servers
}

output "dns_zone_name" {
  value = module.dns.zone_name
}

output "dns_subdomain_fqdns" {
  value = module.dns.subdomain_fqdns
}
