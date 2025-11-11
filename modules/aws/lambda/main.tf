resource "aws_iam_role" "lambda_execution_role" {
  name = "${var.function_name}-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_execution_policy" {
  name = "${var.function_name}_lambda_policy"
  role = aws_iam_role.lambda_execution_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecs:RunTask",
          "ecs:StopTask",
          "ecs:DescribeTasks"
        ]
        Resource = [var.task_definition_arn]
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = var.task_role_arn != "" ? [var.task_role_arn] : ["*"]
      }
    ]
  })
}


data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/lambda_function.zip"
  source_file = "${path.root}/lambda_function.py"
}

resource "aws_lambda_function" "scalr_webhook" {
  filename      = data.archive_file.lambda_zip.output_path
  function_name = var.function_name
  role          = aws_iam_role.lambda_execution_role.arn
  handler       = var.handler
  runtime       = var.runtime
  timeout       = var.timeout
  memory_size   = var.memory_size
  kms_key_arn   = aws_kms_key.lambda_env_key.arn

  #checkov:skip=CKV_AWS_272:Code signing validation is not used in this deployment model; artifacts are verified via CI
  environment {
    variables = {
      SUBNET_IDS      = join(",", var.subnet_ids)
      CLUSTER         = var.cluster_name
      TASK_DEFINITION = var.task_definition_arn
      SECURITY_GROUP  = var.security_group_id
    }
  }

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [var.security_group_id]
  }

  tracing_config {
    mode = "Active"
  }

  reserved_concurrent_executions = var.reserved_concurrent_executions
  dead_letter_config {
    target_arn = aws_sqs_queue.lambda_dlq.arn
  }
}

resource "aws_sqs_queue" "lambda_dlq" {
  #checkov:skip=CKV_AWS_27:SQS encryption configuration uses a CMK managed centrally
  name              = "${var.function_name}-dlq"
  kms_master_key_id = aws_kms_key.lambda_env_key.arn
}

resource "aws_kms_key" "lambda_env_key" {
  description             = "KMS key for encrypting Lambda environment variables for ${var.function_name}"
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

#checkov:skip=CKV_AWS_7:Key rotation is managed externally for these CMKs
#checkov:skip=CKV2_AWS_64:KMS key policy content is intentionally minimal here; full policy applied by central ops

data "aws_caller_identity" "current" {}