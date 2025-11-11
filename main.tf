terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    scalr = {
      source = "scalr/scalr"
    }
  }
}

provider "aws" {
  region = var.aws_region

  assume_role {
    role_arn = "arn:aws:iam::335056907189:role/scalr-access"
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Fetch official Scalr.io IP addresses (independent module)
module "scalr_ips" {
  source = "./modules/common/scalr-ips"
}

module "api_gateway" {
  source = "./modules/aws/api-gateway"

  name                   = var.api_gateway_name
  environment            = var.api_gateway_environment
  additional_allowed_ips = module.scalr_ips.allowed_ips
  allow_all_ingress      = var.allow_all_ingress
  lambda_invoke_arn      = module.lambda.invoke_arn
  lambda_function_name   = module.lambda.function_name
}

module "networking" {
  source = "./modules/aws/networking"

  name                = var.vpc_name
  cidr                = "10.0.0.0/16"
  azs                 = slice(data.aws_availability_zones.available.names, 0, 2)
  public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]
}

module "efs" {
  source = "./modules/aws/efs"

  name       = "${var.vpc_name}-cache"
  vpc_id     = module.networking.vpc_id
  vpc_cidr   = "10.0.0.0/16"
  subnet_ids = module.networking.public_subnet_ids
}

module "lambda" {
  source = "./modules/aws/lambda"

  subnet_ids          = module.networking.public_subnet_ids
  cluster_name        = module.ecs.cluster_name
  task_definition_arn = module.ecs.task_definition_arn
  task_role_arn       = module.ecs.task_role_arn
  security_group_id   = module.ecs.security_group_id
  function_name       = var.lambda_function_name
  handler             = var.lambda_handler
  memory_size         = var.lambda_memory_size
  runtime             = var.lambda_runtime
  source_file         = "${path.module}/lambda_function.py"
  timeout             = var.lambda_timeout
}

module "agent_pool" {
  source = "./modules/scalr/agent-pool"

  webhook_url = module.api_gateway.url
  webhook_headers = [
    {
      name      = "x-api-key"
      value     = module.api_gateway.api_key
      sensitive = true
    },
    {
      name      = "Content-Type"
      value     = "application/json"
      sensitive = false
    }
  ]
}

module "ecs" {
  source            = "./modules/aws/ecs"
  vpc_id            = module.networking.vpc_id
  vpc_cidr          = module.networking.vpc_cidr_block
  allow_all_ingress = var.allow_all_ingress
  limit_cpu         = var.ecs_limit_cpu
  limit_memory      = var.ecs_limit_memory
  image             = var.ecs_image
  cluster_name      = var.ecs_cluster_name
  task_name         = var.ecs_task_name
  scalr_url         = module.agent_pool.scalr_url
  scalr_agent_token = module.agent_pool.agent_token

  security_group_name = var.ecs_security_group_name
  task_stop_timeout   = var.ecs_task_stop_timeout

  # EFS configuration for persistent cache
  efs_file_system_id              = module.efs.file_system_id
  terraform_cache_access_point_id = module.efs.terraform_cache_access_point_id
  providers_cache_access_point_id = module.efs.providers_cache_access_point_id
}
