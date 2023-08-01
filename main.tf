######################################################################################
# VPC
#
# Official terraform module is used for the basic network layer. A VPC with public,
# private and database networks created in the main 2 availability zones is created.
#
# By default (to keep all resources inside the free tier), no NAT gateways are used
# therefore using public subnets for ECS nodes (for internet access, security managed
# at security group level). DB subnets have no internet access.
#
######################################################################################
data "aws_availability_zones" "available" {}

locals { azs = slice(data.aws_availability_zones.available.names, 0, 2) }

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = var.name
  cidr = var.vpc_cidr
  tags = var.tags

  azs              = local.azs
  public_subnets   = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k)]
  private_subnets  = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 2)]
  database_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 4)]

  create_database_subnet_group      = true
  create_database_nat_gateway_route = false
  enable_nat_gateway                = false

  map_public_ip_on_launch = true
}


######################################################################################
# DB
#
# An RDS database based in Postgres engine (v14) is used as Odoo requires this engine:
# https://www.odoo.com/documentation/16.0/administration/install/install.html#postgresql
#
# AWS allows the master password to be fully managed and rotated. The secret is used
# to set the master password as an environment variable in the Odoo ECS task.
#
# The security group of the DB only allows traffic in the DB port from the EC2
# security group used by the ECS nodes.
#
######################################################################################
module "db" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 6.1"

  identifier = var.name
  db_name    = var.odoo_db_name
  username   = var.db_root_username
  tags       = var.tags

  instance_use_identifier_prefix = false
  create_db_option_group         = false
  create_db_parameter_group      = false

  engine         = "postgres"
  engine_version = "14"

  instance_class        = var.db_instance_type
  allocated_storage     = var.db_size
  max_allocated_storage = var.db_max_size

  port                   = local.db_port
  db_subnet_group_name   = module.vpc.database_subnet_group
  vpc_security_group_ids = [module.db_security_group.security_group_id]

  skip_final_snapshot     = true
  backup_window           = "03:00-06:00"
  backup_retention_period = 1
  copy_tags_to_snapshot   = true
}

module "db_security_group" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name            = "${var.name}-db"
  use_name_prefix = false
  description     = "DB security group"
  vpc_id          = module.vpc.vpc_id
  tags            = var.tags

  ingress_with_source_security_group_id = [{
    from_port                = local.db_port
    to_port                  = local.db_port
    protocol                 = "tcp"
    description              = "EC2 ingress"
    source_security_group_id = module.autoscaling_sg.security_group_id
  }]
}


######################################################################################
# ALB
#
# Balances the traffic to the ECS containers hosted in EC2.
#
# It can only be accessed through the CDN, direct access to its public domain gets
# redirected to the CDN domain, and a custom secret header along with a host check
# is used to filter traffic.
#
# By default, it uses HTTP over port 80 (due to the restriction of creating valid SSL
# certs for the default *.amazonaws.com domain), but if a custom domain is set with
# 'var.route53_hosted_zone' an ACM cert is created and the listeners are configured
# as HTTPs in port 443 (80 redirects to this one).
#
# If a custom domain and HTTPs is not set, the traffic between the CDN and the ALB
# could be intercepted and the 'secret' header set by the CDN discovered. The ALB
# requires the host to be the custom domain anyways, which is what we need at an app
# layer, so this does not represent a threat (though it is preferred encrypt traffic).
#
# The traffic behind the load balancer is over HTTP in port 8069, SSL is managed at
# ALB/CDN layer.
#
######################################################################################
resource "random_password" "cloudfront_secret_for_alb" {
  length  = 16
  special = false
}

