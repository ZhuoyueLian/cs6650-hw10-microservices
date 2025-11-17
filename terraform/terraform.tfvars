aws_region = "us-west-2"

project_name = "cs6650-microservices"
environment  = "dev"

# Service scaling
product_service_count       = 2
product_bad_service_count   = 1
shopping_cart_service_count = 2
cca_service_count           = 2
warehouse_service_count     = 1
rabbitmq_service_count      = 1

# Resource allocation
product_service_cpu    = 256
product_service_memory = 512

shopping_cart_cpu    = 256
shopping_cart_memory = 512

cca_cpu    = 256
cca_memory = 512

warehouse_cpu    = 256
warehouse_memory = 512

rabbitmq_cpu    = 512
rabbitmq_memory = 1024

# RabbitMQ credentials
rabbitmq_user     = "admin"
rabbitmq_password = "admin123"

# CloudWatch logs
log_retention_days = 7

# Tags
tags = {
  Project     = "CS6650-hw10"
  Environment = "dev"
  ManagedBy   = "Terraform"
  Course      = "CS6650"
  Assignment  = "Homework10"
}
