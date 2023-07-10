provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      App    = "odoo"
      Module = "https://github.com/renaiss-io/terraform-aws-odoo"
    }
  }
}


module "odoo" {
  source = "git@github.com:renaiss-io/terraform-aws-odoo.git?ref=v0.1.0"
}
