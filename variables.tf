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

variable "deploy_nat" { // TODO: implement logic to use nat in private subnets
  default     = false
  type        = bool
  description = "Deploy NAT for private subnets"
}

######################################################################################
# DB
######################################################################################
variable "db_size" {
  default     = 20
  type        = number
  description = "DB size (in GB)"
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

variable "odoo_custom_modules_paths" {
  default     = []
  type        = list(string)
  description = "Paths containing custom modules to install"
}

variable "odoo_python_libraries_paths" {
  default     = []
  type        = list(string)
  description = "Paths containing python libraries to install"
}

variable "extra_files_filter" {
  default     = [".git"]
  type        = list(string)
  description = "Paths containing python libraries to install"
}
