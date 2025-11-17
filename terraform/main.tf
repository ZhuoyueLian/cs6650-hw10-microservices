# Microservices Infrastructure for CS6650 Homework 10
# Deploys: Product Service, Shopping Cart Service, Credit Card Authorizer, Warehouse Service, Product Service Bad
# Includes: Application Load Balancer, RabbitMQ, ECS services

# Network infrastructure
module "network" {
  source         = "./modules/network"
  service_name   = var.service_name
  container_port = var.container_port
}

# Shared logging
module "logging" {
  source            = "./modules/logging"
  service_name      = var.service_name
  retention_in_days = var.log_retention_days
}

# Reuse an existing IAM role for ECS tasks
data "aws_iam_role" "lab_role" {
  name = "LabRole"
}

# ECR Repositories for each service
module "ecr_product" {
  source          = "./modules/ecr"
  repository_name = "${var.service_name}-product-service"
}

module "ecr_product_bad" {
  source          = "./modules/ecr"
  repository_name = "${var.service_name}-product-service-bad"
}

module "ecr_shopping_cart" {
  source          = "./modules/ecr"
  repository_name = "${var.service_name}-shopping-cart-service"
}

module "ecr_cca" {
  source          = "./modules/ecr"
  repository_name = "${var.service_name}-credit-card-authorizer"
}

module "ecr_warehouse" {
  source          = "./modules/ecr"
  repository_name = "${var.service_name}-warehouse-service"
}

module "ecr_rabbitmq" {
  source          = "./modules/ecr"
  repository_name = "${var.service_name}-rabbitmq"
}

# Security group for RabbitMQ (AMQP port 5672, Management UI 15672)
resource "aws_security_group" "rabbitmq" {
  name        = "${var.service_name}-rabbitmq-sg"
  description = "Security group for RabbitMQ"
  vpc_id      = module.network.vpc_id

  # Allow from other services (using security group reference)
  ingress {
    from_port       = 5672
    to_port         = 5672
    protocol        = "tcp"
    security_groups = [module.network.security_group_id]
    description     = "RabbitMQ AMQP from other services"
  }

  # Allow from VPC CIDR (for NLB health checks - NLB uses VPC IPs)
  ingress {
    from_port   = 5672
    to_port     = 5672
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8", "172.31.0.0/16"] # Allow from VPC and private subnets
    description = "RabbitMQ AMQP from VPC (NLB health checks)"
  }

  ingress {
    from_port   = 15672
    to_port     = 15672
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Management UI (restrict in production)
    description = "RabbitMQ Management UI"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }
}

# Network Load Balancer for RabbitMQ (TCP/AMQP)
resource "aws_lb" "rabbitmq" {
  name               = "${var.service_name}-rabbitmq-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = module.network.subnet_ids

  enable_deletion_protection = false
}

# Target Group for RabbitMQ
resource "aws_lb_target_group" "rabbitmq" {
  name     = "${var.service_name}-rabbitmq-tg"
  port     = 5672
  protocol = "TCP"
  vpc_id   = module.network.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 10
    interval            = 30
    protocol            = "TCP"
  }
}

# NLB Listener for RabbitMQ
resource "aws_lb_listener" "rabbitmq" {
  load_balancer_arn = aws_lb.rabbitmq.arn
  port              = "5672"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.rabbitmq.arn
  }
}

# RabbitMQ ECS Service
module "rabbitmq" {
  source                         = "./modules/ecs"
  service_name                   = "${var.service_name}-rabbitmq"
  image                          = "rabbitmq:3-management"
  container_port                 = 5672
  subnet_ids                     = module.network.subnet_ids
  security_group_ids             = [aws_security_group.rabbitmq.id]
  execution_role_arn             = data.aws_iam_role.lab_role.arn
  task_role_arn                  = data.aws_iam_role.lab_role.arn
  log_group_name                 = module.logging.log_group_name
  ecs_count                      = 1
  region                         = var.aws_region
  cpu                            = "512"
  memory                         = "1024"
  target_group_arn               = aws_lb_target_group.rabbitmq.arn
  environment_variables = {
    RABBITMQ_DEFAULT_USER = "admin"
    RABBITMQ_DEFAULT_PASS = "admin123"
  }
}

