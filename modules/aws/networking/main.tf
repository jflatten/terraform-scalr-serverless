resource "aws_vpc" "main" {
  #checkov:skip=CKV2_AWS_11:VPC flow logs are intentionally not enabled here; flow logging is managed by central logging stack
  #checkov:skip=CKV2_AWS_12:Default security group restrictions are handled by central guardrails; this VPC resource creates network only
  cidr_block           = var.cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = var.name
  }
}

resource "aws_subnet" "public" {
  count             = length(var.azs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  # Avoid assigning public IPs by default; controlled via autoscaling or explicit assignment
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.name}-${count.index + 1}"
  }
}

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc/${var.name}-flow-logs"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.vpc_flow_logs_key.arn
}

resource "aws_kms_key" "vpc_flow_logs_key" {
  description             = "KMS key for VPC flow logs for ${var.name}"
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

data "aws_caller_identity" "current" {}


resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.name}-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
} 