# Terraform Infrastructure for CS6650 Homework 10

This Terraform configuration deploys all microservices to AWS ECS with Application Load Balancer (ALB) and Network Load Balancer (NLB).

## Architecture

### Load Balancers
- **Application Load Balancer (ALB)**: Routes HTTP traffic to microservices based on URL patterns
- **Network Load Balancer (NLB)**: Internal TCP load balancer for RabbitMQ AMQP traffic

### ECS Services
- **Product Service**: 2 instances (good) + 1 instance (bad - returns 503 errors 50% of time)
- **Shopping Cart Service**: 2 instances (with sticky sessions enabled)
- **Credit Card Authorizer**: 1 instance
- **Warehouse Service**: 1 instance (configurable worker threads)
- **RabbitMQ**: 1 instance (with management UI)

### Infrastructure Components
- **ECR Repositories**: One per service for Docker images
- **Target Groups**: One per HTTP service type for ALB routing
- **Security Groups**: Separate groups for ALB, services, and RabbitMQ
- **VPC & Networking**: Custom VPC with public subnets for ECS tasks
- **CloudWatch Logs**: Centralized logging for all services

## Services Deployed

1. **Product Service** - Product catalog service (2 good instances)
2. **Product Service Bad** - Returns 503 errors 50% of time (1 instance, for load balancer testing)
3. **Shopping Cart Service** - Manages shopping carts and checkout (2 instances with sticky sessions)
4. **Credit Card Authorizer** - Authorizes credit card payments (1 instance)
5. **Warehouse Service** - Consumes orders from RabbitMQ queue (1 instance, configurable workers)
6. **RabbitMQ** - Message queue for warehouse orders (1 instance with management UI)

## Load Balancer Routing

### Application Load Balancer (ALB)
- `/products*` → Product Service target group (includes both good and bad instances)
- `/shopping-carts*` → Shopping Cart Service target group (with sticky sessions)
- `/authorize*` → Credit Card Authorizer target group

### Network Load Balancer (NLB)
- TCP port 5672 → RabbitMQ target group (internal only)

## Service-to-Service Communication

The infrastructure uses load balancers for service discovery:

- **Shopping Cart → Credit Card Authorizer**: Via ALB DNS name (`http://<alb-dns-name>/authorize`)
- **Shopping Cart → RabbitMQ**: Via NLB DNS name (`amqp://admin:admin123@<nlb-dns-name>:5672`)
- **Warehouse → RabbitMQ**: Via NLB DNS name (`amqp://admin:admin123@<nlb-dns-name>:5672`)

Environment variables are automatically configured with the correct URLs during deployment.

## Usage

### Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.0 installed
- Docker installed (for building images)
- IAM role "LabRole" exists in your AWS account with permissions for:
  - ECS (create clusters, services, tasks)
  - ECR (create repositories, push images)
  - VPC (create VPC, subnets, security groups)
  - ELB (create load balancers, target groups)
  - CloudWatch Logs (create log groups)

### Initial Setup

1. Copy the example variables file:
   ```bash
   cd terraform
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Edit `terraform.tfvars` to customize configuration (optional):
   - Service instance counts
   - AWS region
   - Warehouse workers count
   - RabbitMQ NLB DNS name (if manually setting)

### Deploy

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

**Note**: The first deployment will take 10-15 minutes as it:
- Creates VPC and networking infrastructure
- Creates ECR repositories
- Builds and pushes Docker images for all services
- Deploys ECS services and load balancers

### Outputs

After deployment, Terraform outputs:
- `alb_dns_name`: ALB DNS name (use this to access HTTP services)
- `rabbitmq_nlb_dns_name`: NLB DNS name for RabbitMQ (used internally)
- `alb_arn`: ALB ARN
- Service cluster names
- Target group ARNs

To view outputs:
```bash
terraform output
```

### Access Services

Once deployed, access services via the ALB DNS name:
- `http://<alb-dns-name>/products/123` - Product service
- `http://<alb-dns-name>/shopping-carts` - Shopping cart service
- `http://<alb-dns-name>/authorize` - Credit card authorizer

**RabbitMQ Management UI**:
- Access via RabbitMQ service public IP on port 15672
- Default credentials: `admin` / `admin123`
- Or use port forwarding from ECS task

### Configuration Variables

Edit `terraform.tfvars` or pass via command line to customize:

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | `us-west-2` | AWS region to deploy |
| `service_name` | `cs6650-hw10` | Base name for all resources |
| `product_service_count` | `2` | Number of good product service instances |
| `shopping_cart_service_count` | `2` | Number of shopping cart instances |
| `cca_service_count` | `1` | Number of credit card authorizer instances |
| `warehouse_service_count` | `1` | Number of warehouse service instances |
| `warehouse_workers` | `10` | Worker goroutines per warehouse instance |
| `log_retention_days` | `7` | CloudWatch log retention period |
| `rabbitmq_nlb_dns_name` | `""` | Manual override for RabbitMQ NLB DNS |

Example:
```bash
terraform apply -var="warehouse_workers=20" -var="product_service_count=3"
```

### Destroy

To tear down all infrastructure:
```bash
terraform destroy
```

**Warning**: This will delete all resources including ECR repositories and their images.

## Important Notes

1. **Sticky Sessions**: Shopping Cart Service uses ALB sticky sessions (24-hour cookie) to ensure cart consistency
2. **Service Communication**: All service-to-service communication uses load balancer DNS names (no service discovery needed)
3. **RabbitMQ Security**: RabbitMQ NLB is internal-only. Management UI (port 15672) is open to internet (restrict in production)
4. **Docker Images**: Images are automatically built and pushed to ECR during `terraform apply`
5. **Product Service Bad**: The bad instance is in the same target group as good instances to test load balancer behavior
6. **Warehouse Workers**: Adjust `warehouse_workers` variable to control message processing throughput

## Module Structure

The infrastructure is organized into reusable modules:

- **`modules/network`**: VPC, subnets, internet gateway, security groups
- **`modules/logging`**: CloudWatch Logs log group
- **`modules/ecr`**: ECR repository creation
- **`modules/ecs`**: ECS cluster, service, task definition, and target group integration

## Troubleshooting

### Services Not Responding
1. Check ECS service status: `aws ecs list-services --cluster <cluster-name>`
2. Check task status: `aws ecs list-tasks --cluster <cluster-name>`
3. View CloudWatch logs for errors
4. Verify target group health checks are passing

### RabbitMQ Connection Issues
1. Verify NLB DNS name is correct in service environment variables
2. Check RabbitMQ security group allows traffic from service security group
3. Verify RabbitMQ service is running: `aws ecs describe-services --cluster <cluster-name> --services <service-name>`

### Image Build Failures
1. Ensure Docker is running locally
2. Check Dockerfile exists in each service directory
3. Verify ECR authentication: `aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-west-2.amazonaws.com`

### Load Balancer Issues
1. Check ALB listener rules are configured correctly
2. Verify target groups have healthy targets
3. Check security groups allow traffic on port 80 (ALB) and 5672 (NLB)

### View Logs
```bash
# View logs for a specific service
aws logs tail /aws/ecs/cs6650-hw10 --follow

# View logs for specific service
aws logs tail /aws/ecs/cs6650-hw10 --log-stream-names <stream-name> --follow
```

