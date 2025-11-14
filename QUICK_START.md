# Quick Start Guide - CS6650 Homework 10

## Overview

This guide helps you get started with the Microservices Extravaganza project. All services are implemented in Go.

## Prerequisites

- Go 1.21 or later
- Docker and Docker Compose
- Git
- Terminal/Command line

## Repository Structure
```
cs6650-hw10-microservices/
├── product-service/              # From hw6 (ready)
├── product-service-bad/          # 503 error version (ready)
├── shopping-cart-service/        # Shopping cart + checkout (ready)
├── credit-card-authorizer/       # Teammate 1 (to implement)
├── warehouse-service/            # Teammate 2 (to implement)
├── docker-compose.yml
├── INTEGRATION_SPECS.md
└── QUICK_START.md
```

## Quick Setup (5 minutes)

### 1. Clone the Repository
```bash
git clone https://github.com/[your-username]/cs6650-hw10-microservices
cd cs6650-hw10-microservices
```

### 2. Verify Services

Check which services are ready:
```bash
# Product Service (should exist from hw6)
ls product-service/

# Shopping Cart Service (should exist)
ls shopping-cart-service/

# CCA and Warehouse (teammates need to create these)
ls credit-card-authorizer/
ls warehouse-service/
```

### 3. Download Dependencies

For each Go service:
```bash
# Product Service
cd product-service && go mod download && cd ..

# Shopping Cart Service
cd shopping-cart-service && go mod download && cd ..

# Do the same for other services when they're ready
```

## Running Services Locally

### Option 1: Individual Services (for development)

**Start RabbitMQ:**
```bash
docker run -d --name rabbitmq \
  -p 5672:5672 -p 15672:15672 \
  -e RABBITMQ_DEFAULT_USER=admin \
  -e RABBITMQ_DEFAULT_PASS=admin123 \
  rabbitmq:3-management
```

**Start Product Service:**
```bash
cd product-service
go run main.go
# Runs on http://localhost:8080
```

**Start Shopping Cart Service:**
```bash
cd shopping-cart-service
export RABBITMQ_URL=amqp://admin:admin123@localhost:5672
export CCA_SERVICE_URL=http://localhost:8083
go run main.go
# Runs on http://localhost:8082
```

### Option 2: Docker Compose (recommended for testing)
```bash
# Start all services
docker-compose up --build

# Or start specific services
docker-compose up rabbitmq product-service shopping-cart-service

# View logs
docker-compose logs -f shopping-cart-service

# Stop all services
docker-compose down
```

## Testing Your Services

### Test Product Service
```bash
# Health check
curl http://localhost:8080/health

# Get product
curl http://localhost:8080/products/1
```

### Test Shopping Cart Service
```bash
# Health check
curl http://localhost:8082/health

# Create cart
curl -X POST http://localhost:8082/shopping-carts \
  -H "Content-Type: application/json" \
  -d '{"customer_id":"TEST-001"}'

# Add item to cart (replace CART_ID)
curl -X POST http://localhost:8082/shopping-carts/CART_ID/items \
  -H "Content-Type: application/json" \
  -d '{"product_id":"PROD-001","quantity":2}'

# Get cart
curl http://localhost:8082/shopping-carts/CART_ID
```

### Test Full Checkout Flow (requires all services)

Use the automated test script:
```bash
# Make it executable
chmod +x test-shopping-cart.sh

# Run tests
./test-shopping-cart.sh
```

## For Teammates

### Teammate 1: Credit Card Authorizer

**See detailed implementation in [INTEGRATION_SPECS.md](INTEGRATION_SPECS.md#for-teammate-1-credit-card-authorizer-cca)**

Quick checklist:
- [ ] Create `credit-card-authorizer/main.go`
- [ ] Create `credit-card-authorizer/go.mod`
- [ ] Create `credit-card-authorizer/Dockerfile`
- [ ] Implement `POST /authorize` endpoint
- [ ] Validate credit card format: `XXXX-XXXX-XXXX-XXXX`
- [ ] Return 90% Authorized, 10% Declined
- [ ] Test with curl

### Teammate 2: Warehouse Service

**See detailed implementation in [INTEGRATION_SPECS.md](INTEGRATION_SPECS.md#for-teammate-2-warehouse-service)**

Quick checklist:
- [ ] Create `warehouse-service/main.go`
- [ ] Create `warehouse-service/go.mod`
- [ ] Create `warehouse-service/Dockerfile`
- [ ] Consume from `warehouse_orders` queue
- [ ] Use manual acknowledgements
- [ ] Track statistics (orders and product counts)
- [ ] Print stats on shutdown (Ctrl+C)

## Accessing Services

| Service | URL | Credentials |
|---------|-----|-------------|
| Product Service | http://localhost:8080 | N/A |
| Bad Product Service | http://localhost:8081 | N/A |
| Shopping Cart | http://localhost:8082 | N/A |
| CCA | http://localhost:8083 | N/A |
| RabbitMQ Management | http://localhost:15672 | admin/admin123 |

## Common Issues

### RabbitMQ Not Starting
```bash
# Check if port is in use
lsof -i :5672

# Remove old container
docker rm -f rabbitmq

# Start fresh
docker run -d --name rabbitmq \
  -p 5672:5672 -p 15672:15672 \
  -e RABBITMQ_DEFAULT_USER=admin \
  -e RABBITMQ_DEFAULT_PASS=admin123 \
  rabbitmq:3-management
```

### Service Won't Build
```bash
# Clean go modules
cd [service-directory]
rm go.sum
go mod tidy
go mod download
```

### Docker Build Fails
```bash
# Clean docker
docker-compose down
docker system prune -f

# Rebuild
docker-compose up --build
```

## Development Workflow

1. **Individual Development**: Each person works on their service locally
2. **Commit Often**: Push your changes regularly
3. **Test Integration**: Use docker-compose to test all services together
4. **Code Review**: Create PRs for major changes
5. **AWS Deployment**: We'll do this together in Week 3

## Next Steps

- [ ] All: Verify services run individually
- [ ] All: Test with docker-compose
- [ ] Week 2: Integration testing
- [ ] Week 3: AWS deployment with Terraform
- [ ] Week 3: Load Balancer configuration
- [ ] Week 3: Final load testing
- [ ] Week 3: Write report

## Getting Help

1. Check [INTEGRATION_SPECS.md](INTEGRATION_SPECS.md) for API details
2. Look at service READMEs in each directory
3. Create GitHub issue with `help-wanted` label
4. Ask in team chat
