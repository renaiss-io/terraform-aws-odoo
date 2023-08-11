locals {
  # Services ports
  db_port   = 5432
  odoo_port = 8069

  # Container paths
  filestore_path        = "/bitnami/odoo"
  addons_dir            = "/bitnami/odoo/addons"
  python_extra_packages = "/bitnami/odoo/python_extra_packages"
  tmp_path              = "/opt/bitnami/odoo/tmp"

  # S3
  requirements_file_object = "requirements.txt"

  # ECR
  custom_image = var.python_requirements_file != null

  # Custom modules
  modules_files_len = length(var.odoo_custom_modules_paths) != 0
  python_files_len  = length(var.odoo_python_dependencies_paths) != 0

  # Events
  cron_expression = "cron(0 0 * * ? *)"

  # Cached paths
  cache_path_patterns = [
    "*/static/*",
    "/web/assets/*",
    "/web/image/*",
    "/web/css/*",
    "/web/js/*",
    "/web/content/*",
    "/website/image/*",
  ]

  # CDN
  region_use1     = data.aws_region.current.name == "us-east-1"
  auth_header_alb = "CloudFront-Access"

  # Domain variables
  custom_domain            = var.route53_hosted_zone != null
  cloudfront_custom_domain = local.custom_domain ? var.odoo_domain != null ? var.odoo_domain : data.aws_route53_zone.domain[0].name : null
  alb_custom_domain        = local.custom_domain ? var.odoo_domain != null ? "alb.${var.odoo_domain}" : "alb.${data.aws_route53_zone.domain[0].name}" : null
}
