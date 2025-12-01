# terraform/nsxt/segments.tf

# Infrastructure segment (Ops Manager, BOSH Director)
resource "nsxt_policy_segment" "infrastructure" {
  display_name        = "${var.environment_name}-Infrastructure"
  description         = "Segment for TAS Infrastructure components"
  connectivity_path   = nsxt_policy_tier1_gateway.t1_infrastructure.path
  transport_zone_path = data.nsxt_policy_transport_zone.overlay_tz.path

  subnet {
    cidr        = var.infrastructure_cidr
    dhcp_ranges = []
  }

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}

# Deployment segment (Diego cells, Routers, UAA, etc.)
resource "nsxt_policy_segment" "deployment" {
  display_name        = "${var.environment_name}-Deployment"
  description         = "Segment for TAS Deployment components"
  connectivity_path   = nsxt_policy_tier1_gateway.t1_deployment.path
  transport_zone_path = data.nsxt_policy_transport_zone.overlay_tz.path

  subnet {
    cidr        = var.deployment_cidr
    dhcp_ranges = []
  }

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}

# Services segment (on-demand service instances)
resource "nsxt_policy_segment" "services" {
  display_name        = "${var.environment_name}-Services"
  description         = "Segment for TAS Services"
  connectivity_path   = nsxt_policy_tier1_gateway.t1_services.path
  transport_zone_path = data.nsxt_policy_transport_zone.overlay_tz.path

  subnet {
    cidr        = var.services_cidr
    dhcp_ranges = []
  }

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}
