# Region to deploy into
variable "aws_region" {
  type    = string
  default = "us-west-2"
}

# Base service name
variable "service_name" {
  type    = string
  default = "cs6650-hw10"
}

variable "container_port" {
  type    = number
  default = 8080
}

# Service instance counts
variable "product_service_count" {
  type    = number
  default = 2
  description = "Number of good product service instances"
}

variable "shopping_cart_service_count" {
  type    = number
  default = 2
  description = "Number of shopping cart service instances"
}

variable "cca_service_count" {
  type    = number
  default = 1
  description = "Number of credit card authorizer instances"
}

variable "warehouse_service_count" {
  type    = number
  default = 1
  description = "Number of warehouse service instances"
}

variable "warehouse_workers" {
  type    = number
  default = 10
  description = "Number of worker goroutines per warehouse service instance for processing RabbitMQ messages"
}

variable "rabbitmq_nlb_dns_name" {
  type        = string
  default     = ""
  description = "Manual override: RabbitMQ NLB DNS name (leave empty to use auto-generated NLB DNS). Example: cs6650-hw10-rabbitmq-nlb-xxx.elb.us-west-2.amazonaws.com"
}

# How long to keep logs
variable "log_retention_days" {
  type    = number
  default = 7
}