module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 8.0"

  name               = var.name
  load_balancer_type = "application"
  vpc_id             = module.vpc.vpc_id
  subnets            = module.vpc.public_subnets
  tags               = var.tags

  security_group_name            = "${var.name}-alb"
  security_group_use_name_prefix = false
  security_group_description     = "ALB security group"

  security_group_rules = [
    {
      protocol    = "tcp"
      type        = "ingress"
      from_port   = "80"
      to_port     = "80"
      description = "HTTP ingress"
      cidr_blocks = ["0.0.0.0/0"]
    },
    {
      protocol    = "tcp"
      type        = "ingress"
      from_port   = "443"
      to_port     = "443"
      description = "HTTPs ingress"
      cidr_blocks = ["0.0.0.0/0"]
    },
    {
      protocol                 = "tcp"
      type                     = "egress"
      from_port                = local.odoo_port
      to_port                  = local.odoo_port
      description              = "Odoo health check"
      source_security_group_id = module.autoscaling_sg.security_group_id
    }
  ]

  http_tcp_listeners = local.custom_domain ? [
    {
      port        = 80
      protocol    = "HTTP"
      action_type = "redirect"

      redirect = {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
    ] : [
    {
      port        = 80
      protocol    = "HTTP"
      action_type = "redirect"

      redirect = {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
        host        = module.cdn.cloudfront_distribution_domain_name
      }
    }
  ]

  http_tcp_listener_rules = local.custom_domain ? [] : [{
    http_tcp_listener_index = 0
    priority                = 10
    tags                    = { Name = "IngressFromCloudFront" }

    actions = [{
      type               = "forward"
      target_group_index = 0
    }]

    conditions = [
      {
        http_headers = [{
          http_header_name = local.auth_header_alb
          values           = [random_password.cloudfront_secret_for_alb.result]
        }]
      },
      {
        host_headers = [module.cdn.cloudfront_distribution_domain_name]
      },
    ]
  }]

  https_listeners = local.custom_domain ? [{
    port            = 443
    certificate_arn = module.acm[0].acm_certificate_arn
    action_type     = "redirect"

    redirect = {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
      host        = local.cloudfront_custom_domain
    }
  }] : []

  https_listener_rules = local.custom_domain ? [{
    https_listener_index = 0
    priority             = 10
    tags                 = { Name = "IngressFromCloudFront" }

    actions = [{
      type               = "forward"
      target_group_index = 0
    }]

    conditions = [
      {
        http_headers = [{
          http_header_name = local.auth_header_alb
          values           = [random_password.cloudfront_secret_for_alb.result]
        }]
      },
      {
        host_headers = [local.cloudfront_custom_domain]
      },
    ]
  }] : []

  target_groups = [{
    name             = var.name
    backend_protocol = "HTTP"
    backend_port     = local.odoo_port
    target_type      = "instance"

    health_check = {
      matcher = "200"
      path    = "/web/health"
    }
  }]
}


######################################################################################
# CLOUDFRONT
#
# Access point for all Odoo services.
#
# It redirects all queries to the ALB and caches some of them according to
# recommended CDN configuration:
# https://www.odoo.com/documentation/16.0/administration/install/cdn.html#configure-the-odoo-instance-with-the-new-zone
#
# If a custom domain is set with route 53, an alias and a ACM cert is used instead
# of the default ones.
#
# If the region used is not us-east-1 and a custom domain is used, an externally
# managed ACM cert for the custom domain must be created and provided
# with the 'var.acm_cert_use1' variable:
# https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/cnames-and-https-requirements.html#https-requirements-certificate-issuer
#
# For caching and origin request policies, AWS managed policies are queried and used.
#
######################################################################################
data "aws_cloudfront_cache_policy" "CachingDisabled" { name = "Managed-CachingDisabled" }
data "aws_cloudfront_cache_policy" "CachingOptimized" { name = "Managed-CachingOptimized" }
data "aws_cloudfront_origin_request_policy" "AllViewer" { name = "Managed-AllViewer" }

module "cdn" {
  source  = "terraform-aws-modules/cloudfront/aws"
  version = "~> 3.2"

  aliases     = local.custom_domain ? [local.cloudfront_custom_domain] : []
  comment     = "CDN for ${var.name}"
  enabled     = true
  price_class = var.cdn_price_class
  tags        = var.tags

  viewer_certificate = local.custom_domain ? {
    acm_certificate_arn = local.region_use1 ? module.acm[0].acm_certificate_arn : var.acm_cert_use1
    ssl_support_method  = "sni-only"
    } : {
    cloudfront_default_certificate = true
    minimum_protocol_version       = "TLSv1"
  }

  origin = {
    (var.name) = {
      domain_name = local.custom_domain ? local.alb_custom_domain : module.alb.lb_dns_name

      custom_origin_config = {
        https_port             = 443
        http_port              = 80
        origin_protocol_policy = local.custom_domain ? "https-only" : "http-only"
        origin_ssl_protocols   = ["TLSv1", "TLSv1.1", "TLSv1.2"]
      }

      custom_header = [{
        name  = local.auth_header_alb
        value = random_password.cloudfront_secret_for_alb.result
      }]
    }
  }

  default_cache_behavior = {
    target_origin_id         = var.name
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cache_policy_id          = data.aws_cloudfront_cache_policy.CachingDisabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.AllViewer.id
    use_forwarded_values     = false
  }

  ordered_cache_behavior = [
    for path in local.cache_path_patterns : {
      path_pattern             = path
      target_origin_id         = var.name
      viewer_protocol_policy   = "redirect-to-https"
      allowed_methods          = ["GET", "HEAD", "OPTIONS"]
      cached_methods           = ["GET", "HEAD"]
      cache_policy_id          = data.aws_cloudfront_cache_policy.CachingOptimized.id
      origin_request_policy_id = data.aws_cloudfront_origin_request_policy.AllViewer.id
      use_forwarded_values     = false
    }
  ]
}


######################################################################################
# EC2
#
# The official autoscaling module of terraform is used to create a scalable group of
# EC2 instances to act as ECS nodes. The base image used is the official alinux2
# provided by AWS (and exposed in a global SSM parameter publicly accessible:
# /aws/service/ecs/optimized-ami/amazon-linux-2/recommended). User data is used to
# configure the ECS agent.
#
# The security group only allows access to the ALB in the odoo port and full
# outbound traffic.
#
# To keep infrastructure in the free tier, t3.micro instances are used by default.
#
######################################################################################
module "autoscaling" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "~> 6.5"

  name                            = var.name
  image_id                        = jsondecode(data.aws_ssm_parameter.ecs_optimized_ami.value)["image_id"]
  instance_type                   = var.ecs_instance_type
  security_groups                 = [module.autoscaling_sg.security_group_id]
  ignore_desired_capacity_changes = true
  protect_from_scale_in           = true
  tags                            = var.tags

  create_iam_instance_profile = true
  iam_role_name               = "${var.name}-ec2"
  iam_role_use_name_prefix    = false
  iam_role_description        = "IAM role for ${var.name} EC2 instances"
  vpc_zone_identifier         = module.vpc.public_subnets
  health_check_type           = "EC2"
  min_size                    = 1
  max_size                    = 1
  desired_capacity            = 1

  iam_role_policies = {
    AmazonEC2ContainerServiceforEC2Role = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
    AmazonSSMManagedInstanceCore        = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  user_data = base64encode(templatefile("${path.module}/ec2/ecs_node.sh", {
    name = module.ecs_cluster.cluster_name
    tags = jsonencode(var.tags)
  }))

  autoscaling_group_tags = {
    AmazonECSManaged = true
  }
}

module "autoscaling_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name            = "${var.name}-ec2"
  use_name_prefix = false
  description     = "EC2 security group"
  vpc_id          = module.vpc.vpc_id
  egress_rules    = ["all-all"]
  tags            = var.tags

  ingress_with_source_security_group_id = [{
    from_port                = local.odoo_port
    to_port                  = local.odoo_port
    protocol                 = "tcp"
    description              = "ALB ingress"
    source_security_group_id = module.alb.security_group_id
  }]
}


