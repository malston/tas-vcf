# terraform/nsxt/provider.tf
provider "nsxt" {
  host                 = var.nsxt_host
  username             = var.nsxt_username
  password             = var.nsxt_password
  allow_unverified_ssl = var.allow_unverified_ssl
}
