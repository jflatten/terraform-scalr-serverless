variable "vpc_id" {
  description = "VPC ID where the ECS cluster will be created"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block used for default security rule restrictions"
  type        = string
  default     = "0.0.0.0/0"
}

variable "allow_all_ingress" {
  description = "Whether to allow all ingress traffic"
  type        = bool
  default     = false
}

variable "security_group_name" {
  type        = string
  description = "AWS Security Group name"
}

variable "cluster_name" {
  type        = string
  description = "Name of the ECS cluster"
}

variable "task_name" {
  type        = string
  description = "Name of the ECS task"
}

variable "image" {
  type        = string
  description = "ECS container image"
}

variable "scalr_url" {}
variable "scalr_agent_token" {}

variable "limit_cpu" {
  type        = number
  description = "The hard limit for the cpu unit used by the task"
}

variable "limit_memory" {
  type        = number
  description = "The hard limit for the memory used by the task"
  default     = 2048
}

variable "efs_file_system_id" {
  type        = string
  description = "EFS file system ID for persistent storage"
  default     = null
}

variable "terraform_cache_access_point_id" {
  type        = string
  description = "EFS access point ID for Terraform cache"
  default     = null
}

variable "providers_cache_access_point_id" {
  type        = string
  description = "EFS access point ID for providers cache"
  default     = null
}

variable "task_stop_timeout" {
  type        = number
  description = "Time to wait for the task to stop gracefully before force-killing (in seconds)"
  default     = 120
}
