resource "aws_efs_file_system" "cache" {
  creation_token = "${var.name}-cache"

  performance_mode                = "generalPurpose"
  throughput_mode                 = "provisioned"
  provisioned_throughput_in_mibps = var.provisioned_throughput
  encrypted                       = true
  kms_key_id                      = aws_kms_key.efs_cmk.arn

  tags = {
    Name = "${var.name}-cache"
  }
}

resource "aws_efs_mount_target" "cache" {
  count           = length(var.subnet_ids)
  file_system_id  = aws_efs_file_system.cache.id
  subnet_id       = var.subnet_ids[count.index]
  security_groups = [aws_security_group.efs.id]
}

resource "aws_security_group" "efs" {
  name        = "${var.name}-efs-sg"
  description = "Security group for EFS"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    description = "Allow NFS from within VPC"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    description = "Egress restricted to VPC CIDR by default"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name = "${var.name}-efs-sg"
  }
}

resource "aws_kms_key" "efs_cmk" {
  description             = "Customer managed KMS key for encrypting EFS ${var.name}"
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

resource "aws_efs_access_point" "terraform_cache" {
  file_system_id = aws_efs_file_system.cache.id

  root_directory {
    path = "/terraform-cache"

    creation_info {
      owner_gid   = 0
      owner_uid   = 0
      permissions = "755"
    }
  }

  posix_user {
    gid = 0
    uid = 0
  }

  tags = {
    Name = "${var.name}-terraform-cache"
  }
}

resource "aws_efs_access_point" "providers_cache" {
  file_system_id = aws_efs_file_system.cache.id

  root_directory {
    path = "/providers-cache"

    creation_info {
      owner_gid   = 0
      owner_uid   = 0
      permissions = "755"
    }
  }

  posix_user {
    gid = 0
    uid = 0
  }

  tags = {
    Name = "${var.name}-providers-cache"
  }
} 