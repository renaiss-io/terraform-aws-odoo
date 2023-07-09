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
variable "db_instance_type" {
  default     = "db.t4g.small"
  type        = string
  description = "Instance type for DB instances"
}

