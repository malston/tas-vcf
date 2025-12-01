# terraform/nsxt/ip_pools.tf

# External IP Pool for container networking (per-org NAT)
resource "nsxt_policy_ip_pool" "external_ip_pool" {
  display_name = "${var.environment_name}-external-ip-pool"
  description  = "External IP pool for TAS container networking"

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}

resource "nsxt_policy_ip_pool_static_subnet" "external_ip_pool_subnet" {
  display_name = "${var.environment_name}-external-ip-pool-subnet"
  pool_path    = nsxt_policy_ip_pool.external_ip_pool.path
  cidr         = "31.31.10.0/24"
  gateway      = "31.31.10.1"

  allocation_range {
    start = var.external_ip_pool_start
    end   = var.external_ip_pool_end
  }
}

# IP Block for container-to-container networking
resource "nsxt_policy_ip_block" "container_ip_block" {
  display_name = "${var.environment_name}-container-ip-block"
  description  = "IP block for TAS container-to-container networking"
  cidr         = var.container_ip_block_cidr

  tag {
    scope = "environment"
    tag   = var.environment_name
  }
}
