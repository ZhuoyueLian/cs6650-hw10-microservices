variable "service_name" {
  type        = string
  description = "Base name for ECS resources"
}

variable "image" {
  type        = string
  description = "ECR image URI (with tag)"
}

variable "container_port" {
  type        = number
  description = "Port your app listens on"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnets for FARGATE tasks"
}

variable "security_group_ids" {
  type        = list(string)
  description = "SGs for FARGATE tasks"
}

variable "execution_role_arn" {
  type        = string
  description = "ECS Task Execution Role ARN"
}

variable "task_role_arn" {
  type        = string
  description = "IAM Role ARN for app permissions"
}

variable "log_group_name" {
  type        = string
  description = "CloudWatch log group name"
}

variable "ecs_count" {
  type        = number
  default     = 1
  description = "Desired Fargate task count"
}

variable "region" {
  type        = string
  description = "AWS region (for awslogs driver)"
}

variable "cpu" {
  type        = string
  default     = "256"
  description = "vCPU units"
}

variable "memory" {
  type        = string
  default     = "512"
  description = "Memory (MiB)"
}

variable "environment_variables" {
  type        = map(string)
  default     = null
  description = "Environment variables for the container"
}

variable "target_group_arn" {
  type        = string
  default     = null
  description = "ARN of target group to attach this service to (optional)"
}

variable "enable_service_discovery" {
  type        = bool
  default     = false
  description = "Whether to enable service discovery for this service"
}

variable "service_discovery_namespace_id" {
  type        = string
  default     = ""
  description = "Service discovery namespace ID for DNS resolution (required if enable_service_discovery = true)"
}

variable "service_discovery_namespace_name" {
  type        = string
  default     = null
  description = "Service discovery namespace name (e.g., cs6650-hw10.local) for DNS resolution"
}
