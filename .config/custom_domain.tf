module "odoo" {
  source = "git@github.com:renaiss-io/terraform-aws-odoo.git?ref=v0.1.0"

  route53_hosted_zone = "Z01208793QY6JAD0UY432" // public hosted zone with domain to use for odoo
}