# Product Service
module "ecs_product" {
  source             = "./modules/ecs"
  service_name       = "${var.service_name}-product-service"
  image              = "${module.ecr_product.repository_url}:latest"
  container_port     = var.container_port
  subnet_ids         = module.network.subnet_ids
  security_group_ids = [module.network.security_group_id]
  execution_role_arn    = data.aws_iam_role.lab_role.arn
  task_role_arn     = data.aws_iam_role.lab_role.arn
  log_group_name    = module.logging.log_group_name
  ecs_count         = var.product_service_count
  region            = var.aws_region
  target_group_arn  = aws_lb_target_group.product.arn
}

# Product Service Bad (returns 503 errors 50% of time)
module "ecs_product_bad" {
  source             = "./modules/ecs"
  service_name       = "${var.service_name}-product-service-bad"
  image              = "${module.ecr_product_bad.repository_url}:latest"
  container_port     = var.container_port
  subnet_ids         = module.network.subnet_ids
  security_group_ids = [module.network.security_group_id]
  execution_role_arn = data.aws_iam_role.lab_role.arn
  task_role_arn      = data.aws_iam_role.lab_role.arn
  log_group_name     = module.logging.log_group_name
  ecs_count          = 1
  region             = var.aws_region
  target_group_arn   = aws_lb_target_group.product.arn
}

# Credit Card Authorizer Service
module "ecs_cca" {
  source                         = "./modules/ecs"
  service_name                   = "${var.service_name}-credit-card-authorizer"
  image                          = "${module.ecr_cca.repository_url}:latest"
  container_port                 = var.container_port
  subnet_ids                     = module.network.subnet_ids
  security_group_ids             = [module.network.security_group_id]
  execution_role_arn             = data.aws_iam_role.lab_role.arn
  task_role_arn                  = data.aws_iam_role.lab_role.arn
  log_group_name                 = module.logging.log_group_name
  ecs_count                      = var.cca_service_count
  region                         = var.aws_region
  target_group_arn               = aws_lb_target_group.cca.arn
  environment_variables = {
    PORT = "8080"
  }
}

# Shopping Cart Service
module "ecs_shopping_cart" {
  source                         = "./modules/ecs"
  service_name                   = "${var.service_name}-shopping-cart-service"
  image                          = "${module.ecr_shopping_cart.repository_url}:latest"
  container_port                 = var.container_port
  subnet_ids                     = module.network.subnet_ids
  security_group_ids             = [module.network.security_group_id]
  execution_role_arn             = data.aws_iam_role.lab_role.arn
  task_role_arn                  = data.aws_iam_role.lab_role.arn
  log_group_name                 = module.logging.log_group_name
  ecs_count                      = var.shopping_cart_service_count
  region                         = var.aws_region
  target_group_arn               = aws_lb_target_group.shopping_cart.arn
  environment_variables = {
    PORT            = "8080"
    RABBITMQ_URL    = "amqp://admin:admin123@${var.rabbitmq_nlb_dns_name != "" ? var.rabbitmq_nlb_dns_name : aws_lb.rabbitmq.dns_name}:5672"
    CCA_SERVICE_URL = "http://${aws_lb.main.dns_name}"
  }
}

# Warehouse Service
module "ecs_warehouse" {
  source                         = "./modules/ecs"
  service_name                   = "${var.service_name}-warehouse-service"
  image                          = "${module.ecr_warehouse.repository_url}:latest"
  container_port                 = var.container_port
  subnet_ids                     = module.network.subnet_ids
  security_group_ids             = [module.network.security_group_id]
  execution_role_arn             = data.aws_iam_role.lab_role.arn
  task_role_arn                  = data.aws_iam_role.lab_role.arn
  log_group_name                 = module.logging.log_group_name
  ecs_count                      = var.warehouse_service_count
  region                         = var.aws_region
  environment_variables = {
    RABBITMQ_URL      = "amqp://admin:admin123@${var.rabbitmq_nlb_dns_name != "" ? var.rabbitmq_nlb_dns_name : aws_lb.rabbitmq.dns_name}:5672"
    WAREHOUSE_WORKERS = tostring(var.warehouse_workers)
  }
}

