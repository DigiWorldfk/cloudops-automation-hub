# ─────────────────────────────────────────────────────────────────────────────
# Azure Front Door Premium Profile
# ─────────────────────────────────────────────────────────────────────────────
resource "azurerm_cdn_frontdoor_profile" "main" {
  name                     = "${var.name_prefix}-afd"
  resource_group_name      = var.resource_group_name
  sku_name                 = var.sku_name   # "Premium_AzureFrontDoor" or "Standard_AzureFrontDoor"
  response_timeout_seconds = 120

  tags = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Front Door WAF Policy
# Premium SKU supports managed rulesets (OWASP, Bot, DDoS)
# ─────────────────────────────────────────────────────────────────────────────
resource "azurerm_cdn_frontdoor_firewall_policy" "main" {
  name                              = "${replace(var.name_prefix, "-", "")}afdwaf"
  resource_group_name               = var.resource_group_name
  sku_name                          = var.sku_name
  enabled                           = true
  mode                              = var.waf_mode   # "Prevention" | "Detection"
  redirect_url                      = var.waf_redirect_url
  custom_block_response_status_code = 403
  custom_block_response_body        = base64encode("<html><body><h1>403 Forbidden</h1><p>Request blocked by security policy.</p></body></html>")

  # ── Managed rulesets ───────────────────────────────────────────────────────
  managed_rule {
    type    = "DefaultRuleSet"
    version = "1.1"
    action  = "Block"

    # Tune noisy rules for SPA / REST API setups
    override {
      rule_group_name = "SQLI"
      rule {
        rule_id = "942200"
        action  = "Log"
        enabled = true
      }
    }
  }

  managed_rule {
    type    = "Microsoft_BotManagerRuleSet"
    version = "1.1"
    action  = "Block"
  }

  # ── Custom rules ───────────────────────────────────────────────────────────
  # 1. Geo-blocking
  dynamic "custom_rule" {
    for_each = length(var.blocked_countries) > 0 ? [1] : []
    content {
      name                           = "BlockHighRiskCountries"
      enabled                        = true
      priority                       = 10
      rate_limit_duration_in_minutes = 1
      rate_limit_threshold           = 10
      type                           = "MatchRule"
      action                         = "Block"

      match_condition {
        match_variable     = "RemoteAddr"
        operator           = "GeoMatch"
        negation_condition = false
        match_values       = var.blocked_countries
      }
    }
  }

  # 2. Rate-limit on API paths — prevents brute-force / scraping
  custom_rule {
    name                           = "RateLimitAPI"
    enabled                        = true
    priority                       = 20
    rate_limit_duration_in_minutes = 1
    rate_limit_threshold           = var.api_rate_limit_threshold
    type                           = "RateLimitRule"
    action                         = "Block"

    match_condition {
      match_variable     = "RequestUri"
      operator           = "Contains"
      negation_condition = false
      match_values       = ["/api/"]
    }
  }

  # 3. Block common bad user agents
  custom_rule {
    name                           = "BlockMaliciousUA"
    enabled                        = true
    priority                       = 30
    rate_limit_duration_in_minutes = 1
    rate_limit_threshold           = 100
    type                           = "MatchRule"
    action                         = "Block"

    match_condition {
      match_variable     = "RequestHeader"
      selector           = "User-Agent"
      operator           = "Contains"
      negation_condition = false
      match_values       = ["masscan", "sqlmap", "nikto", "nmap", "zgrab"]
    }
  }

  tags = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Security Policy — attaches the WAF policy to the Front Door profile
# ─────────────────────────────────────────────────────────────────────────────
resource "azurerm_cdn_frontdoor_security_policy" "main" {
  name                     = "${var.name_prefix}-afd-security"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id

  security_policies {
    firewall {
      cdn_frontdoor_firewall_policy_id = azurerm_cdn_frontdoor_firewall_policy.main.id

      association {
        # Apply WAF to all endpoints + domains
        patterns_to_match = ["/*"]

        dynamic "domain" {
          for_each = azurerm_cdn_frontdoor_endpoint.main[*]
          content {
            cdn_frontdoor_domain_id = domain.value.id
          }
        }

        dynamic "domain" {
          for_each = azurerm_cdn_frontdoor_custom_domain.main
          content {
            cdn_frontdoor_domain_id = domain.value.id
          }
        }
      }
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Front Door Endpoint (the *.z01.azurefd.net public hostname)
# ─────────────────────────────────────────────────────────────────────────────
resource "azurerm_cdn_frontdoor_endpoint" "main" {
  name                     = "${var.name_prefix}-afd-ep"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id
  enabled                  = true

  tags = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Custom Domains (one per hostname in var.custom_domains)
# ─────────────────────────────────────────────────────────────────────────────
resource "azurerm_cdn_frontdoor_custom_domain" "main" {
  for_each = toset(var.custom_domains)

  name                     = replace(each.key, ".", "-")
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id
  host_name                = each.key

  tls {
    certificate_type    = "ManagedCertificate"   # AFD auto-provisions & renews
    minimum_tls_version = "TLS12"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Origin Group — contains the App Gateway as the single regional origin
# ─────────────────────────────────────────────────────────────────────────────
resource "azurerm_cdn_frontdoor_origin_group" "main" {
  name                     = "${var.name_prefix}-origin-group"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id

  load_balancing {
    sample_size                 = 4
    successful_samples_required = 3
    additional_latency_in_milliseconds = 50
  }

  health_probe {
    path                = "/healthz"
    request_type        = "GET"
    protocol            = "Https"
    interval_in_seconds = 30
  }

  session_affinity_enabled = false
  restore_traffic_time_to_healed_or_new_endpoint_in_minutes = 10
}

# ─────────────────────────────────────────────────────────────────────────────
# Origin — the App Gateway public IP / hostname
# ─────────────────────────────────────────────────────────────────────────────
resource "azurerm_cdn_frontdoor_origin" "appgw" {
  name                          = "${var.name_prefix}-appgw-origin"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.main.id

  enabled                        = true
  host_name                      = var.appgw_public_ip_address
  http_port                      = 80
  https_port                     = 443
  origin_host_header             = var.appgw_public_ip_address
  priority                       = 1
  weight                         = 1000
  certificate_name_check_enabled = false   # App GW cert is checked at App GW level

  # Premium SKU: use Private Link to avoid exposing App GW to public internet
  dynamic "private_link" {
    for_each = var.sku_name == "Premium_AzureFrontDoor" && var.appgw_private_link_resource_id != null ? [1] : []
    content {
      request_message        = "AFD private link to App Gateway"
      target_type            = "appGatewayFrontendIpConfiguration"
      location               = var.location
      private_link_target_id = var.appgw_private_link_resource_id
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Route — maps incoming requests to the origin group
# ─────────────────────────────────────────────────────────────────────────────
resource "azurerm_cdn_frontdoor_route" "main" {
  name                          = "${var.name_prefix}-route"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.main.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.main.id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.appgw.id]

  supported_protocols    = ["Http", "Https"]
  patterns_to_match      = ["/*"]
  forwarding_protocol    = "HttpsOnly"
  https_redirect_enabled = true
  link_to_default_domain = true

  # Attach custom domains to this route
  cdn_frontdoor_custom_domain_ids = [
    for d in azurerm_cdn_frontdoor_custom_domain.main : d.id
  ]

  cache {
    query_string_caching_behavior = "UseQueryString"
    compression_enabled           = true
    content_types_to_compress = [
      "text/html",
      "text/css",
      "application/javascript",
      "application/json",
      "image/svg+xml",
    ]
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Custom Domain Association (required to link domains to the route)
# ─────────────────────────────────────────────────────────────────────────────
resource "azurerm_cdn_frontdoor_custom_domain_association" "main" {
  for_each = azurerm_cdn_frontdoor_custom_domain.main

  cdn_frontdoor_custom_domain_id = each.value.id
  cdn_frontdoor_route_ids        = [azurerm_cdn_frontdoor_route.main.id]
}

# ─────────────────────────────────────────────────────────────────────────────
# Diagnostic Settings — ship AFD + WAF logs to Log Analytics
# ─────────────────────────────────────────────────────────────────────────────
resource "azurerm_monitor_diagnostic_setting" "afd" {
  name                       = "${var.name_prefix}-afd-diag"
  target_resource_id         = azurerm_cdn_frontdoor_profile.main.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "FrontDoorAccessLog"
  }

  enabled_log {
    category = "FrontDoorWebApplicationFirewallLog"   # WAF block/detect events
  }

  enabled_log {
    category = "FrontDoorHealthProbeLog"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
