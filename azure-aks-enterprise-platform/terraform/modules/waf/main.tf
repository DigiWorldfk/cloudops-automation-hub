# ─────────────────────────────────────────────────────────────────────────────
# WAF Policy
# ─────────────────────────────────────────────────────────────────────────────
resource "azurerm_web_application_firewall_policy" "main" {
  name                = "${var.name_prefix}-waf-policy"
  resource_group_name = var.resource_group_name
  location            = var.location

  # ── Managed OWASP ruleset ──────────────────────────────────────────────────
  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
    }

    managed_rule_set {
      type    = "Microsoft_BotManagerRuleSet"
      version = "1.0"
    }

    # Exclude noisy rules that cause false positives in typical SPA/API setups
    exclusion {
      match_variable          = "RequestHeaderNames"
      selector_match_operator = "Equals"
      selector                = "x-csrf-token"
    }
    exclusion {
      match_variable          = "RequestCookieNames"
      selector_match_operator = "StartsWith"
      selector                = "sess-"
    }
  }

  # ── Custom rules ───────────────────────────────────────────────────────────
  custom_rules {
    name      = "BlockHighRiskCountries"
    priority  = 10
    rule_type = "MatchRule"
    action    = "Block"

    match_conditions {
      match_variables {
        variable_name = "RemoteAddr"
      }
      operator           = "GeoMatch"
      negation_condition = false
      match_values       = var.blocked_countries
    }
  }

  custom_rules {
    name      = "RateLimitPerIP"
    priority  = 20
    rule_type = "RateLimitRule"
    action    = "Block"

    rate_limit_duration              = "FiveMins"
    rate_limit_threshold             = 500
    group_rate_limit_by              = "ClientAddr"

    match_conditions {
      match_variables {
        variable_name = "RequestUri"
      }
      operator           = "Contains"
      negation_condition = false
      match_values       = ["/api/"]
    }
  }

  # ── Policy settings ────────────────────────────────────────────────────────
  policy_settings {
    enabled                          = true
    mode                             = var.waf_mode   # "Prevention" | "Detection"
    request_body_check               = true
    max_request_body_size_in_kb      = 128
    file_upload_limit_in_mb          = 100

    log_scrubbing {
      enabled = true
      rule {
        enabled                 = true
        match_variable          = "RequestHeaderNames"
        selector_match_operator = "Equals"
        selector                = "authorization"
      }
      rule {
        enabled                 = true
        match_variable          = "RequestCookieNames"
        selector_match_operator = "Contains"
        selector                = "token"
      }
    }
  }

  tags = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Public IP for the Application Gateway