######################################################################################
# EFS
#
# Odoo requires a filesystem to store attachments. AWS EFS is used for that. It is
# created and made available in the network where the ECS nodes run. Access points
# are used to simplify the permissions used by ECS containers to use it.
#
# Access is only granted in the NFS port to the ECS nodes with a security group
# rule pointing to ECS nodes security group.
#
######################################################################################
module "efs" {
  source  = "terraform-aws-modules/efs/aws"
  version = "~> 1.2"

  name          = var.name
  mount_targets = { for k, v in zipmap(local.azs, module.vpc.private_subnets) : k => { subnet_id = v } }
  attach_policy = false
  tags          = var.tags

  security_group_name        = "${var.name}-efs"
  security_group_description = "EFS security group"
  security_group_vpc_id      = module.vpc.vpc_id

  security_group_rules = {
    vpc = {
      description              = "EC2 ingress"
      source_security_group_id = module.autoscaling_sg.security_group_id
    }
  }

  access_points = {
    filestore = {
      root_directory = {
        path = local.filestore_path

        creation_info = {
          owner_gid   = 1001
          owner_uid   = 1001
          permissions = "777"
        }
      }
    }

    python_packages = {
      root_directory = {
        path = local.python_extra_packages

        creation_info = {
          owner_gid   = 1001
          owner_uid   = 1001
          permissions = "777"
        }
      }
    }

    addons = {
      root_directory = {
        path = local.addons_dir

        creation_info = {
          owner_gid   = 1001
          owner_uid   = 1001
          permissions = "777"
        }
      }
    }
  }
}


######################################################################################
# ECS
#
# ECS is the containers manager used to run Odoo as docker containers in a self
# managed cluster in EC2. The official terraform module of ECS is used for both
# the cluster infrastructure as we as the ECS service definition and creation.
#
# The base docker image used for the service is bitnami/odoo in the version 16. This
# image was chosen cause of its versatility to setup the base odoo configuration from
# environment variables (the entrypoint of the image creates an odoo config file
# automatically when provisioned based on environment variables):
# https://hub.docker.com/r/bitnami/odoo
#
# ECS task is run in host mode since each node is only meant to run one instance of
# the odoo container that require internet access, and given the default configuration
# does not use NAT gateways, host mode let containers used the main ENI to access
# internet and set access rules with the main security group:
# https://docs.aws.amazon.com/AmazonECS/latest/bestpracticesguide/networking-outbound.html#networking-public-subnet
#
# ECS task is configured with RDS credentials (read from the AWS managed secret),
# root user credentials (user is taken from 'var.odoo_root_email', password is
# automatically generated, stored in secrets and set as secret in the task), and
# SMTP configuration (an IAM user with SMTP permissions is created and its credentials
# are stored in secrets).
#
######################################################################################
module "ecs_cluster" {
  source  = "terraform-aws-modules/ecs/aws"
  version = "~> 5.2"

  cluster_name                          = var.name
  tags                                  = var.tags
  default_capacity_provider_use_fargate = false

  cluster_settings = {
    name  = "containerInsights"
    value = var.ecs_container_insights ? "enabled" : "disabled"
  }

  autoscaling_capacity_providers = {
    (var.name) = {
      auto_scaling_group_arn         = module.autoscaling.autoscaling_group_arn
      managed_termination_protection = "ENABLED"

      managed_scaling = {
        status                    = "ENABLED"
        maximum_scaling_step_size = 5
        minimum_scaling_step_size = 1
        target_capacity           = 60
      }

      default_capacity_provider_strategy = {
        weight = 60
        base   = 20
      }
    }
  }
}

