# Warehouse Service (Go) - CS6650 Homework 10

## Overview

Warehouse Service is a RabbitMQ consumer that processes orders from the Shopping Cart Service. It simulates warehouse operations by consuming order messages asynchronously and tracking order statistics.

**Language**: Go 1.21+  
**Message Queue**: RabbitMQ (AMQP)  
**Queue Name**: `warehouse_orders`

## Features

- Consumes messages from RabbitMQ queue `warehouse_orders`
- Uses **Manual Acknowledgements** as required
- **Multithreaded** message processing (10 worker goroutines by default)
- Thread-safe order and product quantity tracking
- Graceful shutdown with statistics printing
- Automatic reconnection to RabbitMQ with exponential backoff

## Architecture

The service uses a worker pool pattern:
- One main consumer receives messages from RabbitMQ
- Messages are distributed to multiple worker goroutines via a buffered channel
- Workers process messages in parallel and send manual acknowledgements
- All workers share the same RabbitMQ connection but process messages concurrently

## Environment Variables

- `RABBITMQ_URL` - RabbitMQ connection URL (default: `amqp://admin:admin123@localhost:5672`)

## Setup

### Local Development

```bash
cd warehouse-service
go mod download
go run main.go
```

### Docker

```bash
docker build -t warehouse-service .
docker run -e RABBITMQ_URL=amqp://admin:admin123@rabbitmq:5672 warehouse-service
```

### Docker Compose

The service is already configured in the root `docker-compose.yml`:

```bash
docker-compose up warehouse-service
```

## Message Format

The service expects messages in the following JSON format (sent by Shopping Cart Service):

```json
{
  "order_id": "ORDER-12345",
  "cart_id": "CART-67890",
  "customer_id": "CUST-12345",
  "items": [
    {
      "product_id": "PROD-001",
      "quantity": 2
    }
  ],
  "timestamp": "2024-01-01T12:00:00Z"
}
```

## Statistics

When the service shuts down (via SIGTERM or SIGINT), it prints:
- Total number of orders processed

Product-level quantities are tracked internally but not printed (as per requirements, to avoid very long output).

## Thread Safety

The service uses thread-safe data structures to handle concurrent access:
- `sync/atomic` for total order count (lock-free atomic operations)
- Regular `map[string]int64` protected by `sync.Mutex` for product quantity tracking
- Mutex ensures atomic read-modify-write operations when updating product quantities
- All shared data structures are properly synchronized for concurrent access

## Configuration

The number of worker goroutines can be adjusted by modifying the `numWorkers` constant in `main.go` (default: 10).

## Testing

### Quick Test Script

Run the automated test script:

```bash
./test.sh
```

This script will:
1. Check if RabbitMQ and services are running
2. Create a shopping cart and add items
3. Process checkout (sends order to warehouse)
4. Send multiple test orders
5. Provide instructions for viewing logs and statistics

### Manual Testing Steps

#### 1. Start Services

```bash
# Start RabbitMQ and Warehouse Service
docker-compose up rabbitmq warehouse-service -d

# Or start all services
docker-compose up -d
```

#### 2. Check RabbitMQ Management UI

Open http://localhost:15672 in your browser:
- Username: `admin`
- Password: `admin123`
- Navigate to "Queues" tab
- Look for `warehouse_orders` queue
- Monitor message rates and queue length

#### 3. Test Full Integration Flow

Test the complete flow through Shopping Cart Service:

```bash
# 1. Create a shopping cart
CART_ID=$(curl -s -X POST http://localhost:8082/shopping-carts \
  -H "Content-Type: application/json" \
  -d '{"customer_id":"TEST-123"}' | jq -r '.cart_id')

# 2. Add items to cart
curl -X POST http://localhost:8082/shopping-carts/$CART_ID/items \
  -H "Content-Type: application/json" \
  -d '{"product_id":"PROD-001","quantity":2}'

# 3. Checkout (sends order to warehouse)
curl -X POST http://localhost:8082/shopping-carts/$CART_ID/checkout \
  -H "Content-Type: application/json" \
  -d '{"credit_card_number":"1234-5678-9012-3456"}'
```

#### 4. View Warehouse Service Logs

```bash
# Follow logs in real-time
docker logs -f warehouse-service

# You should see messages like:
# [Worker 0] Processed order ORDER-XXX (Cart: CART-XXX)
```

#### 5. Check Statistics on Shutdown

Stop the warehouse service to see statistics:

```bash
docker stop warehouse-service
```

The service will print:
```
==================================================
WAREHOUSE SERVICE STATISTICS
==================================================
Total Orders Processed: X
==================================================
```

### Verify RabbitMQ Queue Status

1. **Via Management UI**: http://localhost:15672
   - Check queue length (should be low/zero if processing correctly)
   - Monitor publish/consume rates
   - Check consumer count (should be 1)

2. **Via Command Line**:
```bash
# Check if queue exists and has messages
docker exec rabbitmq rabbitmqctl list_queues name messages consumers

# Should show:
# warehouse_orders  <message_count>  <consumer_count>
```

### Troubleshooting

**Warehouse service not processing messages:**
- Check RabbitMQ connection: `docker logs warehouse-service | grep RabbitMQ`
- Verify queue exists: Check RabbitMQ Management UI
- Check if messages are in queue: RabbitMQ UI → Queues → warehouse_orders

**Messages piling up in queue:**
- Increase `numWorkers` in `main.go` (default: 10)
- Check warehouse service logs for errors
- Verify workers are acknowledging messages

**Connection errors:**
- Ensure RabbitMQ is running: `docker ps | grep rabbitmq`
- Check RABBITMQ_URL environment variable
- Verify network connectivity in docker-compose

## Dependencies

- `github.com/rabbitmq/amqp091-go` - RabbitMQ client library
