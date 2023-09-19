######################################################################################
# GENERAL
######################################################################################
variable "tags" {
  default     = {}
  type        = map(string)
  description = "A mapping of tags to assign to resources"
}

variable "name" {
  default     = "odoo"
  type        = string
  description = "A name to use in all resources"
}

######################################################################################
# NETWORK
######################################################################################
variable "vpc_cidr" {
  default     = "10.0.0.0/16"
  type        = string
  description = "IP range to assign to VPC"
}

######################################################################################
# DB
######################################################################################
variable "db_size" {
  default     = 20
  type        = number
  description = "DB size (in GB)"
}

variable "db_max_size" {
  default     = 100
  type        = number
  description = "Max size of DB (var.db_size will be allocated and autoscale will be enabled)"
}

variable "db_root_username" {
  default     = "odoo"
  type        = string
  description = "DB root username"
}

variable "db_instance_type" {
  default     = "db.t4g.micro"
  type        = string
  description = "Instance type for DB instances"
}

######################################################################################
# ECS
######################################################################################
variable "ecs_instance_type" {
  default     = "t3.micro"
  type        = string
  description = "Instance type for ECS instances"
}

variable "ecs_task_memory" {
  default     = 400
  type        = number
  description = "Memory to allocate for the task (in GB)"
}

variable "ecs_container_insights" {
  default     = false
  type        = bool
  description = "Enable container ingsights in ECS (not inside free tier)"
}

######################################################################################
# DOMAIN
######################################################################################
variable "route53_hosted_zone" {
  default     = null
  type        = string
  description = "If provided, the hosted zone is used as domain for odoo"
}

variable "odoo_domain" {
  default     = null
  type        = string
  description = "If route53 is set, use this var to use a subdomain instead of the root domain. Must be subdomain of the provided domain"
}

######################################################################################
# CDN
######################################################################################
variable "acm_cert_use1" {
  default     = null
  type        = string
  description = "If using custom domain and deploying outside us-east-1, a cert in us-east-1 for the domain is required"
}

variable "cdn_price_class" {
  default     = "PriceClass_100"
  type        = string
  description = "Price class for CDN"
}

######################################################################################
# ODOO
######################################################################################
variable "odoo_version" {
  default     = "16"
  type        = string
  description = "Version of odoo docker image to use"
}

variable "odoo_docker_image" {
  default     = "bitnami/odoo"
  type        = string
  description = "Odoo docker image to use"
}

variable "odoo_root_email" {
  type        = string
  description = "Root email to use, must be validated in SES"
}

variable "odoo_db_name" {
  default     = "odoo"
  type        = string
  description = "Main odoo DB name"
}

variable "no_database_list" {
  default     = true
  type        = bool
  description = "Enable/Disable exposing DB management capabilities in the login page"
}

variable "load_language" {
  default     = []
  type        = list(string)
  description = "Allow automatic installation of a language. List of languages available at https://github.com/odoo/odoo/blob/16.0/odoo/tools/translate.py"
}

variable "init_modules" {
  default     = []
  type        = list(string)
  description = "Initialize some modules upon deployment success"
}

######################################################################################
# CUSTOM MODULES
######################################################################################
variable "odoo_custom_modules_paths" {
  default     = []
  type        = list(string)
  description = "Paths containing custom modules to install"
}

variable "odoo_python_dependencies_paths" {
  default     = []
  type        = list(string)
  description = "Paths containing python dependencies"
}

variable "extra_files_filter" {
  default     = [".git"]
  type        = list(string)
  description = "Paths to ignore when processing modules and python dependencies"
}

variable "python_requirements_file" {
  default     = null
  type        = string
  description = "Path to a requirements.txt file with extra libraries to install in python environment"
}

######################################################################################
# DATASYNC
######################################################################################
variable "datasync_preserve_deleted_files" {
  default     = false
  type        = bool
  description = "Datasync preserves old files not present in S3"
}