module "ecs_service" {
  source  = "terraform-aws-modules/ecs/aws//modules/service"
  version = "~> 5.2"

  name                               = var.name
  cluster_arn                        = module.ecs_cluster.cluster_arn
  subnet_ids                         = module.vpc.private_subnets
  memory                             = var.ecs_task_memory
  launch_type                        = "EC2"
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100
  force_new_deployment               = false
  requires_compatibilities           = ["EC2"]
  network_mode                       = "host"
  tags                               = var.tags

  iam_role_name                      = "${var.name}-ecs-cluster"
  iam_role_use_name_prefix           = false
  iam_role_description               = "IAM role for ${var.name} ECS cluster"
  task_exec_iam_role_name            = "${var.name}-ecs-task-execution"
  task_exec_iam_role_use_name_prefix = false
  task_exec_iam_role_description     = "IAM role for ${var.name} ECS execution"
  task_exec_ssm_param_arns           = []
  create_tasks_iam_role              = false

  task_exec_secret_arns = [
    module.db.db_instance_master_user_secret_arn,
    aws_secretsmanager_secret.odoo_ses_user.arn,
    aws_secretsmanager_secret.odoo_root_user.arn,
  ]

  capacity_provider_strategy = {
    provider = {
      capacity_provider = module.ecs_cluster.autoscaling_capacity_providers[var.name].name
      weight            = 1
      base              = 1
    }
  }

  volume = {
    tmp = {}

    filestore = {
      efs_volume_configuration = {
        file_system_id     = module.efs.id
        transit_encryption = "ENABLED"

        authorization_config = {
          access_point_id = module.efs.access_points["filestore"].id
        }
      }
    }
  }

  container_definitions = {
    (var.name) = {
      image                    = local.custom_image ? "${aws_ecr_repository.odoo[0].repository_url}:latest" : "${var.odoo_docker_image}:${var.odoo_version}"
      readonly_root_filesystem = false

      port_mappings = [{
        name          = var.name
        containerPort = local.odoo_port
        protocol      = "tcp"
      }]

      mount_points = [
        { # Local volume for tmp files
          sourceVolume  = "tmp",
          containerPath = local.tmp_path
        },
        { # Save files in EFS
          sourceVolume  = "filestore",
          containerPath = local.filestore_path
        },
      ]

      environment = [
        # Root user
        { "name" : "ODOO_EMAIL", "value" : var.odoo_root_email },
        # Python path
        { "name" : "PYTHONPATH", "value" : local.python_extra_packages },
        # DB parameters
        { "name" : "ODOO_DATABASE_HOST", "value" : module.db.db_instance_address },
        { "name" : "ODOO_DATABASE_PORT_NUMBER", "value" : module.db.db_instance_port },
        { "name" : "ODOO_DATABASE_USER", "value" : module.db.db_instance_username },
        { "name" : "ODOO_DATABASE_NAME", "value" : var.odoo_db_name },
        # SMTP parameters
        { "name" : "ODOO_SMTP_HOST", "value" : "email-smtp.${data.aws_region.current.name}.amazonaws.com" },
        { "name" : "ODOO_SMTP_PORT_NUMBER", "value" : "587" },
        { "name" : "ODOO_SMTP_USER", "value" : module.ses_user.iam_access_key_id },
        { "name" : "ODOO_SMTP_PROTOCOL", "value" : "ssl" },
      ]

      secrets = [
        {
          "name" : "ODOO_DATABASE_PASSWORD",
          "valueFrom" : "${module.db.db_instance_master_user_secret_arn}:password::"
        },
        {
          "name" : "ODOO_SMTP_PASSWORD",
          "valueFrom" : "${aws_secretsmanager_secret.odoo_ses_user.arn}:password::"
        },
        {
          "name" : "ODOO_PASSWORD",
          "valueFrom" : "${aws_secretsmanager_secret.odoo_root_user.arn}:password::"
        },
      ]
    }
  }

  load_balancer = {
    service = {
      target_group_arn = element(module.alb.target_group_arns, 0)
      container_name   = var.name
      container_port   = local.odoo_port
    }
  }
}


######################################################################################
# ROUTE 53
#
# If a custom domain is set with the 'var.route53_hosted_zone', records are created
# as aliases for the CDN and the ALB.
#
# By default, the root domain of the hosted zone is used for the CDN and a subdomain
# of it in 'alb.' for the ALB. A subdomain can be optionally set with the
# 'var.odoo_domain' variable, setting the CDN domain in 'subdomain.' and the ALB domain
# in 'alb.subdomain.'.
#
######################################################################################
data "aws_route53_zone" "domain" {
  count = local.custom_domain ? 1 : 0

  zone_id = var.route53_hosted_zone
}

