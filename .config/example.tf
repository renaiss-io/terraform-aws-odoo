provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      App    = "odoo"
      Module = "https://github.com/renaiss-io/terraform-aws-odoo"
    }
  }
}

# Simple usage
module "odoo" {
  source = "git@github.com:renaiss-io/terraform-aws-odoo.git?ref=v0.1.0"
}

# With custom domain
module "odoo" {
  source = "git@github.com:renaiss-io/terraform-aws-odoo.git?ref=v0.1.0"

  route53_hosted_zone = "Z01208793QY6JAD0UY432" // public hosted zone with domain to use for odoo
}


# With custom domain, overriding the root domain
module "odoo" {
  source = "git@github.com:renaiss-io/terraform-aws-odoo.git?ref=v0.1.0"

  route53_hosted_zone = "Z01208793QY6JAD0UY432"
  odoo_domain = "odoo.example.com" // must be a subdomain of the root domain
}