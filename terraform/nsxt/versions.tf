# terraform/nsxt/versions.tf
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    nsxt = {
      source  = "vmware/nsxt"
      version = "~> 3.4"
    }
  }
}
