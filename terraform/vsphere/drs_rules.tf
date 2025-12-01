# terraform/vsphere/drs_rules.tf

# DRS rule to prefer infrastructure VMs on esx01
resource "vsphere_compute_cluster_vm_host_rule" "infrastructure_affinity" {
  name                     = "${var.environment_name}-infrastructure-affinity"
  compute_cluster_id       = data.vsphere_compute_cluster.cluster.id
  vm_group_name            = vsphere_compute_cluster_vm_group.infrastructure.name
  affinity_host_group_name = vsphere_compute_cluster_host_group.infrastructure_hosts.name
  mandatory                = false # Soft rule - prefer but don't require
}

resource "vsphere_compute_cluster_vm_group" "infrastructure" {
  name               = "${var.environment_name}-infrastructure-vms"
  compute_cluster_id = data.vsphere_compute_cluster.cluster.id
  # VMs will be added dynamically by BOSH
}

resource "vsphere_compute_cluster_host_group" "infrastructure_hosts" {
  name               = "${var.environment_name}-infrastructure-hosts"
  compute_cluster_id = data.vsphere_compute_cluster.cluster.id
  host_system_ids    = [data.vsphere_host.infrastructure_host.id]
}

# DRS rule to prefer AZ1 VMs on esx02
resource "vsphere_compute_cluster_vm_host_rule" "az1_affinity" {
  name                     = "${var.environment_name}-az1-affinity"
  compute_cluster_id       = data.vsphere_compute_cluster.cluster.id
  vm_group_name            = vsphere_compute_cluster_vm_group.az1.name
  affinity_host_group_name = vsphere_compute_cluster_host_group.az1_hosts.name
  mandatory                = false
}

resource "vsphere_compute_cluster_vm_group" "az1" {
  name               = "${var.environment_name}-az1-vms"
  compute_cluster_id = data.vsphere_compute_cluster.cluster.id
}

resource "vsphere_compute_cluster_host_group" "az1_hosts" {
  name               = "${var.environment_name}-az1-hosts"
  compute_cluster_id = data.vsphere_compute_cluster.cluster.id
  host_system_ids    = [data.vsphere_host.az1_host.id]
}

# DRS rule to prefer AZ2 VMs on esx03
resource "vsphere_compute_cluster_vm_host_rule" "az2_affinity" {
  name                     = "${var.environment_name}-az2-affinity"
  compute_cluster_id       = data.vsphere_compute_cluster.cluster.id
  vm_group_name            = vsphere_compute_cluster_vm_group.az2.name
  affinity_host_group_name = vsphere_compute_cluster_host_group.az2_hosts.name
  mandatory                = false
}

resource "vsphere_compute_cluster_vm_group" "az2" {
  name               = "${var.environment_name}-az2-vms"
  compute_cluster_id = data.vsphere_compute_cluster.cluster.id
}

resource "vsphere_compute_cluster_host_group" "az2_hosts" {
  name               = "${var.environment_name}-az2-hosts"
  compute_cluster_id = data.vsphere_compute_cluster.cluster.id
  host_system_ids    = [data.vsphere_host.az2_host.id]
}
