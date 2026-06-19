terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }
}

# ─── Storage Account for Velero Backups ──────────────────────────────────────
resource "azurerm_storage_account" "velero" {
  name                            = var.storage_account_name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = var.replication_type # GRS for prod, LRS for dev
  allow_nested_items_to_be_public = false
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  # Restrict storage access to Azure services only (Velero uses workload identity)
  # Deny direct internet access — only Azure backbone traffic allowed
  network_rules {
    default_action             = "Deny"
    bypass                     = ["AzureServices"]
    virtual_network_subnet_ids = var.allowed_subnet_ids
    ip_rules                   = var.allowed_ip_ranges
  }

  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = var.blob_soft_delete_days
    }
    container_delete_retention_policy {
      days = var.blob_soft_delete_days
    }
  }

  tags = var.tags
}

resource "azurerm_storage_container" "velero" {
  name                  = "velero"
  storage_account_name  = azurerm_storage_account.velero.name
  container_access_type = "private"
}

# ─── User-Assigned Managed Identity for Velero ───────────────────────────────
resource "azurerm_user_assigned_identity" "velero" {
  name                = "id-velero-${var.cluster_name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

# ─── Federated Credential (Workload Identity) ─────────────────────────────────
resource "azurerm_federated_identity_credential" "velero" {
  name                = "fic-velero-${var.cluster_name}"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.velero.id
  issuer              = var.aks_oidc_issuer_url
  subject             = "system:serviceaccount:velero:velero-server"
  audience            = ["api://AzureADTokenExchange"]
}

# ─── Role Assignment — Storage Blob Data Contributor ─────────────────────────
resource "azurerm_role_assignment" "velero_storage" {
  principal_id         = azurerm_user_assigned_identity.velero.principal_id
  role_definition_name = "Storage Blob Data Contributor"
  scope                = azurerm_storage_account.velero.id
  skip_service_principal_aad_check = true
}

# ─── Lifecycle Policy — Auto-expire old backups ───────────────────────────────
resource "azurerm_storage_management_policy" "velero" {
  storage_account_id = azurerm_storage_account.velero.id

  rule {
    name    = "expire-old-backups"
    enabled = true

    filters {
      prefix_match = ["velero/backups/"]
      blob_types   = ["blockBlob"]
    }

    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than    = 30
        tier_to_archive_after_days_since_modification_greater_than = 60
        delete_after_days_since_modification_greater_than          = var.backup_retention_days
      }
    }
  }
}
