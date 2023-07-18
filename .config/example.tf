provider "aws" {
  region = "us-east-1"
}

# Simple usage
module "odoo_simple" {
  source = "git@github.com:renaiss-io/terraform-aws-odoo.git"
}

# You can use a domain hosted in route 53 for odoo
# 1. Provide the hosted zone id and the module will create the required records
# 2. (optional) use a subdomain instead of the root domain of route 53
module "odoo_custom_domain" {
  source = "git@github.com:renaiss-io/terraform-aws-odoo.git"

  route53_hosted_zone = "Z01208793QY6JAD0UY432"
  odoo_domain         = "odoo.example.com"
}


# If you manage your domain externally you can:
# 1. Create a record in your DNS server: a CNAME with destination to the output 'dns'
# 2. Manually create and verify an ACM cert for the used domain and provide it to the module
module "odoo_external_domain" {
  source = "git@github.com:renaiss-io/terraform-aws-odoo.git"

  acm_cert = "arn:aws:acm......2f4-4579-4493-8615-609cf64daf6d"
}