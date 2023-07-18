locals {
  db_port   = 5432
  odoo_port = 8069

  filestore_path = "/var/lib/odoo/filestore"
  config_path    = "/etc/odoo"

  # If not external cert or domain, create locally signed cert
  create_locally_signed_cert = var.acm_cert == null && var.route53_hosted_zone == null
  # If not external cert and domain provided, create and validate acm cert
  create_acm_cert = var.acm_cert == null && var.route53_hosted_zone != null

  # Choose the cert from any of the 3 options:
  # Self signed, created or externally provided
  https_listener_cert = (
    local.create_locally_signed_cert ?
    aws_acm_certificate.self_signed[0].arn
    :
    local.create_acm_cert ?
    module.acm[0].acm_certificate_arn
    :
    var.acm_cert
  )
}
