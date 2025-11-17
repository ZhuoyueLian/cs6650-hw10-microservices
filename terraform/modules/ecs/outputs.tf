output "cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.this.name
}

output "service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.this.name
}

output "service_id" {
  description = "ECS service ID"
  value       = aws_ecs_service.this.id
}

output "service_dns_name" {
  description = "Service discovery DNS name (format: service-name.namespace)"
  value       = var.service_discovery_namespace_id != "" ? "${var.service_name}.${var.service_discovery_namespace_name}" : null
}
