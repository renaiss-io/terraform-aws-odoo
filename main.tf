######################################################################################
# VPC
######################################################################################
data "aws_availability_zones" "available" {}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = var.name
  cidr = var.vpc_cidr
  tags = var.tags

  azs              = local.azs
  public_subnets   = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k)]
  private_subnets  = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 3)]
  database_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 6)]

  create_database_subnet_group      = true
  create_database_nat_gateway_route = false
  enable_nat_gateway                = false

  map_public_ip_on_launch = true
}


######################################################################################
# DB
######################################################################################
module "db" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 6.0"

  identifier                     = var.name
  instance_use_identifier_prefix = false
  create_db_option_group         = false
  create_db_parameter_group      = false
  engine                         = "postgres"
  family                         = "postgres14"
  db_name                        = var.odoo_db_name
  engine_version                 = "14"
  major_engine_version           = "14"
  instance_class                 = var.db_instance_type
  allocated_storage              = var.db_size
  username                       = "odoo"
  port                           = local.db_port
  db_subnet_group_name           = module.vpc.database_subnet_group
  vpc_security_group_ids         = [module.db_security_group.security_group_id]
  maintenance_window             = "Mon:00:00-Mon:03:00"
  backup_window                  = "03:00-06:00"
  backup_retention_period        = 0
  tags                           = var.tags
}

# Query secret created by RDS cause the official RDS module does not expose it
# https://github.com/terraform-aws-modules/terraform-aws-rds/issues/501
data "aws_secretsmanager_secrets" "db_master_password" {
  filter {
    name   = "owning-service"
    values = ["rds"]
  }

  filter {
    name   = "tag-value"
    values = [module.db.db_instance_arn]
  }
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
######################################################################################
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

  http_tcp_listeners = [{
    port        = 80
    protocol    = "HTTP"
    action_type = "redirect"

    redirect = {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }]

  https_listeners = [{
    port            = 443
    certificate_arn = local.https_listener_cert
  }]

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
# EC2
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
  iam_role_name               = "${var.name}-ecs"
  iam_role_description        = "ECS role for ${var.name}"
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
  }
}


######################################################################################
# ECS
######################################################################################
module "ecs_cluster" {
  source  = "terraform-aws-modules/ecs/aws"
  version = "~> 5.2"

  cluster_name                          = var.name
  tags                                  = var.tags
  default_capacity_provider_use_fargate = false

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

  name                     = var.name
  cluster_arn              = module.ecs_cluster.cluster_arn
  subnet_ids               = module.vpc.private_subnets
  memory                   = var.ecs_task_memory
  requires_compatibilities = ["EC2"]
  network_mode             = "host"
  tags                     = var.tags

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
      image                    = "${var.odoo_docker_image}:${var.odoo_version}"
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
          "valueFrom" : "${tolist(data.aws_secretsmanager_secrets.db_master_password.arns)[0]}:password::"
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
# DOMAIN
######################################################################################
data "aws_route53_zone" "domain" {
  count = var.route53_hosted_zone != null ? 1 : 0

  zone_id = var.route53_hosted_zone
}

locals {
  domain = var.route53_hosted_zone != null ? var.odoo_domain != null ? var.odoo_domain : data.aws_route53_zone.domain[0].name : module.alb.lb_dns_name
}

module "acm" {
  source  = "terraform-aws-modules/acm/aws"
  version = "~> 4.0"

  count = local.create_acm_cert ? 1 : 0

  domain_name               = local.domain
  zone_id                   = var.route53_hosted_zone
  tags                      = var.tags
  wait_for_validation       = true
  subject_alternative_names = ["*.${local.domain}"]
}

resource "aws_route53_record" "www" {
  count = var.route53_hosted_zone != null ? 1 : 0

  zone_id = var.route53_hosted_zone
  name    = local.domain
  type    = "A"

  alias {
    name                   = module.alb.lb_dns_name
    zone_id                = module.alb.lb_zone_id
    evaluate_target_health = true
  }
}


######################################################################################
# SES
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
# ODOO
######################################################################################
resource "random_password" "odoo_root_password" {
  length  = 16
  special = true
}

resource "aws_secretsmanager_secret" "odoo_root_user" {
  name                    = "${var.name}-root-user"
  description             = "Odoo SES user"
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
