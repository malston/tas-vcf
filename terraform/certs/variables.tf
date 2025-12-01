# terraform/certs/variables.tf
variable "base_domain" {
  description = "Base domain for TAS"
  type        = string
  default     = "tas.vcf.lab"
}

variable "organization" {
  description = "Organization name for certificates"
  type        = string
  default     = "Homelab"
}

variable "validity_period_hours" {
  description = "Certificate validity in hours (default 1 year)"
  type        = number
  default     = 8760
}

variable "output_path" {
  description = "Path to write certificate files"
  type        = string
  default     = "./generated"
}
