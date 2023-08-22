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
locals {
  mime_types    = jsondecode(file("${path.module}/util/mime.json"))
  modules_files = merge([for k, v in { for path in var.odoo_custom_modules_paths : path => fileset(path, "*/**") } : { for path in v : "${k}/${path}" => { src = k, object = path } if !anytrue([for filter in var.extra_files_filter : strcontains("${k}/${path}", filter)]) }]...)
  python_files  = merge([for k, v in { for path in var.odoo_python_dependencies_paths : path => fileset(path, "**") } : { for path in v : "${k}/${path}" => { src = k, object = path } if !anytrue([for filter in var.extra_files_filter : strcontains("${k}/${path}", filter)]) }]...)
}

module "s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.14"

  count = (local.custom_image || local.modules_files_length || local.python_files_length) ? 1 : 0

  bucket        = "${var.name}-odoo-custom"
  tags          = var.tags
  force_destroy = true
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  count = (local.custom_image || local.modules_files_length || local.python_files_length) ? 1 : 0

  bucket      = module.s3_bucket[0].s3_bucket_id
  eventbridge = true
  dynamic "lambda_function" {
    for_each = local.custom_image ? [1] : []
    content {
      lambda_function_arn = module.lambda_image_builder[0].lambda_function_arn
      events              = ["s3:ObjectCreated:*"]
      filter_prefix       = local.requirements_file_object
    }
  }
}

resource "aws_s3_object" "module_files" {
  depends_on = [
    aws_cloudwatch_event_target.modules_sync[0],
    aws_cloudwatch_event_rule.modules_sync[0],
    aws_s3_bucket_notification.bucket_notification[0]
  ]

  for_each = local.modules_files

  bucket       = module.s3_bucket[0].s3_bucket_id
  key          = "modules/${each.value.object}"
  source       = each.key
  etag         = filemd5(each.key)
  content_type = lookup(local.mime_types, regex("\\.[^.]+$", each.key), null)
}

resource "aws_s3_object" "python_dependencies" {
  depends_on = [
    aws_cloudwatch_event_target.python_files_sync[0],
    aws_cloudwatch_event_rule.python_files_sync[0],
    aws_s3_bucket_notification.bucket_notification[0]
  ]
  for_each = local.python_files

  bucket       = module.s3_bucket[0].s3_bucket_id
  key          = "python/${each.value.object}"
  source       = each.key
  etag         = filemd5(each.key)
  content_type = lookup(local.mime_types, regex("\\.[^.]+$", each.key), null)
}

resource "aws_s3_object" "python_requirements_file" {
  count = (local.custom_image) ? 1 : 0

  # Wait for bucket and events to be created for
  # the first trigger to happen on object creation

  depends_on = [
    module.lambda_image_builder[0],
    aws_s3_bucket_notification.bucket_notification[0]
  ]

  bucket       = module.s3_bucket[0].s3_bucket_id
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
  count = (local.modules_files_length) ? 1 : 0

  efs_file_system_arn         = module.efs.mount_targets[keys(module.efs.mount_targets)[0]].file_system_arn
  access_point_arn            = module.efs.access_points["addons"].arn
  file_system_access_role_arn = module.datasync_role[0].iam_role_arn
  in_transit_encryption       = "TLS1_2"
  tags                        = var.tags

  ec2_config {
    security_group_arns = [module.autoscaling_sg.security_group_arn]
    subnet_arn          = module.vpc.private_subnet_arns[0]
  }
}

resource "aws_datasync_location_efs" "odoo_filestore_python" {
  count = (local.python_files_length) ? 1 : 0

  efs_file_system_arn         = module.efs.mount_targets[keys(module.efs.mount_targets)[0]].file_system_arn
  access_point_arn            = module.efs.access_points["python_packages"].arn
  file_system_access_role_arn = module.datasync_role[0].iam_role_arn
  in_transit_encryption       = "TLS1_2"
  tags                        = var.tags

  ec2_config {
    security_group_arns = [module.autoscaling_sg.security_group_arn]
    subnet_arn          = module.vpc.private_subnet_arns[0]
  }
}

