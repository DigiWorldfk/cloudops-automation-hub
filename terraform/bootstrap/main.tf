# Bootstrap: creates the Azure storage account and container used for
# Terraform remote state. Run this ONCE manually before any environment deploy.
#
# Usage:
#   terraform init   (no backend — state is stored locally just for bootstrap)
#   terraform apply

terraform {
  required_version = ">= 1.5"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "norwayeast"
}

variable "environments" {
  description = "Environments that need their own state container"
  type        = list(string)
  default     = ["dev", "staging", "prod"]
}

resource "random_string" "suffix" {
  length  = 4
  upper   = false
  special = false
}

resource "azurerm_resource_group" "tfstate" {
  for_each = toset(var.environments)

  name     = "rg-tfstate-${each.key}"
  location = var.location

  tags = {
    purpose    = "terraform-state"
    environment = each.key
    managed_by = "terraform-bootstrap"
  }
}

resource "azurerm_storage_account" "tfstate" {
  for_each = toset(var.environments)

  name                     = "sttfstate${each.key}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.tfstate[each.key].name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 30
    }
  }

  tags = {
    purpose     = "terraform-state"
    environment = each.key
    managed_by  = "terraform-bootstrap"
  }
}

resource "azurerm_storage_container" "tfstate" {
  for_each = toset(var.environments)

  name                  = "tfstate"
  storage_account_name  = azurerm_storage_account.tfstate[each.key].name
  container_access_type = "private"
}

output "storage_account_names" {
  description = "Storage account names per environment — update backend configs with these"
  value = {
    for env in var.environments :
    env => azurerm_storage_account.tfstate[env].name
  }
}
