provider "aws" { region = "us-east-2" }

provider "aws" {
  region = "us-east-1"
  alias  = "use1"
}

# When deploying outside us-east-1 and using a custom domain
# an ACM cert is required in us-east-1 for the cdn.
# The cert must be created externally and sent to the module
# in the var.acm_cert_use1 variable
module "odoo_simple" {
  source = "../.."

  route53_hosted_zone = "Z01208793QY6JAD0UY432"
  odoo_domain         = "odoo.example.com"
  odoo_root_email     = "user@example.com"
  acm_cert_use1       = module.acm.acm_certificate_arn
}

# This represents the ACM cert in us-east-1 created outside
# the odoo module
module "acm" {
  source  = "terraform-aws-modules/acm/aws"
  version = "~> 4.0"

  provider = { aws = aws.use1 }

  domain_name               = "example.com"
  zone_id                   = "Z01208793QY6JAD0UY432"
  wait_for_validation       = true
  subject_alternative_names = ["*.example.com"]
}