resource "aws_datasync_location_s3" "odoo_bucket_modules" {
  count = (local.modules_files_length) ? 1 : 0

  s3_bucket_arn = module.s3_bucket[0].s3_bucket_arn
  subdirectory  = "/modules/"
  tags          = var.tags

  s3_config {
    bucket_access_role_arn = module.datasync_role[0].iam_role_arn
  }
}

resource "aws_datasync_location_s3" "odoo_bucket_python" {
  count = (local.python_files_length) ? 1 : 0

  s3_bucket_arn = module.s3_bucket[0].s3_bucket_arn
  subdirectory  = "/python/"
  tags          = var.tags

  s3_config {
    bucket_access_role_arn = module.datasync_role[0].iam_role_arn
  }
}

module "datasync_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role"
  version = "~> 5.27"

  count = (local.python_files_length || local.modules_files_length) ? 1 : 0

  role_name               = "${var.name}-datasync"
  role_description        = "IAM role for ${var.name} data sync"
  create_role             = true
  create_instance_profile = false
  role_requires_mfa       = false
  trusted_role_services   = ["datasync.amazonaws.com"]
  trusted_role_actions    = ["sts:AssumeRole"]
  tags                    = var.tags
}

resource "aws_iam_role_policy" "datasync_s3_access" {
  count = (local.python_files_length || local.modules_files_length) ? 1 : 0

  name = "${var.name}-datasync-bucket-access"
  role = module.datasync_role[0].iam_role_name

  policy = templatefile("${path.module}/iam/datasync_s3.json", {
    bucket = module.s3_bucket[0].s3_bucket_id
  })
}

resource "aws_iam_role_policy" "datasync_efs_access" {
  count = (local.python_files_length || local.modules_files_length) ? 1 : 0

  name = "${var.name}-datasync-efs-access"
  role = module.datasync_role[0].iam_role_name

  policy = templatefile("${path.module}/iam/datasync_efs.json", {
    efs = module.efs.arn
  })
}

resource "aws_datasync_task" "sync_modules" {
  count = (local.modules_files_length) ? 1 : 0

  name                     = "${var.name}-modules"
  source_location_arn      = aws_datasync_location_s3.odoo_bucket_modules[0].arn
  destination_location_arn = aws_datasync_location_efs.odoo_filestore_addons[0].arn
  tags                     = var.tags

  options {
    preserve_deleted_files = var.datasync_preserve_deleted_files ? "PRESERVE" : "REMOVE"
  }

  schedule {
    schedule_expression = local.cron_expression
  }
}

resource "aws_datasync_task" "sync_python_packages" {
  count = (local.python_files_length) ? 1 : 0

  name                     = "${var.name}-python"
  source_location_arn      = aws_datasync_location_s3.odoo_bucket_python[0].arn
  destination_location_arn = aws_datasync_location_efs.odoo_filestore_python[0].arn
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
  count = (local.custom_image || local.modules_files_length || local.python_files_length) ? 1 : 0

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

  count = (local.custom_image) ? 1 : 0

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
  count = (local.custom_image) ? 1 : 0

  name = "${var.name}-modules-bucket-access"
  role = module.image_builder_role[0].iam_role_name

  policy = templatefile("${path.module}/iam/bucket_read.json", {
    bucket = module.s3_bucket[0].s3_bucket_id
  })
}

resource "aws_iam_role_policy" "eventbridge_execute_image_pipeline2" {
  count = (local.custom_image) ? 1 : 0

  name = "${var.name}-eventbridge-image-pipeline2"
  role = module.image_builder_role[0].iam_role_name

  policy = templatefile("${path.module}/iam/image_pipeline_execute.json", {
    image_pipeline = aws_imagebuilder_image_pipeline.odoo_container[0].arn
  })
}

resource "aws_imagebuilder_component" "install_python_dependencies" {
  count = (local.custom_image) ? 1 : 0

  name        = "${var.name}-install-python-dependencies"
  description = "Component to install extra python dependencies for odoo in ${var.name}"
  platform    = "Linux"
  version     = "1.0.0"
  tags        = var.tags

  data = templatefile("${path.module}/image_builder/install_python_dependencies.yaml", {
    source = "${module.s3_bucket[0].s3_bucket_id}/${local.requirements_file_object}"
  })
}

