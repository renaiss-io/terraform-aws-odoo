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
  db_name                        = "postgres" // DB named odoo must not be created on init
  engine_version                 = "14"
  major_engine_version           = "14"
  instance_class                 = var.db_instance_type
  allocated_storage              = var.db_size
  username                       = var.name
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

  name        = var.name
  description = "DB security group"
  vpc_id      = module.vpc.vpc_id
  tags        = var.tags

  ingress_with_cidr_blocks = [
    {
      from_port   = local.db_port
      to_port     = local.db_port
      protocol    = "tcp"
      description = "server access"
      cidr_blocks = module.vpc.vpc_cidr_block
    },
  ]
}

######################################################################################
# EC2
######################################################################################
module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 8.0"

  name               = var.name
  load_balancer_type = "application"
  vpc_id             = module.vpc.vpc_id
  subnets            = module.vpc.public_subnets
  security_groups    = [module.alb_sg.security_group_id]
  tags               = var.tags

  http_tcp_listeners = [
    {
      port        = 80
      protocol    = "HTTP"
      action_type = "redirect"

      redirect = {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    },
  ]

  https_listeners = [{
    port               = 443
    certificate_arn    = local.https_listener_cert
    target_group_index = 0
  }]

  target_groups = [
    {
      name             = var.name
      backend_protocol = "HTTP"
      backend_port     = local.odoo_port
      target_type      = "ip"

      # odoo server returns a 303 in /
      health_check = {
        matcher = 303
      }
    },
  ]
}

module "alb_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name                = "${var.name}-service"
  description         = "Service security group"
  vpc_id              = module.vpc.vpc_id
  tags                = var.tags
  ingress_rules       = ["http-80-tcp", "https-443-tcp"]
  ingress_cidr_blocks = ["0.0.0.0/0"]
  egress_rules        = ["all-all"]
  egress_cidr_blocks  = module.vpc.private_subnets_cidr_blocks
}

module "autoscaling" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "~> 6.5"

  name                            = var.name
  image_id                        = jsondecode(data.aws_ssm_parameter.ecs_optimized_ami.value)["image_id"]
  instance_type                   = "t3.micro"
  security_groups                 = [module.autoscaling_sg.security_group_id]
  ignore_desired_capacity_changes = true
  protect_from_scale_in           = true // Required for managed_termination_protection = "ENABLED"
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

  user_data = base64encode(templatefile("${path.module}/ecs/ecs.sh", {
    name = var.name
    tags = jsonencode(var.tags)
  }))

  autoscaling_group_tags = {
    AmazonECSManaged = true
  }
}

module "autoscaling_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name         = var.name
  description  = "Autoscaling group security group"
  vpc_id       = module.vpc.vpc_id
  egress_rules = ["all-all"]
  tags         = var.tags

  number_of_computed_ingress_with_source_security_group_id = 1
  computed_ingress_with_source_security_group_id = [
    {
      rule                     = "http-80-tcp"
      source_security_group_id = module.alb_sg.security_group_id
    }
  ]
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
    provider = {
      auto_scaling_group_arn         = module.autoscaling.autoscaling_group_arn
      managed_termination_protection = "ENABLED"

      managed_scaling = {
        maximum_scaling_step_size = 5
        minimum_scaling_step_size = 1
        status                    = "ENABLED"
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
  tags                     = var.tags
  memory                   = 800
  subnet_ids               = module.vpc.private_subnets
  requires_compatibilities = ["EC2"]

  capacity_provider_strategy = {
    provider = {
      capacity_provider = module.ecs_cluster.autoscaling_capacity_providers["provider"].name
      weight            = 1
      base              = 1
    }
  }

  volume = {
    tmp = {}
  }

  container_definitions = {
    odoo = {
      image                    = "odoo:latest"
      readonly_root_filesystem = false

      port_mappings = [
        {
          name          = var.name
          containerPort = local.odoo_port
          protocol      = "tcp"
        }
      ]

      # odoo requires a tmp folder
      mount_points = [
        {
          sourceVolume  = "tmp",
          containerPath = "/tmp"
        }
      ]

      environment = [
        { "name" : "DB_PORT_5432_TCP_ADDR", "value" : module.db.db_instance_address },
        { "name" : "DB_PORT_5432_TCP_PORT", "value" : module.db.db_instance_port },
        { "name" : "DB_ENV_POSTGRES_USER", "value" : module.db.db_instance_username },
      ]

      # RDS saves credentials in a json like { "username": "", "password": "" }
      # ECS allows to parse the secret pulled from AWS before setting the environment variable
      secrets = [
        {
          "name" : "DB_ENV_POSTGRES_PASSWORD",
          "valueFrom" : "${tolist(data.aws_secretsmanager_secrets.db_master_password.arns)[0]}:password::"
        }
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

  security_group_rules = {
    alb_http_ingress = {
      type                     = "ingress"
      from_port                = local.odoo_port
      to_port                  = local.odoo_port
      protocol                 = "tcp"
      description              = "Service port"
      source_security_group_id = module.alb_sg.security_group_id
    }

    outbound = {
      protocol  = "tcp"
      from_port = local.db_port
      to_port   = local.db_port
      type      = "egress"

      cidr_blocks = ["0.0.0.0/0"]
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
  domain = var.route53_hosted_zone != null ? var.odoo_domain != null ? var.odoo_domain : data.aws_route53_zone.domain[0].name : null
}

module "acm" {
  source  = "terraform-aws-modules/acm/aws"
  version = "~> 4.0"

  count = local.create_acm_cert ? 1 : 0

  domain_name         = local.domain
  zone_id             = var.route53_hosted_zone
  tags                = var.tags
  wait_for_validation = true

  subject_alternative_names = [
    "*.${local.domain}"
  ]
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
