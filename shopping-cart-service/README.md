# Shopping Cart Service (Go) - CS6650 Homework 10

## Overview

Shopping Cart Service manages cart operations and coordinates checkout with the Credit Card Authorizer and Warehouse services.

**Language**: Go 1.21+  
**Framework**: Gin  
**Port**: 8080

## API Endpoints

### 1. Health Check
```
GET /health
```

### 2. Create Shopping Cart
```
POST /shopping-carts
Content-Type: application/json

{
  "customer_id": "CUST-12345"
}
```

### 3. Get Shopping Cart
```
GET /shopping-carts/:id
```

### 4. Add Item to Cart
```
POST /shopping-carts/:id/items
Content-Type: application/json

{
  "product_id": "PROD-001",
  "quantity": 2
}
```

### 5. Checkout
```
POST /shopping-carts/:id/checkout
Content-Type: application/json

{
  "credit_card_number": "1234-5678-9012-3456"
}
```

## Setup
```bash
cd shopping-cart-service
go mod download
go run main.go
```

## Environment Variables

- `PORT` - Service port (default: 8080)
- `RABBITMQ_URL` - RabbitMQ connection (default: amqp://admin:admin123@localhost:5672)
- `CCA_SERVICE_URL` - Credit Card Authorizer URL (default: http://localhost:8082)

## Dependencies

- github.com/gin-gonic/gin
- github.com/google/uuid
- github.com/rabbitmq/amqp091-go