resource "aws_imagebuilder_container_recipe" "odoo_container" {
  count = (local.custom_image) ? 1 : 0

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
  count = (local.custom_image) ? 1 : 0

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

  count = (local.custom_image) ? 1 : 0

  name            = "${var.name}-image-builder"
  use_name_prefix = false
  description     = "Image builder for ${var.name} security group"
  vpc_id          = module.vpc.vpc_id
  egress_rules    = ["all-all"]
  tags            = var.tags
}

resource "aws_imagebuilder_distribution_configuration" "odoo_container" {
  count = (local.custom_image) ? 1 : 0

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
  count = (local.custom_image) ? 1 : 0

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
# Rules are created to handle different stages of the automations regarding custom
# modules management.
#
# Custom modules require to watch changes in objects stored in the S3 bucket and
# execute the image builder pipeline and datasync tasks under different scenarios.
#
# In addition, each time a new image is pushed to ECR, the service running odoo in
# ECS must be redeployed.
#
######################################################################################
module "eventbridge_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role"
  version = "~> 5.27"

  count = (local.python_files_length || local.modules_files_length || local.custom_image) ? 1 : 0

  role_name               = "${var.name}-eventbridge"
  role_description        = "IAM role for ${var.name} eventbridge"
  create_role             = true
  create_instance_profile = false
  role_requires_mfa       = false
  trusted_role_services   = ["events.amazonaws.com", "ssm.amazonaws.com"]
  trusted_role_actions    = ["sts:AssumeRole"]
  tags                    = var.tags

  custom_role_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AmazonSSMAutomationRole"
  ]
}
resource "aws_iam_role_policy" "ssm_iam_pass_role" {
  name = "${var.name}-smm-iam-pass-role"
  role = module.eventbridge_role[0].iam_role_name

  policy = templatefile("${path.module}/iam/iam_pass_role.json", {
    arn = module.eventbridge_role[0].iam_role_arn
  })
}

resource "aws_iam_role_policy" "eventbridge_run_tasks_python" {
  count = (local.python_files_length) ? 1 : 0

  name = "${var.name}-eventbridge-run-task-python"
  role = module.eventbridge_role[0].iam_role_name

  policy = templatefile("${path.module}/iam/run_datasync.json", {
    tasks = [aws_datasync_task.sync_python_packages[0].arn]
  })
}

resource "aws_iam_role_policy" "eventbridge_run_tasks_modules" {
  count = (local.modules_files_length) ? 1 : 0

  name = "${var.name}-eventbridge-run-task-modules"
  role = module.eventbridge_role[0].iam_role_name

  policy = templatefile("${path.module}/iam/run_datasync.json", {
    tasks = [aws_datasync_task.sync_modules[0].arn]
  })
}

resource "aws_iam_role_policy" "eventbridge_update_ecs_service" {
  count = (local.custom_image) ? 1 : 0

  name = "${var.name}-eventbridge-update-ecs-service"
  role = module.eventbridge_role[0].iam_role_name

  policy = templatefile("${path.module}/iam/ecs_update_service.json", {
    service = module.ecs_service.id
  })
}

resource "aws_cloudwatch_event_rule" "modules_sync" {
  count = local.modules_files_length ? 1 : 0

  depends_on = [aws_iam_role_policy.eventbridge_run_tasks_modules[0]]

  name        = "${var.name}-modules-sync"
  description = "Sync modules files stored in s3"
  tags        = var.tags

  event_pattern = templatefile("${path.module}/eventbridge/s3_object_prefix_rule.json", {
    bucket = module.s3_bucket[0].s3_bucket_id
    prefix = "modules/"
  })
}

resource "aws_cloudwatch_event_target" "modules_sync" {
  count = local.modules_files_length ? 1 : 0

  rule     = aws_cloudwatch_event_rule.modules_sync[0].name
  arn      = "${replace(aws_ssm_document.datasync[0].arn, "document", "automation-definition")}:$DEFAULT"
  role_arn = module.eventbridge_role[0].iam_role_arn

  input = jsonencode({
    TaskArn = [aws_datasync_task.sync_modules[0].arn]
  })
}

