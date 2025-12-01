# terraform/vsphere/resource_pools.tf

# Resource pool for infrastructure (Ops Manager, BOSH Director)
resource "vsphere_resource_pool" "infrastructure" {
  name                    = "${var.environment_name}-infrastructure"
  parent_resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
}

# Resource pool for AZ1 workloads
resource "vsphere_resource_pool" "az1" {
  name                    = "${var.environment_name}-az1"
  parent_resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
}

# Resource pool for AZ2 workloads
resource "vsphere_resource_pool" "az2" {
  name                    = "${var.environment_name}-az2"
  parent_resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
}
