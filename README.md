<!-- BEGIN_TF_DOCS -->
# Odoo in AWS

## Description

This module deploys [odoo](https://odoo.com) in AWS using RDS for the postgres database and ECS to run the containerized version of odoo server.

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement_terraform) | >= 1.5.2 |
| <a name="requirement_aws"></a> [aws](#requirement_aws) | >= 5.00 |
| <a name="requirement_random"></a> [random](#requirement_random) | >= 3.1.0 |
| <a name="requirement_tls"></a> [tls](#requirement_tls) | >= 4.0.4 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_acm"></a> [acm](#module_acm) | terraform-aws-modules/acm/aws | ~> 4.0 |
| <a name="module_alb"></a> [alb](#module_alb) | terraform-aws-modules/alb/aws | ~> 8.0 |
| <a name="module_alb_sg"></a> [alb_sg](#module_alb_sg) | terraform-aws-modules/security-group/aws | ~> 5.0 |
| <a name="module_autoscaling"></a> [autoscaling](#module_autoscaling) | terraform-aws-modules/autoscaling/aws | ~> 6.5 |
| <a name="module_autoscaling_sg"></a> [autoscaling_sg](#module_autoscaling_sg) | terraform-aws-modules/security-group/aws | ~> 5.0 |
| <a name="module_db"></a> [db](#module_db) | terraform-aws-modules/rds/aws | ~> 6.0 |
| <a name="module_db_security_group"></a> [db_security_group](#module_db_security_group) | terraform-aws-modules/security-group/aws | ~> 5.0 |
| <a name="module_ecs_cluster"></a> [ecs_cluster](#module_ecs_cluster) | terraform-aws-modules/ecs/aws | ~> 5.2 |
| <a name="module_ecs_service"></a> [ecs_service](#module_ecs_service) | terraform-aws-modules/ecs/aws//modules/service | ~> 5.2 |
| <a name="module_efs"></a> [efs](#module_efs) | terraform-aws-modules/efs/aws | ~> 1.2 |
| <a name="module_vpc"></a> [vpc](#module_vpc) | terraform-aws-modules/vpc/aws | ~> 5.0 |

## Usage

```hcl
provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      App    = "odoo"
      Module = "https://github.com/renaiss-io/terraform-aws-odoo"
    }
  }
}

# Simple usage
module "odoo" {
  source = "git@github.com:renaiss-io/terraform-aws-odoo.git?ref=v0.1.0"
}

# With custom domain
module "odoo" {
  source = "git@github.com:renaiss-io/terraform-aws-odoo.git?ref=v0.1.0"

  route53_hosted_zone = "Z01208793QY6JAD0UY432" // public hosted zone with domain to use for odoo
}


# With custom domain, overriding the root domain
module "odoo" {
  source = "git@github.com:renaiss-io/terraform-aws-odoo.git?ref=v0.1.0"

  route53_hosted_zone = "Z01208793QY6JAD0UY432"  // hosted zone for example.com
  odoo_domain         = "odoo.example.com"       // must be a subdomain of the root domain
}
```


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_acm_cert"></a> [acm_cert](#input_acm_cert) | ACM cert to assign to the load balancer, util when managing domain externally or to reuse a valid cert for a domain | `string` | `null` | no |
| <a name="input_db_instance_type"></a> [db_instance_type](#input_db_instance_type) | Instance type for DB instances | `string` | `"db.t4g.small"` | no |
| <a name="input_db_size"></a> [db_size](#input_db_size) | DB size (in GB) | `number` | `20` | no |
| <a name="input_deploy_nat"></a> [deploy_nat](#input_deploy_nat) | Deploy NAT for private subnets | `bool` | `false` | no |
| <a name="input_name"></a> [name](#input_name) | A name to use in all resources | `string` | `"odoo"` | no |
| <a name="input_odoo_domain"></a> [odoo_domain](#input_odoo_domain) | If route53 is set, use this var to use a subdomain instead of the root domain. Must be subdomain of the provided domain | `string` | `null` | no |
| <a name="input_odoo_version"></a> [odoo_version](#input_odoo_version) | Version of odoo docker image to use | `string` | `"16"` | no |
| <a name="input_route53_hosted_zone"></a> [route53_hosted_zone](#input_route53_hosted_zone) | If provided, the hosted zone is used as domain for odoo | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input_tags) | A mapping of tags to assign to resources | `map(string)` | `{}` | no |
| <a name="input_vpc_cidr"></a> [vpc_cidr](#input_vpc_cidr) | IP range to assign to VPC | `string` | `"10.0.0.0/16"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_default_dns"></a> [default_dns](#output_default_dns) | DNS of the load balancer to access odoo |
<!-- END_TF_DOCS -->