# Security Group for ALB (allows HTTP from internet)
resource "aws_security_group" "alb" {
  name        = "${var.service_name}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = module.network.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol     = "tcp"
    cidr_blocks  = ["0.0.0.0/0"]
    description  = "Allow HTTP from internet"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }
}

# Application Load Balancer
# Note: Must be created before target groups and ECS services that reference it
resource "aws_lb" "main" {
  name               = "${var.service_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = module.network.subnet_ids

  enable_deletion_protection = false
}

# Target Group for Product Service (Good instances)
resource "aws_lb_target_group" "product" {
  name     = "${var.service_name}-product-tg"
  port     = var.container_port
  protocol = "HTTP"
  vpc_id   = module.network.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/health"
    matcher             = "200"
  }
}

# Target Group for Shopping Cart Service
resource "aws_lb_target_group" "shopping_cart" {
  name     = "${var.service_name}-shopping-cart-tg"
  port     = var.container_port
  protocol = "HTTP"
  vpc_id   = module.network.vpc_id
  target_type = "ip"

  # Enable sticky sessions (session affinity) so same cart goes to same instance
  stickiness {
    enabled         = true
    type            = "lb_cookie"
    cookie_duration = 86400 # 24 hours
  }

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/health"
    matcher             = "200"
  }
}

# Target Group for Credit Card Authorizer
resource "aws_lb_target_group" "cca" {
  name     = "${var.service_name}-cca-tg"
  port     = var.container_port
  protocol = "HTTP"
  vpc_id   = module.network.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/health"
    matcher             = "200"
  }
}

# Note: Target group attachments are handled automatically by ECS service load_balancer configuration
# We'll integrate target groups directly with ECS services

# ALB Listener
resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "No matching rule"
      status_code  = "404"
    }
  }
}

# Routing Rule: Product Service (URL contains "product")
resource "aws_lb_listener_rule" "product" {
  listener_arn = aws_lb_listener.main.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.product.arn
  }

  condition {
    path_pattern {
      values = ["/products*"]
    }
  }
}

# Routing Rule: Shopping Cart Service (URL contains "shopping-cart")
resource "aws_lb_listener_rule" "shopping_cart" {
  listener_arn = aws_lb_listener.main.arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.shopping_cart.arn
  }

  condition {
    path_pattern {
      values = ["/shopping-carts*"]
    }
  }
}

# Routing Rule: Credit Card Authorizer (URL contains "authorize")
resource "aws_lb_listener_rule" "cca" {
  listener_arn = aws_lb_listener.main.arn
  priority     = 300

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.cca.arn
  }

  condition {
    path_pattern {
      values = ["/authorize*"]
    }
  }
}

# Build & push Docker images for each service
resource "docker_image" "product" {
  name = "${module.ecr_product.repository_url}:latest"
  build {
    context = "../product-service"
  }
}

resource "docker_registry_image" "product" {
  name = docker_image.product.name
}

resource "docker_image" "product_bad" {
  name = "${module.ecr_product_bad.repository_url}:latest"
  build {
    context = "../product-service-bad"
  }
}

resource "docker_registry_image" "product_bad" {
  name = docker_image.product_bad.name
}

resource "docker_image" "shopping_cart" {
  name = "${module.ecr_shopping_cart.repository_url}:latest"
  build {
    context = "../shopping-cart-service"
  }
}

resource "docker_registry_image" "shopping_cart" {
  name = docker_image.shopping_cart.name
}

resource "docker_image" "cca" {
  name = "${module.ecr_cca.repository_url}:latest"
  build {
    context = "../credit-card-authorizer"
  }
}

resource "docker_registry_image" "cca" {
  name = docker_image.cca.name
}

resource "docker_image" "warehouse" {
  name = "${module.ecr_warehouse.repository_url}:latest"
  build {
    context = "../warehouse-service"
  }
}

resource "docker_registry_image" "warehouse" {
  name = docker_image.warehouse.name
}
