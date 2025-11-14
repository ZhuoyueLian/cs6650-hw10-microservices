# CS6650 Homework 10 - Microservices Extravaganza

Team Members: Zhuoyue Lian, Meihao Cheng, Junping Zhu

## Services

- **Product Service** - Manages product catalog (from hw6)
- **Shopping Cart Service** - Cart management and checkout
- **Credit Card Authorizer** - Payment authorization mock
- **Warehouse Service** - Order fulfillment via RabbitMQ

## Quick Start
```bash
# Start all services
docker-compose up --build

# Test the services
./test.sh
```

## Documentation

- [Integration Specs](INTEGRATION_SPECS.md) - API contracts
- [Quick Start](QUICK_START.md) - Setup guide
- Individual service READMEs in each directory