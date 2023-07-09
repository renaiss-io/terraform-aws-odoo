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
  description = "A to use for all resources"
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
  description = "DB size"
}

variable "db_instance_type" {
  default     = "db.t4g.small"
  type        = string
  description = "Instance type for DB instances"
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

variable "acm_cert" {
  default     = null
  type        = string
  description = "ACM cert to assign to the load balancer, util when managing domain externally or to reuse a valid cert for a domain"
}
