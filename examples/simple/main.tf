provider "aws" { region = "us-east-1" }

module "odoo_simple" {
  source = "../.."

  odoo_root_email = "user@example.com"
}
