output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = aws_lb.main.arn
}

output "product_service_cluster" {
  description = "Product service ECS cluster name"
  value       = module.ecs_product.cluster_name
}

output "shopping_cart_service_cluster" {
  description = "Shopping cart service ECS cluster name"
  value       = module.ecs_shopping_cart.cluster_name
}

output "cca_service_cluster" {
  description = "Credit card authorizer ECS cluster name"
  value       = module.ecs_cca.cluster_name
}

output "warehouse_service_cluster" {
  description = "Warehouse service ECS cluster name"
  value       = module.ecs_warehouse.cluster_name
}

output "rabbitmq_service_cluster" {
  description = "RabbitMQ ECS cluster name"
  value       = module.rabbitmq.cluster_name
}

output "target_group_arns" {
  description = "ARNs of all target groups"
  value = {
    product       = aws_lb_target_group.product.arn
    shopping_cart = aws_lb_target_group.shopping_cart.arn
    cca           = aws_lb_target_group.cca.arn
  }
}

output "rabbitmq_nlb_dns_name" {
  description = "Network Load Balancer DNS name for RabbitMQ"
  value       = aws_lb.rabbitmq.dns_name
}
