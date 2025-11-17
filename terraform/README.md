# Terraform Infrastructure for CS6650 Homework 10

This Terraform configuration deploys all microservices to AWS ECS with an Application Load Balancer.

## Architecture

- **Application Load Balancer**: Routes traffic to services based on URL patterns
- **ECS Services**: 
  - Product Service (2 instances + 1 bad instance)
  - Shopping Cart Service (2 instances)
  - Credit Card Authorizer (1 instance)
  - Warehouse Service (1 instance)
  - RabbitMQ (1 instance)
- **Target Groups**: One per service type for load balancing
- **ECR Repositories**: One per service for Docker images

## Services Deployed

1. **Product Service** - Product catalog service
2. **Product Service Bad** - Returns 503 errors 50% of time (for load balancer testing)
3. **Shopping Cart Service** - Manages shopping carts and checkout
4. **Credit Card Authorizer** - Authorizes credit card payments
5. **Warehouse Service** - Consumes orders from RabbitMQ
6. **RabbitMQ** - Message queue for warehouse orders

## Load Balancer Routing

- `/products*` → Product Service target group
- `/shopping-carts*` → Shopping Cart Service target group  
- `/authorize*` → Credit Card Authorizer target group

## Service-to-Service Communication

**Note**: Service-to-service communication requires AWS Service Discovery (Cloud Map) or manual configuration. Currently configured with service names as placeholders:

- Shopping Cart → CCA: Uses service name (needs service discovery)
- Shopping Cart → RabbitMQ: Uses service name (needs service discovery)
- Warehouse → RabbitMQ: Uses service name (needs service discovery)

**To enable service discovery**, you'll need to:
1. Create a service discovery namespace
2. Configure ECS services with service discovery
3. Update environment variables to use service discovery DNS names

Alternatively, you can:
- Use the ALB for external-facing services
- Use private IPs (requires dynamic lookup)
- Use a service mesh (more complex)

## Usage

### Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform installed
- Docker installed (for building images)
- IAM role "LabRole" exists in your AWS account

### Deploy

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### Outputs

After deployment, you'll get:
- ALB DNS name (use this to access services)
- ECS cluster names
- Target group ARNs

### Access Services

Once deployed, access services via the ALB DNS name:
- `http://<alb-dns-name>/products/123` - Product service
- `http://<alb-dns-name>/shopping-carts` - Shopping cart service
- `http://<alb-dns-name>/authorize` - Credit card authorizer

### Destroy

```bash
terraform destroy
```

## Configuration

Edit `variables.tf` to customize:
- Service instance counts
- AWS region
- Container resources (CPU/memory)
- Log retention

## Important Notes

1. **Service Discovery**: Internal service communication needs to be configured. See above.
2. **Security Groups**: RabbitMQ security group allows AMQP (5672) from VPC only
3. **Target Groups**: Product service bad instance is in the same target group as good instances for load balancer testing
4. **Docker Images**: Images are built and pushed to ECR during `terraform apply`

## Troubleshooting

- Check ECS service logs in CloudWatch
- Verify security groups allow necessary traffic
- Ensure IAM role "LabRole" has required permissions
- Check target group health checks

