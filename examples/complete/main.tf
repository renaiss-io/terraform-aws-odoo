provider "aws" { region = "us-east-1" }

module "odoo_complete" {
  source = "../.."

  # general
  name = "odoo-complete"
  tags = { "Environment" : "complete" }

  # domain
  route53_hosted_zone = "Z01208793QY6JAD0UY432"
  odoo_domain         = "odoo.example.com"

  # network
  vpc_cidr = "10.1.0.0/16"

  # db
  db_size          = 30
  db_max_size      = 300
  db_root_username = "db_admin"
  db_instance_type = "db.t4g.large"

  # ecs
  ecs_instance_type      = "t3.large"
  ecs_task_memory        = 1024
  ecs_container_insights = true

  # odoo
  odoo_version      = "16"
  odoo_docker_image = "bitnami/odoo"
  odoo_root_email   = "user@example.com"
  no_database_list  = true
  load_language     = ["es_AR"]
  init_modules      = ["mail", "notes"]

  # custom modules
  python_requirements_file  = "./requirements.txt"
  odoo_custom_modules_paths = ["./custom_modules"]

  # datasync
  datasync_preserve_deleted_files = false
}
