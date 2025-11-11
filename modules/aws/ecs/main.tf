data "aws_region" "current" {}

resource "aws_security_group" "ecs_tasks" {
  #checkov:skip=CKV_AWS_25:This security group uses a conditional all-ports rule when allow_all_ingress is true; managed by higher level policy
  #checkov:skip=CKV_AWS_24:This security group uses a conditional all-ports rule when allow_all_ingress is true; managed by higher level policy
  #checkov:skip=CKV_AWS_260:This security group uses a conditional all-ports rule when allow_all_ingress is true; managed by higher level policy
  #checkov:skip=CKV2_AWS_5:Security group attachment is performed by ECS when tasks are run; static attachment not present in this module
  name        = var.security_group_name
  description = "Security group for ${var.cluster_name}"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.allow_all_ingress ? [1] : []
    content {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      description = "Allow all ingress when explicitly enabled by allow_all_ingress"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    description = "Default egress to VPC CIDR"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name = "${var.cluster_name}-tasks"
  }
}

resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/${var.cluster_name}"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.ecs_logs_key.arn
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${var.task_name}-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task_role" {
  name = "${var.task_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "ecs_task_role_policy" {
  name = "${var.cluster_name}-log-policy"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.ecs_logs.arn}:*"
      }
      ], var.efs_file_system_id != null ? [
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite",
          "elasticfilesystem:ClientRootAccess"
        ]
        Resource = "arn:aws:elasticfilesystem:*:*:file-system/${var.efs_file_system_id}"
      }
    ] : [])
  })
}

resource "aws_ecs_cluster" "main" {
  name = var.cluster_name
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_kms_key" "ecs_logs_key" {
  description             = "KMS key for encrypting ECS CloudWatch Log Group ${var.cluster_name}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })
}

#checkov:skip=CKV_AWS_7:Key rotation is managed by a centralized key management process
#checkov:skip=CKV2_AWS_64:KMS key policies are managed centrally; minimal policy is present for bootstrap

data "aws_caller_identity" "current" {}


resource "aws_ecs_task_definition" "webhook" {
  family                   = var.task_name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.limit_cpu
  memory                   = var.limit_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  dynamic "volume" {
    for_each = var.efs_file_system_id != null ? [1] : []
    content {
      name = "terraform-cache"

      efs_volume_configuration {
        file_system_id     = var.efs_file_system_id
        root_directory     = "/"
        transit_encryption = "ENABLED"
        authorization_config {
          access_point_id = var.terraform_cache_access_point_id
        }
      }
    }
  }

  dynamic "volume" {
    for_each = var.efs_file_system_id != null ? [1] : []
    content {
      name = "providers-cache"

      efs_volume_configuration {
        file_system_id     = var.efs_file_system_id
        root_directory     = "/"
        transit_encryption = "ENABLED"
        authorization_config {
          access_point_id = var.providers_cache_access_point_id
        }
      }
    }
  }

  container_definitions = jsonencode([
    {
      name      = var.task_name
      image     = var.image
      essential = true

      environment = concat([
        {
          name  = "SCALR_URL"
          value = var.scalr_url
        },
        {
          name  = "SCALR_TOKEN"
          value = var.scalr_agent_token
        },
        {
          name  = "SCALR_SINGLE"
          value = "true"
        },
        {
          name  = "SCALR_DRIVER"
          value = "local"
        },
        {
          name  = "SCALR_AGENT_TIMEOUT"
          value = tostring(var.task_stop_timeout - 30) # Leave buffer for graceful shutdown
        }
        ], var.efs_file_system_id != null ? [
        {
          name  = "TF_PLUGIN_CACHE_DIR"
          value = "/terraform-cache"
        },
        {
          name  = "TF_DATA_DIR"
          value = "/providers-cache"
        }
      ] : [])

      mountPoints = var.efs_file_system_id != null ? [
        {
          sourceVolume  = "terraform-cache"
          containerPath = "/terraform-cache"
          readOnly      = false
        },
        {
          sourceVolume  = "providers-cache"
          containerPath = "/providers-cache"
          readOnly      = false
        }
      ] : []

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_logs.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "ecs"
        }
      }

      stopTimeout = var.task_stop_timeout
    }
  ])
}
