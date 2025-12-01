# terraform/vsphere/provider.tf
provider "vsphere" {
  vsphere_server       = var.vcenter_host
  user                 = var.vcenter_username
  password             = var.vcenter_password
  allow_unverified_ssl = var.allow_unverified_ssl
}
