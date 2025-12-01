# terraform/certs/main.tf

# Root CA
resource "tls_private_key" "ca" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "ca" {
  private_key_pem = tls_private_key.ca.private_key_pem

  subject {
    common_name  = "TAS Homelab CA"
    organization = var.organization
  }

  validity_period_hours = var.validity_period_hours
  is_ca_certificate     = true

  allowed_uses = [
    "cert_signing",
    "crl_signing",
  ]
}

# Ops Manager certificate
resource "tls_private_key" "opsman" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "opsman" {
  private_key_pem = tls_private_key.opsman.private_key_pem

  subject {
    common_name  = "opsman.${var.base_domain}"
    organization = var.organization
  }

  dns_names = [
    "opsman.${var.base_domain}",
  ]
}

resource "tls_locally_signed_cert" "opsman" {
  cert_request_pem   = tls_cert_request.opsman.cert_request_pem
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem

  validity_period_hours = var.validity_period_hours

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

# TAS System domain certificate (wildcard)
resource "tls_private_key" "tas_system" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "tas_system" {
  private_key_pem = tls_private_key.tas_system.private_key_pem

  subject {
    common_name  = "*.sys.${var.base_domain}"
    organization = var.organization
  }

  dns_names = [
    "*.sys.${var.base_domain}",
    "*.login.sys.${var.base_domain}",
    "*.uaa.sys.${var.base_domain}",
  ]
}

resource "tls_locally_signed_cert" "tas_system" {
  cert_request_pem   = tls_cert_request.tas_system.cert_request_pem
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem

  validity_period_hours = var.validity_period_hours

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

# TAS Apps domain certificate (wildcard)
resource "tls_private_key" "tas_apps" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "tas_apps" {
  private_key_pem = tls_private_key.tas_apps.private_key_pem

  subject {
    common_name  = "*.apps.${var.base_domain}"
    organization = var.organization
  }

  dns_names = [
    "*.apps.${var.base_domain}",
  ]
}

resource "tls_locally_signed_cert" "tas_apps" {
  cert_request_pem   = tls_cert_request.tas_apps.cert_request_pem
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem

  validity_period_hours = var.validity_period_hours

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

# Write certificates to files
resource "local_file" "ca_cert" {
  content  = tls_self_signed_cert.ca.cert_pem
  filename = "${var.output_path}/ca.crt"
}

resource "local_file" "opsman_cert" {
  content  = tls_locally_signed_cert.opsman.cert_pem
  filename = "${var.output_path}/opsman.crt"
}

resource "local_file" "opsman_key" {
  content         = tls_private_key.opsman.private_key_pem
  filename        = "${var.output_path}/opsman.key"
  file_permission = "0600"
}

resource "local_file" "tas_system_cert" {
  content  = tls_locally_signed_cert.tas_system.cert_pem
  filename = "${var.output_path}/tas-system.crt"
}

resource "local_file" "tas_system_key" {
  content         = tls_private_key.tas_system.private_key_pem
  filename        = "${var.output_path}/tas-system.key"
  file_permission = "0600"
}

resource "local_file" "tas_apps_cert" {
  content  = tls_locally_signed_cert.tas_apps.cert_pem
  filename = "${var.output_path}/tas-apps.crt"
}

resource "local_file" "tas_apps_key" {
  content         = tls_private_key.tas_apps.private_key_pem
  filename        = "${var.output_path}/tas-apps.key"
  file_permission = "0600"
}
