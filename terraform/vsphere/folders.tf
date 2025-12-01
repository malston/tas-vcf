# terraform/vsphere/folders.tf

# Parent folder for all TAS resources
resource "vsphere_folder" "tas" {
  path          = var.environment_name
  type          = "vm"
  datacenter_id = data.vsphere_datacenter.dc.id
}

# Folder for TAS VMs
resource "vsphere_folder" "vms" {
  path          = "${vsphere_folder.tas.path}/vms"
  type          = "vm"
  datacenter_id = data.vsphere_datacenter.dc.id
}

# Folder for BOSH stemcell templates
resource "vsphere_folder" "templates" {
  path          = "${vsphere_folder.tas.path}/templates"
  type          = "vm"
  datacenter_id = data.vsphere_datacenter.dc.id
}
