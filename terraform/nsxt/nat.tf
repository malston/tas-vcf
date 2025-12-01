# terraform/nsxt/nat.tf

# SNAT rule for all TAS VMs (egress)
resource "nsxt_policy_nat_rule" "snat_all" {
  display_name         = "${var.environment_name}-SNAT-All"
  description          = "SNAT for all TAS VM egress traffic"
  action               = "SNAT"
  gateway_path         = data.nsxt_policy_tier0_gateway.t0_gateway.path
  source_networks      = ["10.0.0.0/16"]
  translated_networks  = [var.nat_gateway_ip]
  logging              = false
  firewall_match       = "MATCH_INTERNAL_ADDRESS"

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}

# SNAT rule for Ops Manager (specific source IP)
resource "nsxt_policy_nat_rule" "snat_ops_manager" {
  display_name         = "${var.environment_name}-SNAT-OpsManager"
  description          = "SNAT for Ops Manager egress traffic"
  action               = "SNAT"
  gateway_path         = data.nsxt_policy_tier0_gateway.t0_gateway.path
  source_networks      = [var.ops_manager_internal_ip]
  translated_networks  = [var.ops_manager_external_ip]
  logging              = false
  firewall_match       = "MATCH_INTERNAL_ADDRESS"
  sequence_number      = 10

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}

# DNAT rule for Ops Manager (inbound access)
resource "nsxt_policy_nat_rule" "dnat_ops_manager" {
  display_name         = "${var.environment_name}-DNAT-OpsManager"
  description          = "DNAT for Ops Manager inbound traffic"
  action               = "DNAT"
  gateway_path         = data.nsxt_policy_tier0_gateway.t0_gateway.path
  destination_networks = [var.ops_manager_external_ip]
  translated_networks  = [var.ops_manager_internal_ip]
  logging              = false
  firewall_match       = "MATCH_EXTERNAL_ADDRESS"

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}