resource "aws_cloudwatch_event_rule" "python_files_sync" {
  count = local.python_files_length ? 1 : 0

  depends_on = [aws_iam_role_policy.eventbridge_run_tasks_python[0]]

  name        = "${var.name}-python-files-sync"
  description = "Sync python files stored in s3"
  tags        = var.tags

  event_pattern = templatefile("${path.module}/eventbridge/s3_object_prefix_rule.json", {
    bucket = module.s3_bucket[0].s3_bucket_id
    prefix = "python/"
  })
}

resource "aws_cloudwatch_event_target" "python_files_sync" {
  count = local.python_files_length ? 1 : 0

  rule     = aws_cloudwatch_event_rule.python_files_sync[0].name
  arn      = "${replace(aws_ssm_document.datasync[0].arn, "document", "automation-definition")}:$DEFAULT"
  role_arn = module.eventbridge_role[0].iam_role_arn

  input = jsonencode({
    TaskArn = [aws_datasync_task.sync_python_packages[0].arn]
  })
}

resource "aws_cloudwatch_event_rule" "ecr_push" {
  count = (local.custom_image) ? 1 : 0

  name        = "${var.name}-ecr-push"
  description = "Replace ECS task on ECR image push"
  tags        = var.tags

  event_pattern = templatefile("${path.module}/eventbridge/ecr_image_push.json", {
    repository = aws_ecr_repository.odoo[0].id
    tag        = "latest"
  })
}

resource "aws_cloudwatch_event_target" "ecr_push" {
  count = (local.custom_image) ? 1 : 0

  rule     = aws_cloudwatch_event_rule.ecr_push[0].name
  arn      = "${replace(aws_ssm_document.ecs_replace_task[0].arn, "document", "automation-definition")}:$DEFAULT"
  role_arn = module.eventbridge_role[0].iam_role_arn

  input = jsonencode({
    Cluster              = [module.ecs_cluster.cluster_name]
    Service              = [module.ecs_service.name]
    AutomationAssumeRole = [module.eventbridge_role[0].iam_role_arn]
  })
}

resource "aws_ssm_document" "datasync" {
  count = (local.modules_files_length || local.python_files_length) ? 1 : 0

  name            = "${var.name}-run-datasync"
  document_format = "YAML"
  document_type   = "Automation"
  content         = file("${path.module}/ssm/run_datasync_task.yaml")
  tags            = var.tags
}

resource "aws_ssm_document" "ecs_replace_task" {
  count = (local.custom_image) ? 1 : 0

  name            = "${var.name}-ecs-replace-task"
  document_format = "YAML"
  document_type   = "Automation"
  content         = file("${path.module}/ssm/replace_ecs_task.yaml")
  tags            = var.tags
}


######################################################################################
# Lambdas
#
# Lambdas to handle different stages of the automations regarding
# modules management.
#
# Custom modules require to watch changes in objects stored in the S3 bucket and
# execute the image builder pipeline. W/ this integration the automation is able to trigger 
# a lambda to execute the pipe to build the desired image.   
######################################################################################
module "lambda_image_builder" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 6.0.0"

  count = (local.custom_image) ? 1 : 0

  description                             = "AWS lambda function that triggers AWS Image Builder Pipeline when an s3 object with prefix requirements.txt is created or modified in ${module.s3_bucket[0].s3_bucket_id}"
  function_name                           = "${var.name}-lambda"
  handler                                 = "image_builder_exec.lambda_handler"
  runtime                                 = "python3.10"
  create_current_version_allowed_triggers = false
  source_path                             = "${path.module}/lambdas/image_builder_exec.py"
  cloudwatch_logs_retention_in_days       = 14
  allowed_triggers = {
    Config = {
      principal  = "s3.amazonaws.com"
      source_arn = module.s3_bucket[0].s3_bucket_arn
    }
  }
  attach_policy_statements = true
  policy_statements = {
    imagebuilder = {
      effect    = "Allow",
      actions   = ["imagebuilder:StartImagePipelineExecution"],
      resources = [aws_imagebuilder_image_pipeline.odoo_container[0].arn]
  } }

  environment_variables = {
    IMG_BUILDER_ARN = aws_imagebuilder_image_pipeline.odoo_container[0].arn
  }
}