resource "aws_route53_record" "cdn" {
  count = local.custom_domain ? 1 : 0

  zone_id = var.route53_hosted_zone
  name    = local.cloudfront_custom_domain
  type    = "A"

  alias {
    name                   = module.cdn.cloudfront_distribution_domain_name
    zone_id                = module.cdn.cloudfront_distribution_hosted_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "alb" {
  count = local.custom_domain ? 1 : 0

  zone_id = var.route53_hosted_zone
  name    = local.alb_custom_domain
  type    = "A"

  alias {
    name                   = module.alb.lb_dns_name
    zone_id                = module.alb.lb_zone_id
    evaluate_target_health = true
  }
}


######################################################################################
# ACM
#
# When a custom domain is set, an ACM cert for the domain and '*.' subdomain is
# created and automatically validated.
#
# The cert is used for the ALB listeners and conditionally for the CDN (if the region
# is us-east-1, if not a separate cert hosted in us-east-1 must be provided).
#
######################################################################################
module "acm" {
  source  = "terraform-aws-modules/acm/aws"
  version = "~> 4.0"

  count = local.custom_domain ? 1 : 0

  domain_name               = local.cloudfront_custom_domain
  zone_id                   = var.route53_hosted_zone
  tags                      = var.tags
  wait_for_validation       = true
  subject_alternative_names = ["*.${local.cloudfront_custom_domain}"]
}


######################################################################################
# SES
#
# AWS SES is used as mail gateway. An IAM user is created with permissions to send
# emails through SES. A key pair is created, stored in AWS Secrets Manager and exposed
# to the odoo server process via ECS secret environment variables.
#
# In order for Odoo to send emails, any origin must be verified in SES (specific email
# addresses or email domains can be verified) and the AWS account must be taken off
# the sandbox mode via a support request (to be able to send to any destination).
#
######################################################################################
module "ses_user" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-user"
  version = "~> 5.27"

  name                          = "${var.name}-ses"
  force_destroy                 = true
  create_iam_user_login_profile = false
  tags                          = var.tags
}

resource "aws_iam_user_policy" "ses_user_send_email" {
  name   = "AmazonSesSendingAccess"
  user   = module.ses_user.iam_user_name
  policy = file("${path.module}/iam/send_email.json")
}

resource "aws_secretsmanager_secret" "odoo_ses_user" {
  name                    = "${var.name}-ses-user"
  description             = "Odoo SES user"
  recovery_window_in_days = 0
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "odoo_ses_user" {
  secret_id = aws_secretsmanager_secret.odoo_ses_user.id

  secret_string = jsonencode({
    username = module.ses_user.iam_access_key_id
    password = module.ses_user.iam_access_key_ses_smtp_password_v4
  })
}


######################################################################################
# ODOO ROOT USER
#
# Root user of odoo is initialized with 'var.odoo_root_email' as the root user and
# a randomly generated password. The password is stored in AWS Secrets Manager,
# exposed to the odoo server via ECS task environment variable and set as root user
# by the bitnami/odoo image entrypoint script.
#
######################################################################################
resource "random_password" "odoo_root_password" {
  length  = 16
  special = true
}

resource "aws_secretsmanager_secret" "odoo_root_user" {
  name                    = "${var.name}-root-user"
  description             = "Odoo root user"
  recovery_window_in_days = 0
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "odoo_root_user" {
  secret_id = aws_secretsmanager_secret.odoo_root_user.id

  secret_string = jsonencode({
    username = var.odoo_root_email
    password = random_password.odoo_root_password.result
  })
}


######################################################################################
# ODOO CUSTOM MODULES
#
# A S3 bucket is created to store all files belonging to custom modules to install,
# a requirements.txt file for extra python dependencies to install, and optionally
# a folder with python dependencies that are installed directly as folder inside
# site-packages.
#
# Files are explored in the paths set in 'var.odoo_custom_modules_paths' and uploaded
# to the bucket. The path sent in that variable must be parent of the folders
# containing the modules (similar to how the path variable is set in the odoo server).
#
######################################################################################
module "s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.14"

  bucket        = "${var.name}-odoo-custom"
  tags          = var.tags
  force_destroy = true
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket      = module.s3_bucket.s3_bucket_id
  eventbridge = true
}

locals {
  mime_types    = jsondecode(file("${path.module}/util/mime.json"))
  modules_files = merge([for k, v in { for path in var.odoo_custom_modules_paths : path => fileset(path, "*/**") } : { for path in v : "${k}/${path}" => { src = k, object = path } if !anytrue([for filter in var.extra_files_filter : strcontains("${k}/${path}", filter)]) }]...)
  python_files  = merge([for k, v in { for path in var.odoo_python_dependencies_paths : path => fileset(path, "**") } : { for path in v : "${k}/${path}" => { src = k, object = path } if !anytrue([for filter in var.extra_files_filter : strcontains("${k}/${path}", filter)]) }]...)
}

resource "aws_s3_object" "module_files" {
  for_each = local.modules_files

  bucket       = module.s3_bucket.s3_bucket_id
  key          = "modules/${each.value.object}"
  source       = each.key
  etag         = filemd5(each.key)
  content_type = lookup(local.mime_types, regex("\\.[^.]+$", each.key), null)
}

resource "aws_s3_object" "python_dependencies" {
  for_each = local.python_files

  bucket       = module.s3_bucket.s3_bucket_id
  key          = "python/${each.value.object}"
  source       = each.key
  etag         = filemd5(each.key)
  content_type = lookup(local.mime_types, regex("\\.[^.]+$", each.key), null)
}

resource "aws_s3_object" "python_requirements_file" {
  count = var.python_requirements_file != null ? 1 : 0

  # Wait for bucket and events to be created for
  # the first trigger to happen on object creation
  depends_on = [
    aws_cloudwatch_event_rule.image_build,
    aws_cloudwatch_event_target.image_build_target,
    aws_s3_bucket_notification.bucket_notification
  ]

  bucket       = module.s3_bucket.s3_bucket_id
  key          = local.requirements_file_object
  source       = var.python_requirements_file
  etag         = filemd5(var.python_requirements_file)
  content_type = "text/plain"
}


######################################################################################
# DATASYNC
#
# For custom module files and python dependencies packages (set directly as files
# instead than as a requirements.txt file), a S3 bucket is used as a object storage
# for the files, and a AWS DataSync task is set to sync the files from the bucket
# with the EFS storage used for odoo persistant information.
#
# The sync is done periodically (once a week) and an event driven process is
# triggered if changes in S3 are detected. Once the DataSync Task has been executed
# odoo is ready for a "Update App List" action.
#
######################################################################################
resource "aws_datasync_location_efs" "odoo_filestore_addons" {
  efs_file_system_arn         = module.efs.mount_targets[keys(module.efs.mount_targets)[0]].file_system_arn
  access_point_arn            = module.efs.access_points["addons"].arn
  file_system_access_role_arn = module.datasync_role.iam_role_arn
  in_transit_encryption       = "TLS1_2"
  tags                        = var.tags

  ec2_config {
    security_group_arns = [module.autoscaling_sg.security_group_arn]
    subnet_arn          = module.vpc.private_subnet_arns[0]
  }
}

resource "aws_datasync_location_efs" "odoo_filestore_python" {
  efs_file_system_arn         = module.efs.mount_targets[keys(module.efs.mount_targets)[0]].file_system_arn
  access_point_arn            = module.efs.access_points["python_packages"].arn
  file_system_access_role_arn = module.datasync_role.iam_role_arn
  in_transit_encryption       = "TLS1_2"
  tags                        = var.tags

  ec2_config {
    security_group_arns = [module.autoscaling_sg.security_group_arn]
    subnet_arn          = module.vpc.private_subnet_arns[0]
  }
}

resource "aws_datasync_location_s3" "odoo_bucket_modules" {
  s3_bucket_arn = module.s3_bucket.s3_bucket_arn
  subdirectory  = "/modules/"
  tags          = var.tags

  s3_config {
    bucket_access_role_arn = module.datasync_role.iam_role_arn
  }
}

resource "aws_datasync_location_s3" "odoo_bucket_python" {
  s3_bucket_arn = module.s3_bucket.s3_bucket_arn
  subdirectory  = "/python/"
  tags          = var.tags

  s3_config {
    bucket_access_role_arn = module.datasync_role.iam_role_arn
  }
}

module "datasync_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role"
  version = "~> 5.27"

  role_name               = "${var.name}-datasync"
  role_description        = "IAM role for ${var.name} data sync"
  create_role             = true
  create_instance_profile = true
  role_requires_mfa       = false
  trusted_role_services   = ["datasync.amazonaws.com"]
  trusted_role_actions    = ["sts:AssumeRole"]
  tags                    = var.tags
}

resource "aws_iam_role_policy" "datasync_s3_access" {
  name = "${var.name}-datasync-bucket-access"
  role = module.datasync_role.iam_role_name

  policy = templatefile("${path.module}/iam/datasync_s3.json", {
    bucket = module.s3_bucket.s3_bucket_id
  })
}

resource "aws_iam_role_policy" "datasync_efs_access" {
  name = "${var.name}-datasync-efs-access"
  role = module.datasync_role.iam_role_name

  policy = templatefile("${path.module}/iam/datasync_efs.json", {
    efs = module.efs.arn
  })
}

resource "aws_datasync_task" "sync_modules" {
  name                     = "${var.name}-modules"
  source_location_arn      = aws_datasync_location_s3.odoo_bucket_modules.arn
  destination_location_arn = aws_datasync_location_efs.odoo_filestore_addons.arn
  tags                     = var.tags

  options {
    preserve_deleted_files = var.datasync_preserve_deleted_files ? "PRESERVE" : "REMOVE"
  }

  schedule {
    schedule_expression = local.cron_expression
  }
}

resource "aws_datasync_task" "sync_python_packages" {
  name                     = "${var.name}-python"
  source_location_arn      = aws_datasync_location_s3.odoo_bucket_python.arn
  destination_location_arn = aws_datasync_location_efs.odoo_filestore_python.arn
  tags                     = var.tags

  options {
    preserve_deleted_files = var.datasync_preserve_deleted_files ? "PRESERVE" : "REMOVE"
  }

  schedule {
    schedule_expression = local.cron_expression
  }
}


######################################################################################
# ODOO IMAGE BUILDER
#
# If a requirements.txt file is set for custom python dependencies, a custom docker
# image is created with this dependencies installed in the python venv used by
# the bitnami/odoo image.
#
# AWS Image Builder is used to create and push the image to a private ECR repository
# and to periodically rebuild the image if the base bitnami/odoo image changes.
#
######################################################################################
resource "aws_ecr_repository" "odoo" {
  count = local.custom_image ? 1 : 0

  name                 = var.name
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  tags                 = var.tags

  image_scanning_configuration {
    scan_on_push = false
  }
}

module "image_builder_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role"
  version = "~> 5.27"

  count = local.custom_image ? 1 : 0

  role_name               = "${var.name}-image-builder"
  role_description        = "IAM role for ${var.name} image builder"
  create_role             = true
  create_instance_profile = true
  role_requires_mfa       = false
  trusted_role_services   = ["ec2.amazonaws.com"]
  trusted_role_actions    = ["sts:AssumeRole"]
  tags                    = var.tags

  custom_role_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/EC2InstanceProfileForImageBuilder",
    "arn:aws:iam::aws:policy/EC2InstanceProfileForImageBuilderECRContainerBuilds",
  ]
}

