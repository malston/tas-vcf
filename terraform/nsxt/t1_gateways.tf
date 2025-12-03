# terraform/nsxt/t1_gateways.tf

# T1 Gateway for Infrastructure (Ops Manager, BOSH Director)
resource "nsxt_policy_tier1_gateway" "t1_infrastructure" {
  display_name              = "${var.environment_name}-T1-Infrastructure"
  description               = "T1 Gateway for TAS Infrastructure components"
  edge_cluster_path         = data.nsxt_policy_edge_cluster.edge_cluster.path
  failover_mode             = "PREEMPTIVE"
  default_rule_logging      = false
  enable_firewall           = false
  enable_standby_relocation = false
  tier0_path                = data.nsxt_policy_tier0_gateway.t0_gateway.path
  route_advertisement_types = ["TIER1_CONNECTED", "TIER1_NAT", "TIER1_LB_VIP", "TIER1_LB_SNAT"]

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}

# T1 Gateway for Deployment (Diego cells, Routers, UAA, etc.)
resource "nsxt_policy_tier1_gateway" "t1_deployment" {
  display_name              = "${var.environment_name}-T1-Deployment"
  description               = "T1 Gateway for TAS Deployment components"
  edge_cluster_path         = data.nsxt_policy_edge_cluster.edge_cluster.path
  failover_mode             = "NON_PREEMPTIVE"
  default_rule_logging      = false
  enable_firewall           = false
  enable_standby_relocation = false
  tier0_path                = data.nsxt_policy_tier0_gateway.t0_gateway.path
  route_advertisement_types = ["TIER1_CONNECTED", "TIER1_NAT", "TIER1_LB_VIP", "TIER1_LB_SNAT"]

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}

# T1 Gateway for Services (on-demand service instances)
resource "nsxt_policy_tier1_gateway" "t1_services" {
  display_name              = "${var.environment_name}-T1-Services"
  description               = "T1 Gateway for TAS Services"
  edge_cluster_path         = data.nsxt_policy_edge_cluster.edge_cluster.path
  failover_mode             = "NON_PREEMPTIVE"
  default_rule_logging      = false
  enable_firewall           = false
  enable_standby_relocation = false
  tier0_path                = data.nsxt_policy_tier0_gateway.t0_gateway.path
  route_advertisement_types = ["TIER1_CONNECTED", "TIER1_NAT"]

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}
