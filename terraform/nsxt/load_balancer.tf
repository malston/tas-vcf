# terraform/nsxt/load_balancer.tf

# --- Health Monitors ---

resource "nsxt_policy_lb_http_monitor_profile" "gorouter_monitor" {
  display_name       = "${var.environment_name}-gorouter-monitor"
  description        = "Health monitor for GoRouters"
  request_method     = "GET"
  request_url        = "/health"
  request_version    = "HTTP_VERSION_1_1"
  response_status_codes = [200]
  monitor_port       = 8080
  request_header {
    name  = "Host"
    value = "gorouter-health"
  }

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}

resource "nsxt_policy_lb_http_monitor_profile" "tcp_router_monitor" {
  display_name       = "${var.environment_name}-tcp-router-monitor"
  description        = "Health monitor for TCP Routers"
  request_method     = "GET"
  request_url        = "/health"
  request_version    = "HTTP_VERSION_1_1"
  response_status_codes = [200]
  monitor_port       = 80

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}

resource "nsxt_policy_lb_tcp_monitor_profile" "ssh_monitor" {
  display_name = "${var.environment_name}-ssh-monitor"
  description  = "Health monitor for Diego Brain SSH"
  monitor_port = 2222

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}

# --- Server Pools ---

resource "nsxt_policy_lb_pool" "gorouter_pool" {
  display_name         = "${var.environment_name}-gorouter-pool"
  description          = "Pool for GoRouter instances"
  algorithm            = "ROUND_ROBIN"
  active_monitor_path  = nsxt_policy_lb_http_monitor_profile.gorouter_monitor.path

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}

resource "nsxt_policy_lb_pool" "tcp_router_pool" {
  display_name         = "${var.environment_name}-tcp-router-pool"
  description          = "Pool for TCP Router instances"
  algorithm            = "ROUND_ROBIN"
  active_monitor_path  = nsxt_policy_lb_http_monitor_profile.tcp_router_monitor.path

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}

resource "nsxt_policy_lb_pool" "ssh_pool" {
  display_name         = "${var.environment_name}-ssh-pool"
  description          = "Pool for Diego Brain SSH"
  algorithm            = "ROUND_ROBIN"
  active_monitor_path  = nsxt_policy_lb_tcp_monitor_profile.ssh_monitor.path

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}

# --- Application Profiles ---

resource "nsxt_policy_lb_fast_tcp_application_profile" "tcp_profile" {
  display_name  = "${var.environment_name}-tcp-profile"
  description   = "TCP application profile for TAS"
  close_timeout = 8
  idle_timeout  = 1800

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}

# --- Virtual Servers ---

resource "nsxt_policy_lb_virtual_server" "web_http" {
  display_name               = "${var.environment_name}-web-http-vs"
  description                = "Virtual server for HTTP traffic"
  access_log_enabled         = false
  application_profile_path   = nsxt_policy_lb_fast_tcp_application_profile.tcp_profile.path
  enabled                    = true
  ip_address                 = var.web_lb_vip
  ports                      = ["80"]
  default_pool_member_ports  = ["80"]
  pool_path                  = nsxt_policy_lb_pool.gorouter_pool.path

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}

resource "nsxt_policy_lb_virtual_server" "web_https" {
  display_name               = "${var.environment_name}-web-https-vs"
  description                = "Virtual server for HTTPS traffic"
  access_log_enabled         = false
  application_profile_path   = nsxt_policy_lb_fast_tcp_application_profile.tcp_profile.path
  enabled                    = true
  ip_address                 = var.web_lb_vip
  ports                      = ["443"]
  default_pool_member_ports  = ["443"]
  pool_path                  = nsxt_policy_lb_pool.gorouter_pool.path

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}

resource "nsxt_policy_lb_virtual_server" "ssh" {
  display_name               = "${var.environment_name}-ssh-vs"
  description                = "Virtual server for SSH traffic"
  access_log_enabled         = false
  application_profile_path   = nsxt_policy_lb_fast_tcp_application_profile.tcp_profile.path
  enabled                    = true
  ip_address                 = var.ssh_lb_vip
  ports                      = ["2222"]
  default_pool_member_ports  = ["2222"]
  pool_path                  = nsxt_policy_lb_pool.ssh_pool.path

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}

resource "nsxt_policy_lb_virtual_server" "tcp_router" {
  display_name               = "${var.environment_name}-tcp-router-vs"
  description                = "Virtual server for TCP router traffic"
  access_log_enabled         = false
  application_profile_path   = nsxt_policy_lb_fast_tcp_application_profile.tcp_profile.path
  enabled                    = true
  ip_address                 = var.tcp_lb_vip
  ports                      = ["1024-65535"]
  default_pool_member_ports  = ["1024-65535"]
  pool_path                  = nsxt_policy_lb_pool.tcp_router_pool.path

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}

# --- Load Balancer Service ---

resource "nsxt_policy_lb_service" "tas_lb" {
  display_name      = "${var.environment_name}-lb-service"
  description       = "Load balancer service for TAS"
  connectivity_path = nsxt_policy_tier1_gateway.t1_deployment.path
  size              = "SMALL"
  enabled           = true

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}