resource "aws_iam_role_policy" "image_builder_role_modules_bucket_access" {
  name = "${var.name}-modules-bucket-access"
  role = module.image_builder_role[0].iam_role_name

  policy = templatefile("${path.module}/iam/bucket_read.json", {
    bucket = module.s3_bucket.s3_bucket_id
  })
}

resource "aws_imagebuilder_component" "install_python_dependencies" {
  count = local.custom_image ? 1 : 0

  name        = "${var.name}-install-python-dependencies"
  description = "Component to install extra python dependencies for odoo in ${var.name}"
  platform    = "Linux"
  version     = "1.0.0"
  tags        = var.tags

  data = templatefile("${path.module}/image_builder/install_python_dependencies.yaml", {
    source = "${module.s3_bucket.s3_bucket_id}/${local.requirements_file_object}"
  })
}

resource "aws_imagebuilder_container_recipe" "odoo_container" {
  count = local.custom_image ? 1 : 0

  name                     = var.name
  description              = "Recipe for ${var.name} custom image"
  version                  = "1.0.0"
  parent_image             = "${var.odoo_docker_image}:${var.odoo_version}"
  dockerfile_template_data = file("${path.module}/image_builder/dockerfile")
  container_type           = "DOCKER"
  working_directory        = "/tmp"
  tags                     = var.tags

  target_repository {
    repository_name = aws_ecr_repository.odoo[0].name
    service         = "ECR"
  }

  component {
    component_arn = aws_imagebuilder_component.install_python_dependencies[0].arn
  }
}

