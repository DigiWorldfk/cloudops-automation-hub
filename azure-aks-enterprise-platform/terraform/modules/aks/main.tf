resource "azurerm_kubernetes_cluster" "main" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.name
  kubernetes_version  = var.kubernetes_version

  # Auto-upgrade: patch channel keeps nodes patched without manual intervention
  automatic_channel_upgrade = var.environment == "prod" ? "patch" : "node-image"
  node_os_upgrade_channel   = "NodeImage"

  # Maintenance window: upgrades only on Sunday nights (low traffic)
  maintenance_window_auto_upgrade {
    frequency   = "Weekly"
    interval    = 1
    duration    = 4
    day_of_week = "Sunday"
    utc_offset  = "+00:00"
    start_time  = "02:00"
  }

  maintenance_window_node_os {
    frequency   = "Weekly"
    interval    = 1
    duration    = 4
    day_of_week = "Sunday"
    utc_offset  = "+00:00"
    start_time  = "04:00"
  }

  default_node_pool {
    name                = "system"
    node_count          = var.default_node_count
    vm_size             = var.default_vm_size
    enable_auto_scaling = var.min_node_count != null
    min_count           = var.min_node_count
    max_count           = var.max_node_count
    os_disk_size_gb     = var.os_disk_size_gb
    type                = "VirtualMachineScaleSets"
    vnet_subnet_id      = var.vnet_subnet_id

    upgrade_settings {
      max_surge = var.node_pool_max_surge
    }
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin    = "azure"
    network_policy    = "calico"
    load_balancer_sku = var.load_balancer_sku
  }

  # Restrict API server access to known CIDRs (VPN, CI/CD, bastion)
  # In prod, set var.api_server_authorized_ip_ranges to your actual ranges
  dynamic "api_server_access_profile" {
    for_each = length(var.api_server_authorized_ip_ranges) > 0 ? [1] : []
    content {
      authorized_ip_ranges = var.api_server_authorized_ip_ranges
    }
  }

  azure_active_directory_role_based_access_control {
    managed            = true
    azure_rbac_enabled = true
  }

  # Required for Azure Workload Identity (pod-level managed identity via OIDC)
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  }

  # ── AGIC addon — wires AKS to the Application Gateway WAF ─────────────────
  dynamic "ingress_application_gateway" {
    for_each = var.application_gateway_id != null ? [1] : []
    content {
      gateway_id = var.application_gateway_id
    }
  }

  tags = var.tags
}

# ─── Microsoft Defender for Containers ───────────────────────────────────────
# Provides runtime threat detection, vulnerability assessment for images,
# and Kubernetes audit log analysis.
resource "azurerm_security_center_subscription_pricing" "defender_containers" {
  tier          = "Standard"
  resource_type = "KubernetesService"
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.name}-law"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.environment == "prod" ? 90 : 30

  tags = var.tags
}

# ─── AKS Control-Plane Diagnostic Settings ────────────────────────────────────
# Sends Kubernetes API server, audit, scheduler, and controller logs
# to Log Analytics for security forensics and compliance.
resource "azurerm_monitor_diagnostic_setting" "aks" {
  name                       = "aks-diagnostics"
  target_resource_id         = azurerm_kubernetes_cluster.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log { category = "kube-apiserver" }
  enabled_log { category = "kube-audit" }
  enabled_log { category = "kube-audit-admin" }
  enabled_log { category = "kube-controller-manager" }
  enabled_log { category = "kube-scheduler" }
  enabled_log { category = "cluster-autoscaler" }
  enabled_log { category = "guard" }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
