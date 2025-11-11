# Example Terraform variables configuration
# Copy this to terraform.tfvars and customize for your environment

# AWS Configuration
aws_region = "us-east-2"

# Network Configuration  
vpc_name = "scalr-agent"

# API Gateway Configuration
api_gateway_name        = "scalr-agent-pool-api"
api_gateway_environment = "prod"

# Security Configuration
# Set to false to enable Scalr.io IP restrictions (recommended for production)
# The system automatically uses official IPs from https://scalr.io/.well-known/allowlist.txt
allow_all_ingress = false

# ECS Configuration
ecs_cluster_name        = "scalr-agent-pool-cluster"
ecs_task_name           = "scalr-agent-run"
ecs_limit_cpu           = 2048
ecs_limit_memory        = 4096
ecs_image               = "scalr/agent-runner:latest"
ecs_task_stop_timeout   = 120
ecs_security_group_name = "scalr-agent-ecs-tasks"

# Lambda Configuration
lambda_function_name = "scalr-agent"
lambda_handler       = "lambda_function.lambda_handler"
lambda_runtime       = "python3.13"
lambda_timeout       = 30
lambda_memory_size   = 128