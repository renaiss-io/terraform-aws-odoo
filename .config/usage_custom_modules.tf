module "odoo_complete" {
  source = "git@github.com:renaiss-io/terraform-aws-odoo.git"

  # Custom modules files
  # If this var is provided, the files are stored in s3
  # and synced to EFS with DataSync
  odoo_custom_modules_paths = ["./custom_modules"]

  # Custom python packages
  # If this var is provided, a custom docker image is
  # created and maintained in ECR
  python_requirements_file = "./requirements.txt"
}