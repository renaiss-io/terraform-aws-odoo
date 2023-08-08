# Simple usage
module "odoo_simple" {
  source = "git@github.com:renaiss-io/terraform-aws-odoo.git"

  name = "odoo"
  tags = { "Environment" : "prod" }
}

# You can use a domain hosted in route 53 for odoo
# 1. Provide the hosted zone id and the module will create the required records
# 2. (optional) use a subdomain instead of the root domain of route 53
module "odoo_custom_domain" {
  source = "git@github.com:renaiss-io/terraform-aws-odoo.git"

  route53_hosted_zone = "Z01208793QY6JAD0UY432"
  odoo_domain         = "odoo.example.com"
}