resource "aws_imagebuilder_infrastructure_configuration" "odoo_container" {
  count = local.custom_image ? 1 : 0

  name                          = var.name
  description                   = "Infrastructure configuration for ${var.name} custom image"
  instance_profile_name         = module.image_builder_role[0].iam_instance_profile_name
  instance_types                = ["t3.micro"]
  subnet_id                     = module.vpc.public_subnets[0]
  security_group_ids            = [module.image_builder_sg[0].security_group_id]
  terminate_instance_on_failure = true
  resource_tags                 = var.tags
  tags                          = var.tags
}

module "image_builder_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  count = local.custom_image ? 1 : 0

  name            = "${var.name}-image-builder"
  use_name_prefix = false
  description     = "Image builder for ${var.name} security group"
  vpc_id          = module.vpc.vpc_id
  egress_rules    = ["all-all"]
  tags            = var.tags
}

resource "aws_imagebuilder_distribution_configuration" "odoo_container" {
  count = local.custom_image ? 1 : 0

  name        = var.name
  description = "Distribution configuration for ${var.name}"
  tags        = var.tags

  distribution {
    region = data.aws_region.current.name

    container_distribution_configuration {
      container_tags = ["latest"]

      target_repository {
        service         = "ECR"
        repository_name = aws_ecr_repository.odoo[0].name
      }
    }
  }
}

resource "aws_imagebuilder_image_pipeline" "odoo_container" {
  count = local.custom_image ? 1 : 0

  name                             = var.name
  description                      = "Image pipeline for ${var.name}"
  container_recipe_arn             = aws_imagebuilder_container_recipe.odoo_container[0].arn
  infrastructure_configuration_arn = aws_imagebuilder_infrastructure_configuration.odoo_container[0].arn
  distribution_configuration_arn   = aws_imagebuilder_distribution_configuration.odoo_container[0].arn
  tags                             = var.tags

  schedule {
    schedule_expression = local.cron_expression
  }
}


######################################################################################
# EVENTBRIDGE
#
#
######################################################################################
module "eventbridge_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role"
  version = "~> 5.27"

  role_name               = "${var.name}-eventbridge"
  role_description        = "IAM role for ${var.name} eventbridge"
  create_role             = true
  create_instance_profile = true
  role_requires_mfa       = false
  trusted_role_services   = ["events.amazonaws.com"]
  trusted_role_actions    = ["sts:AssumeRole"]
  tags                    = var.tags

  custom_role_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonSSMAutomationRole"
  ]
}

