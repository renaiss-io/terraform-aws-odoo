<!-- BEGIN_TF_DOCS -->
# Odoo in AWS

This module deploys [odoo](https://odoo.com) in AWS using:

- ECS backed with EC2 to run the containerized version of odoo server
- RDS for the postgres database
- EFS as a filesystem for odoo's filestore
- SES as a mail gateway
- CloudFront as a CDN with cache capabilities
- AWS Secrets to store credentials

## Architecture reference

![Architecture diagram](images/Diagram.svg)

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement_terraform) | >= 1.5.2 |
| <a name="requirement_aws"></a> [aws](#requirement_aws) | >= 5.00 |
| <a name="requirement_random"></a> [random](#requirement_random) | >= 3.1.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_acm"></a> [acm](#module_acm) | terraform-aws-modules/acm/aws | ~> 4.0 |
| <a name="module_alb"></a> [alb](#module_alb) | terraform-aws-modules/alb/aws | ~> 8.0 |
| <a name="module_autoscaling"></a> [autoscaling](#module_autoscaling) | terraform-aws-modules/autoscaling/aws | ~> 6.5 |
| <a name="module_autoscaling_sg"></a> [autoscaling_sg](#module_autoscaling_sg) | terraform-aws-modules/security-group/aws | ~> 5.0 |
| <a name="module_cdn"></a> [cdn](#module_cdn) | terraform-aws-modules/cloudfront/aws | ~> 3.2 |
| <a name="module_db"></a> [db](#module_db) | terraform-aws-modules/rds/aws | ~> 6.0 |
| <a name="module_db_security_group"></a> [db_security_group](#module_db_security_group) | terraform-aws-modules/security-group/aws | ~> 5.0 |
| <a name="module_ecs_cluster"></a> [ecs_cluster](#module_ecs_cluster) | terraform-aws-modules/ecs/aws | ~> 5.2 |
| <a name="module_ecs_service"></a> [ecs_service](#module_ecs_service) | terraform-aws-modules/ecs/aws//modules/service | ~> 5.2 |
| <a name="module_efs"></a> [efs](#module_efs) | terraform-aws-modules/efs/aws | ~> 1.2 |
| <a name="module_s3_bucket"></a> [s3_bucket](#module_s3_bucket) | terraform-aws-modules/s3-bucket/aws | ~> 3.14 |
| <a name="module_ses_user"></a> [ses_user](#module_ses_user) | terraform-aws-modules/iam/aws//modules/iam-user | ~> 5.27 |
| <a name="module_vpc"></a> [vpc](#module_vpc) | terraform-aws-modules/vpc/aws | ~> 5.0 |

## Usage

```hcl
provider "aws" { region = "us-east-1" }

# Simple usage
module "odoo_simple" {
  source = "git@github.com:renaiss-io/terraform-aws-odoo.git"
}

# You can use a domain hosted in route 53 for odoo
# 1. Provide the hosted zone id and the module will create the required records
# 2. (optional) use a subdomain instead of the root domain of route 53
module "odoo_custom_domain" {
  source = "git@github.com:renaiss-io/terraform-aws-odoo.git"

  route53_hosted_zone = "Z01208793QY6JAD0UY432"
  odoo_domain         = "odoo.example.com"
}
```

> Important! For simplicity, the examples do not point to a
> specific version of the module. For a production deployment,
> it is suggested that you point to a specific version tag like:
>
> **source = "git<span>@</span>github.com:renaiss-io/terraform-aws-odoo.git?ref=v1.0.0"**

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_odoo_root_email"></a> [odoo_root_email](#input_odoo_root_email) | Root email to use, must be validated in SES | `string` | n/a | yes |
| <a name="input_acm_cert_use1"></a> [acm_cert_use1](#input_acm_cert_use1) | If using custom domain and deploying outside us-east-1, a cert in us-east-1 for the domain is required | `string` | `null` | no |
| <a name="input_cdn_price_class"></a> [cdn_price_class](#input_cdn_price_class) | Price class for CDN | `string` | `"PriceClass_100"` | no |
| <a name="input_db_instance_type"></a> [db_instance_type](#input_db_instance_type) | Instance type for DB instances | `string` | `"db.t4g.small"` | no |
| <a name="input_db_size"></a> [db_size](#input_db_size) | DB size (in GB) | `number` | `20` | no |
| <a name="input_deploy_nat"></a> [deploy_nat](#input_deploy_nat) | Deploy NAT for private subnets | `bool` | `false` | no |
| <a name="input_ecs_instance_type"></a> [ecs_instance_type](#input_ecs_instance_type) | Instance type for ECS instances | `string` | `"t3.micro"` | no |
| <a name="input_ecs_task_memory"></a> [ecs_task_memory](#input_ecs_task_memory) | Memory to allocate for the task (in GB) | `number` | `400` | no |
| <a name="input_extra_files_filter"></a> [extra_files_filter](#input_extra_files_filter) | Paths containing python libraries to install | `list(string)` | <pre>[<br>  ".git"<br>]</pre> | no |
| <a name="input_name"></a> [name](#input_name) | A name to use in all resources | `string` | `"odoo"` | no |
| <a name="input_odoo_custom_modules_paths"></a> [odoo_custom_modules_paths](#input_odoo_custom_modules_paths) | Paths containing custom modules to install | `list(string)` | `[]` | no |
| <a name="input_odoo_db_name"></a> [odoo_db_name](#input_odoo_db_name) | Main odoo DB name | `string` | `"odoo"` | no |
| <a name="input_odoo_docker_image"></a> [odoo_docker_image](#input_odoo_docker_image) | Odoo docker image to use | `string` | `"bitnami/odoo"` | no |
| <a name="input_odoo_domain"></a> [odoo_domain](#input_odoo_domain) | If route53 is set, use this var to use a subdomain instead of the root domain. Must be subdomain of the provided domain | `string` | `null` | no |
| <a name="input_odoo_python_libraries_paths"></a> [odoo_python_libraries_paths](#input_odoo_python_libraries_paths) | Paths containing python libraries to install | `list(string)` | `[]` | no |
| <a name="input_odoo_version"></a> [odoo_version](#input_odoo_version) | Version of odoo docker image to use | `string` | `"16"` | no |
| <a name="input_route53_hosted_zone"></a> [route53_hosted_zone](#input_route53_hosted_zone) | If provided, the hosted zone is used as domain for odoo | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input_tags) | A mapping of tags to assign to resources | `map(string)` | `{}` | no |
| <a name="input_vpc_cidr"></a> [vpc_cidr](#input_vpc_cidr) | IP range to assign to VPC | `string` | `"10.0.0.0/16"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_dns"></a> [dns](#output_dns) | DNS to access odoo |
<!-- END_TF_DOCS -->