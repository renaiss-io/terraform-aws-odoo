locals {
  db_port   = 5432
  odoo_port = 8069

  tags = merge(var.tags, {
    App    = "odoo"
    Module = "https://github.com/renaiss-io/terraform-aws-odoo"
  })
}