resource "aws_iam_role_policy" "eventbridge_execute_image_pipeline" {
  count = local.custom_image ? 1 : 0

  name = "${var.name}-eventbridge-image-pipeline"
  role = module.eventbridge_role.iam_role_name

  policy = templatefile("${path.module}/iam/image_pipeline_execute.json", {
    image_pipeline = aws_imagebuilder_image_pipeline.odoo_container[0].arn
  })
}

resource "aws_iam_role_policy" "eventbridge_run_tasks" {
  name = "${var.name}-eventbridge-run-task"
  role = module.eventbridge_role.iam_role_name

  policy = templatefile("${path.module}/iam/run_datasync.json", {
    tasks = [aws_datasync_task.sync_modules.arn, aws_datasync_task.sync_python_packages.arn]
  })
}

resource "aws_iam_role_policy" "eventbridge_update_ecs_service" {
  name = "${var.name}-eventbridge-update-ecs-service"
  role = module.eventbridge_role.iam_role_name

  policy = templatefile("${path.module}/iam/ecs_update_service.json", {
    service = module.ecs_service.id
  })
}

resource "aws_cloudwatch_event_rule" "image_build" {
  count = local.custom_image ? 1 : 0

  name        = "${var.name}-image-build"
  description = "Rebuild image when requirements.txt changes"
  tags        = var.tags

  event_pattern = templatefile("${path.module}/eventbridge/s3_object_rule.json", {
    bucket = module.s3_bucket.s3_bucket_id
    object = local.requirements_file_object
  })
}

resource "aws_cloudwatch_event_target" "image_build_target" {
  count = local.custom_image ? 1 : 0

  rule     = aws_cloudwatch_event_rule.image_build[0].name
  arn      = aws_imagebuilder_image_pipeline.odoo_container[0].arn
  role_arn = module.eventbridge_role.iam_role_arn
}

resource "aws_cloudwatch_event_rule" "modules_sync" {
  name        = "${var.name}-modules-sync"
  description = "Sync modules files stored in s3"
  tags        = var.tags

  event_pattern = templatefile("${path.module}/eventbridge/s3_object_prefix_rule.json", {
    bucket = module.s3_bucket.s3_bucket_id
    prefix = "modules/"
  })
}

resource "aws_cloudwatch_event_target" "modules_sync" {
  rule     = aws_cloudwatch_event_rule.modules_sync.name
  arn      = "${replace(aws_ssm_document.datasync.arn, "document", "automation-definition")}:$DEFAULT"
  role_arn = module.eventbridge_role.iam_role_arn

  input = jsonencode({
    TaskArn = [aws_datasync_task.sync_modules.arn]
  })
}

resource "aws_cloudwatch_event_rule" "python_files_sync" {
  name        = "${var.name}-python-files-sync"
  description = "Sync python files stored in s3"
  tags        = var.tags

  event_pattern = templatefile("${path.module}/eventbridge/s3_object_prefix_rule.json", {
    bucket = module.s3_bucket.s3_bucket_id
    prefix = "python/"
  })
}

resource "aws_cloudwatch_event_target" "python_files_sync" {
  rule     = aws_cloudwatch_event_rule.python_files_sync.name
  arn      = "${replace(aws_ssm_document.datasync.arn, "document", "automation-definition")}:$DEFAULT"
  role_arn = module.eventbridge_role.iam_role_arn

  input = jsonencode({
    TaskArn = [aws_datasync_task.sync_python_packages.arn]
  })
}

resource "aws_cloudwatch_event_rule" "ecr_push" {
  count = local.custom_image ? 1 : 0

  name        = "${var.name}-ecr-push"
  description = "Replace ECS task on ECR image push"
  tags        = var.tags

  event_pattern = templatefile("${path.module}/eventbridge/ecr_image_push.json", {
    repository = aws_ecr_repository.odoo[0].id
    tag        = "latest"
  })
}

resource "aws_cloudwatch_event_target" "ecr_push" {
  count = local.custom_image ? 1 : 0

  rule     = aws_cloudwatch_event_rule.ecr_push[0].name
  arn      = "${replace(aws_ssm_document.ecs_replace_task.arn, "document", "automation-definition")}:$DEFAULT"
  role_arn = module.eventbridge_role.iam_role_arn

  input = jsonencode({
    Cluster = [module.ecs_cluster.cluster_name]
    Service = [module.ecs_service.name]
  })
}

resource "aws_ssm_document" "datasync" {
  name            = "${var.name}-run-datasync"
  document_format = "YAML"
  document_type   = "Automation"
  content         = file("${path.module}/ssm/run_datasync_task.yaml")
  tags            = var.tags
}

resource "aws_ssm_document" "ecs_replace_task" {
  name            = "${var.name}-ecs-replace-task"
  document_format = "YAML"
  document_type   = "Automation"
  content         = file("${path.module}/ssm/replace_ecs_task.yaml")
  tags            = var.tags
}
