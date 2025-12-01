# terraform/vsphere/data.tf

data "vsphere_datacenter" "dc" {
  name = var.datacenter_name
}

data "vsphere_compute_cluster" "cluster" {
  name          = var.cluster_name
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_datastore" "datastore" {
  name          = var.datastore_name
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_host" "infrastructure_host" {
  name          = var.infrastructure_host
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_host" "az1_host" {
  name          = var.az1_host
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_host" "az2_host" {
  name          = var.az2_host
  datacenter_id = data.vsphere_datacenter.dc.id
}
