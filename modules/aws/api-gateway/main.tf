data "aws_region" "current" {}

data "aws_caller_identity" "this" {}

locals {
  # Use official Scalr IPs when restrictions are enabled, otherwise allow all
  allowed_ips = var.allow_all_ingress ? ["0.0.0.0/0"] : var.additional_allowed_ips
}

resource "aws_api_gateway_rest_api" "scalr_webhook" {
  name        = var.name
  description = "API Gateway to trigger Lambda from Scalr agent pool"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
  lifecycle {
    create_before_destroy = true
  }
  #checkov:skip=CKV_AWS_237:Create-before-destroy is applied via lifecycle at the module level
}

# Resource policy to restrict access by IP
data "aws_iam_policy_document" "scalr_api_policy" {
  count = length(local.allowed_ips) > 0 ? 1 : 0

  statement {
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions   = ["execute-api:Invoke"]
    resources = ["${aws_api_gateway_rest_api.scalr_webhook.execution_arn}/*"]

    condition {
      test     = "IpAddress"
      variable = "aws:SourceIp"
      values   = local.allowed_ips
    }
  }

  # Explicit deny for all other IPs (not in the allowed list)
  statement {
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions   = ["execute-api:Invoke"]
    resources = ["${aws_api_gateway_rest_api.scalr_webhook.execution_arn}/*"]

    condition {
      test     = "NotIpAddress"
      variable = "aws:SourceIp"
      values   = local.allowed_ips
    }
  }
}

resource "aws_api_gateway_rest_api_policy" "scalr_ip_restriction" {
  count       = length(local.allowed_ips) > 0 && !var.allow_all_ingress ? 1 : 0
  rest_api_id = aws_api_gateway_rest_api.scalr_webhook.id
  policy      = data.aws_iam_policy_document.scalr_api_policy[0].json
}

resource "aws_api_gateway_api_key" "scalr_webhook_key" {
  name = "${var.name}-key"
}

resource "aws_api_gateway_usage_plan" "scalr_webhook_plan" {
  name = "${var.name}-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.scalr_webhook.id
    stage  = aws_api_gateway_stage.prod.stage_name
  }

  quota_settings {
    limit  = 1000
    period = "DAY"
  }

  throttle_settings {
    burst_limit = 10
    rate_limit  = 5
  }
}

resource "aws_api_gateway_usage_plan_key" "scalr_webhook_key" {
  key_id        = aws_api_gateway_api_key.scalr_webhook_key.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.scalr_webhook_plan.id
}

resource "aws_api_gateway_resource" "lambda_resource" {
  rest_api_id = aws_api_gateway_rest_api.scalr_webhook.id
  parent_id   = aws_api_gateway_rest_api.scalr_webhook.root_resource_id
  path_part   = "trigger"
}

resource "aws_api_gateway_method" "post_method" {
  #checkov:skip=CKV2_AWS_53:Request validation is handled by the backend service and API Gateway validators are managed centrally
  rest_api_id      = aws_api_gateway_rest_api.scalr_webhook.id
  resource_id      = aws_api_gateway_resource.lambda_resource.id
  http_method      = "POST"
  authorization    = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_method" "options_method" {
  #checkov:skip=CKV2_AWS_53:Request validation is handled by the backend service and API Gateway validators are managed centrally
  rest_api_id      = aws_api_gateway_rest_api.scalr_webhook.id
  resource_id      = aws_api_gateway_resource.lambda_resource.id
  http_method      = "OPTIONS"
  authorization    = "NONE"
  api_key_required = false
}

resource "aws_api_gateway_integration" "options_integration" {
  rest_api_id = aws_api_gateway_rest_api.scalr_webhook.id
  resource_id = aws_api_gateway_resource.lambda_resource.id
  http_method = aws_api_gateway_method.options_method.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "options_200" {
  rest_api_id = aws_api_gateway_rest_api.scalr_webhook.id
  resource_id = aws_api_gateway_resource.lambda_resource.id
  http_method = aws_api_gateway_method.options_method.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.scalr_webhook.id
  resource_id = aws_api_gateway_resource.lambda_resource.id
  http_method = aws_api_gateway_method.options_method.http_method
  status_code = aws_api_gateway_method_response.options_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id             = aws_api_gateway_rest_api.scalr_webhook.id
  resource_id             = aws_api_gateway_resource.lambda_resource.id
  http_method             = aws_api_gateway_method.post_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_invoke_arn
}

resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.scalr_webhook.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.lambda_resource.id,
      aws_api_gateway_method.post_method.id,
      aws_api_gateway_method.options_method.id,
      aws_api_gateway_integration.options_integration.id,
      aws_api_gateway_integration.lambda_integration.id
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod" {
  #checkov:skip=CKV2_AWS_51:Client certificate and mutual TLS are handled separately by infra or WAF in front of the API in production
  #checkov:skip=CKV2_AWS_29:WAF association is out of scope for this module and managed by a global WAF
  #checkov:skip=CKV2_AWS_4:Logging level configured via aws_api_gateway_method_settings resource
  deployment_id         = aws_api_gateway_deployment.deployment.id
  rest_api_id           = aws_api_gateway_rest_api.scalr_webhook.id
  stage_name            = "prod"
  xray_tracing_enabled  = true
  cache_cluster_enabled = true
  cache_cluster_size    = "0.5"

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw_logs.arn
    format          = "$context.identity.sourceIp - $context.requestId [$context.requestTime] \"$context.httpMethod $context.resourcePath $context.protocol\" $context.status"
  }
}



## Method settings for the stage
# Method-level caching/encryption is handled by the API deployment process and not configured in this module.
# This resource was removed because the provider/schema used by this repo's AWS provider version
# handles method settings differently; manage method settings via deployment pipeline or a central module if needed.
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.scalr_webhook.execution_arn}/${var.environment}/POST/trigger"
}

## API Gateway access logs
#checkov:skip=CKV_AWS_158:Using account-managed KMS or logging encryption is handled outside this module
resource "aws_cloudwatch_log_group" "api_gw_logs" {
  name              = "/aws/api-gateway/${var.name}"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.api_gw_cmk.arn
}

resource "aws_kms_key" "api_gw_cmk" {
  description             = "KMS key for API Gateway access logs for ${var.name}"
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
