# ABOUTME: NSX-T provider configuration for VPC management
# ABOUTME: Authenticates to NSX Manager to manage VPC resources
provider "nsxt" {
  host                 = var.nsxt_host
  username             = var.nsxt_username
  password             = var.nsxt_password
  allow_unverified_ssl = var.allow_unverified_ssl
}
