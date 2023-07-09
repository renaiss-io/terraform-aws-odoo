######################################################################################
# SELF SIGNED CERT
######################################################################################
resource "tls_private_key" "ca_key" {
  count = var.route53_hosted_zone != null ? 0 : 1

  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "ca_cert" {
  count = var.route53_hosted_zone != null ? 0 : 1

#   key_algorithm         = "RSA"
  private_key_pem       = tls_private_key.ca_key[0].private_key_pem
  is_ca_certificate     = true
  validity_period_hours = 87659 # Valid for 1 year

  subject {
    common_name  = module.alb.lb_dns_name
    organization = var.name
  }

  allowed_uses = [
    "digital_signature",
    "cert_signing",
    "crl_signing",
  ]
}

resource "tls_private_key" "alb_key" {
  count = var.route53_hosted_zone != null ? 0 : 1

  algorithm = "RSA"
  rsa_bits  = "2048"
}

resource "tls_cert_request" "alb_cert_req" {
  count = var.route53_hosted_zone != null ? 0 : 1

#   key_algorithm   = "RSA"
  private_key_pem = tls_private_key.alb_key[0].private_key_pem

  subject {
    common_name  = module.alb.lb_dns_name
    organization = var.name
  }
}

resource "tls_locally_signed_cert" "alb_locally_signed_cert" {
  count = var.route53_hosted_zone != null ? 0 : 1

  cert_request_pem      = tls_cert_request.alb_cert_req[0].cert_request_pem
#   ca_key_algorithm      = "RSA"
  ca_private_key_pem    = tls_private_key.ca_key[0].private_key_pem
  ca_cert_pem           = tls_self_signed_cert.ca_cert[0].cert_pem
  validity_period_hours = 8760 # Valid for 1 year

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "aws_acm_certificate" "self_signed" {
  count = var.route53_hosted_zone != null ? 0 : 1

  private_key       = tls_private_key.alb_key[0].private_key_pem
  certificate_body  = tls_locally_signed_cert.alb_locally_signed_cert[0].cert_pem
  certificate_chain = tls_self_signed_cert.ca_cert[0].cert_pem
}