# ─────────────────────────────────────────────────────────────────────────────
resource "azurerm_public_ip" "appgw" {
  name                = "${var.name_prefix}-appgw-pip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]

  tags = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Application Gateway (WAF_v2) — front door for AKS traffic
# ─────────────────────────────────────────────────────────────────────────────
resource "azurerm_application_gateway" "main" {
  name                = "${var.name_prefix}-appgw"
  resource_group_name = var.resource_group_name
  location            = var.location
  zones               = ["1", "2", "3"]
  firewall_policy_id  = azurerm_web_application_firewall_policy.main.id
  enable_http2        = true

  # ── SKU — WAF_v2 with autoscaling ─────────────────────────────────────────
  sku {
    name = "WAF_v2"
    tier = "WAF_v2"
  }

  autoscale_configuration {
    min_capacity = var.appgw_min_capacity
    max_capacity = var.appgw_max_capacity
  }

  # ── Network ────────────────────────────────────────────────────────────────
  gateway_ip_configuration {
    name      = "appgw-ip-config"
    subnet_id = var.appgw_subnet_id
  }

  frontend_ip_configuration {
    name                 = "public-frontend"
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  frontend_port {
    name = "port-80"
    port = 80
  }

  frontend_port {
    name = "port-443"
    port = 443
  }

  # ── TLS certificate (from Key Vault via managed identity) ──────────────────
  ssl_certificate {
    name                = "main-tls"
    key_vault_secret_id = var.tls_cert_keyvault_secret_id
  }

  ssl_policy {
    policy_type          = "Predefined"
    policy_name          = "AppGwSslPolicy20220101"   # TLS 1.2+ only
  }

  # ── Backend (AKS nodes / AGIC managed) ────────────────────────────────────
  backend_address_pool {
    name = "aks-backend-pool"
  }

  backend_http_settings {
    name                  = "aks-http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60

    probe_name = "aks-health-probe"

    connection_draining {
      enabled           = true
      drain_timeout_sec = 30
    }
  }

  probe {
    name                = "aks-health-probe"
    protocol            = "Http"
    path                = "/healthz"
    interval            = 15
    timeout             = 10
    unhealthy_threshold = 3
    host                = "127.0.0.1"

    match {
      status_code = ["200-399"]
    }
  }

  # ── HTTP → HTTPS redirect ──────────────────────────────────────────────────
  http_listener {
    name                           = "http-listener"
    frontend_ip_configuration_name = "public-frontend"
    frontend_port_name             = "port-80"
    protocol                       = "Http"
  }

  redirect_configuration {
    name                 = "http-to-https"
    redirect_type        = "Permanent"
    target_listener_name = "https-listener"
    include_path         = true
    include_query_string = true
  }

  request_routing_rule {
    name                        = "http-redirect-rule"
    rule_type                   = "Basic"
    http_listener_name          = "http-listener"
    redirect_configuration_name = "http-to-https"
    priority                    = 100
  }

  # ── HTTPS listener ─────────────────────────────────────────────────────────
  http_listener {
    name                           = "https-listener"
    frontend_ip_configuration_name = "public-frontend"
    frontend_port_name             = "port-443"
    protocol                       = "Https"
    ssl_certificate_name           = "main-tls"
    firewall_policy_id             = azurerm_web_application_firewall_policy.main.id
  }

  request_routing_rule {
    name                       = "https-routing-rule"
    rule_type                  = "Basic"
    http_listener_name         = "https-listener"
    backend_address_pool_name  = "aks-backend-pool"
    backend_http_settings_name = "aks-http-settings"
    priority                   = 200
  }

  # ── Diagnostics ────────────────────────────────────────────────────────────
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.appgw.id]
  }

  lifecycle {
    # AGIC manages backend pool / routing rules — ignore its changes to avoid conflicts
    ignore_changes = [
      backend_address_pool,
      backend_http_settings,
      frontend_port,
      http_listener,
      probe,
      request_routing_rule,
      redirect_configuration,
      ssl_certificate,
      tags["managed-by-k8s-ingress"],
    ]
  }

  tags = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Managed Identity — allows App GW to read TLS certs from Key Vault
# ─────────────────────────────────────────────────────────────────────────────
resource "azurerm_user_assigned_identity" "appgw" {
  name                = "${var.name_prefix}-appgw-identity"
  resource_group_name = var.resource_group_name
  location            = var.location

  tags = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Key Vault access — let the App GW identity read the TLS certificate
# ─────────────────────────────────────────────────────────────────────────────
resource "azurerm_key_vault_access_policy" "appgw" {
  key_vault_id = var.key_vault_id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.appgw.principal_id

  secret_permissions      = ["Get"]
  certificate_permissions = ["Get"]
}

data "azurerm_client_config" "current" {}

# ─────────────────────────────────────────────────────────────────────────────
# Diagnostic settings — ship WAF logs to Log Analytics
# ─────────────────────────────────────────────────────────────────────────────
resource "azurerm_monitor_diagnostic_setting" "appgw" {
  name                       = "${var.name_prefix}-appgw-diag"
  target_resource_id         = azurerm_application_gateway.main.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "ApplicationGatewayAccessLog"
  }

  enabled_log {
    category = "ApplicationGatewayFirewallLog"    # WAF block/detect events
  }

  enabled_log {
    category = "ApplicationGatewayPerformanceLog"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Role assignment — let AGIC (AKS kubelet identity) manage the App Gateway
# ─────────────────────────────────────────────────────────────────────────────
resource "azurerm_role_assignment" "agic_contributor" {
  scope                = azurerm_application_gateway.main.id
  role_definition_name = "Contributor"
  principal_id         = var.aks_kubelet_identity_object_id
}

resource "azurerm_role_assignment" "agic_rg_reader" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${var.resource_group_name}"
  role_definition_name = "Reader"
  principal_id         = var.aks_kubelet_identity_object_id
}
