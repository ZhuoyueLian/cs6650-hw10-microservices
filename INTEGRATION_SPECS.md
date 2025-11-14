# Integration Specifications for Team Members (Go Implementation)

This document defines the contract between the Shopping Cart Service and the other microservices. All services are implemented in Go.

## Service Ports (Local Development)

| Service | Port |
|---------|------|
| Product Service | 8080 |
| Product Service (Bad) | 8081 |
| Shopping Cart Service | 8082 |
| Credit Card Authorizer | 8083 |
| RabbitMQ AMQP | 5672 |
| RabbitMQ Management UI | 15672 |

---

## For Teammate 1: Credit Card Authorizer (CCA)

### Requirements

The CCA must expose a REST API endpoint that the Shopping Cart Service will call during checkout.

### Endpoint Specification

**POST /authorize**

Request body:
```json
{
  "credit_card_number": "1234-5678-9012-3456",
  "amount": 100.50
}
```

Response (Authorized - 200 OK):
```json
{
  "status": "Authorized",
  "transaction_id": "TXN-12345",
  "message": "Payment authorized successfully"
}
```

Response (Declined - 402 Payment Required):
```json
{
  "status": "Declined",
  "message": "Card declined by issuer"
}
```

Status Codes:
- `200 OK` - Card authorized
- `402 Payment Required` - Card declined
- `400 Bad Request` - Invalid credit card format

### Validation Rules

1. **Credit Card Format**: Must match pattern `XXXX-XXXX-XXXX-XXXX` where X is a digit
2. **Authorization Logic**: 
   - 90% of valid cards should be authorized
   - 10% of valid cards should be declined (randomly)
3. **Invalid Format**: Return 400 with error message

### Complete Example Implementation (Go with Gin)

Create `credit-card-authorizer/main.go`:
```go
package main

import (
	"math/rand"
	"net/http"
	"os"
	"regexp"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

type AuthRequest struct {
	CreditCardNumber string  `json:"credit_card_number" binding:"required"`
	Amount           float64 `json:"amount" binding:"required"`
}

type AuthResponse struct {
	Status        string `json:"status"`
	TransactionID string `json:"transaction_id,omitempty"`
	Message       string `json:"message"`
}

func init() {
	rand.Seed(time.Now().UnixNano())
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	router := gin.Default()
	router.GET("/health", healthCheck)
	router.POST("/authorize", authorizePayment)
	
	router.Run(":" + port)
}

func healthCheck(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"status": "healthy"})
}

func authorizePayment(c *gin.Context) {
	var req AuthRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "invalid request",
			"message": err.Error(),
		})
		return
	}

	// Validate credit card format: XXXX-XXXX-XXXX-XXXX
	pattern := `^\d{4}-\d{4}-\d{4}-\d{4}$`
	matched, _ := regexp.MatchString(pattern, req.CreditCardNumber)
	
	if !matched {
		c.JSON(http.StatusBadRequest, gin.H{
			"error":   "invalid credit card format",
			"message": "Format must be XXXX-XXXX-XXXX-XXXX",
		})
		return
	}

	// 90% authorized, 10% declined
	isAuthorized := rand.Float32() < 0.9

	if isAuthorized {
		c.JSON(http.StatusOK, AuthResponse{
			Status:        "Authorized",
			TransactionID: uuid.New().String(),
			Message:       "Payment authorized successfully",
		})
	} else {
		c.JSON(http.StatusPaymentRequired, AuthResponse{
			Status:  "Declined",
			Message: "Card declined by issuer",
		})
	}
}
```

### go.mod for CCA

Create `credit-card-authorizer/go.mod`:
```
module credit-card-authorizer

go 1.21

require (
	github.com/gin-gonic/gin v1.9.1
	github.com/google/uuid v1.5.0
)
```

### Dockerfile for CCA

Create `credit-card-authorizer/Dockerfile`:
```dockerfile
FROM golang:1.21-alpine AS build
RUN apk add --no-cache git

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -ldflags="-s -w" -o server .

FROM alpine:latest
RUN apk add --no-cache ca-certificates

WORKDIR /app
COPY --from=build /app/server .

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

ENTRYPOINT ["./server"]
```

### Testing Your Service
```bash
# Start the service
cd credit-card-authorizer
go mod download
go run main.go

# Test valid card (should be authorized or declined)
curl -X POST http://localhost:8083/authorize \
  -H "Content-Type: application/json" \
  -d '{"credit_card_number":"1234-5678-9012-3456","amount":100.50}'

# Test invalid format (should return 400)
curl -X POST http://localhost:8083/authorize \
  -H "Content-Type: application/json" \
  -d '{"credit_card_number":"1234567890123456","amount":100.50}'
```

---

## For Teammate 2: Warehouse Service

### Requirements

The Warehouse Service is a **RabbitMQ consumer** that processes orders sent by the Shopping Cart Service.

### Message Queue Configuration

- **Queue Name**: `warehouse_orders`
- **Durability**: true (persistent queue)
- **Message Format**: JSON

### Message Structure
```json
{
  "order_id": "550e8400-e29b-41d4-a716-446655440000",
  "cart_id": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
  "customer_id": "CUST-12345",
  "items": [
    {
      "product_id": "PROD-001",
      "quantity": 2
    },
    {
      "product_id": "PROD-002",
      "quantity": 1
    }
  ],
  "timestamp": "2025-11-13T10:30:00Z"
}
```

### Processing Requirements

1. **Consume messages** from the `warehouse_orders` queue
2. **Manual Acknowledgement**: Use manual acks (not auto-ack)
   - Acknowledge ONLY after recording the order
3. **Track Statistics**:
   - Count total number of orders processed
   - Count quantity of each productId
4. **Thread Safety**: Must handle concurrent messages safely (use mutex)
5. **Shutdown**: Print final statistics when shutting down (Ctrl+C)

### Complete Example Implementation (Go)

Create `warehouse-service/main.go`:
```go
package main

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"

	amqp "github.com/rabbitmq/amqp091-go"
)

type WarehouseOrder struct {
	OrderID    string     `json:"order_id"`
	CartID     string     `json:"cart_id"`
	CustomerID string     `json:"customer_id"`
	Items      []CartItem `json:"items"`
	Timestamp  string     `json:"timestamp"`
}

type CartItem struct {
	ProductID string `json:"product_id"`
	Quantity  int    `json:"quantity"`
}

// Thread-safe statistics
type Stats struct {
	mu            sync.Mutex
	totalOrders   int
	productCounts map[string]int
}

func (s *Stats) addOrder(order WarehouseOrder) {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.totalOrders++
	for _, item := range order.Items {
		s.productCounts[item.ProductID] += item.Quantity
	}
}

func (s *Stats) print() {
	s.mu.Lock()
	defer s.mu.Unlock()

	fmt.Println("\n=== Warehouse Statistics ===")
	fmt.Printf("Total Orders Processed: %d\n", s.totalOrders)
	fmt.Println("Product Counts:")
	for productID, count := range s.productCounts {
		fmt.Printf("  %s: %d\n", productID, count)
	}
}

var stats = Stats{
	productCounts: make(map[string]int),
}

func main() {
	rabbitmqURL := os.Getenv("RABBITMQ_URL")
	if rabbitmqURL == "" {
		rabbitmqURL = "amqp://admin:admin123@localhost:5672"
	}

	// Connect to RabbitMQ with retry
	var conn *amqp.Connection
	var err error
	for i := 0; i < 5; i++ {
		conn, err = amqp.Dial(rabbitmqURL)
		if err == nil {
			break
		}
		log.Printf("Failed to connect to RabbitMQ (attempt %d/5): %v", i+1, err)
		time.Sleep(5 * time.Second)
	}
	if err != nil {
		log.Fatalf("Could not connect to RabbitMQ: %v", err)
	}
	defer conn.Close()

	ch, err := conn.Channel()
	if err != nil {
		log.Fatalf("Failed to open channel: %v", err)
	}
	defer ch.Close()

	// Declare queue
	q, err := ch.QueueDeclare(
		"warehouse_orders", // queue name
		true,               // durable
		false,              // delete when unused
		false,              // exclusive
		false,              // no-wait
		nil,                // arguments
	)
	if err != nil {
		log.Fatalf("Failed to declare queue: %v", err)
	}

	// Set prefetch count for concurrency
	err = ch.Qos(
		10,    // prefetch count
		0,     // prefetch size
		false, // global
	)
	if err != nil {
		log.Fatalf("Failed to set QoS: %v", err)
	}

	// Consume messages
	msgs, err := ch.Consume(
		q.Name, // queue
		"",     // consumer
		false,  // auto-ack (MUST be false for manual ack)
		false,  // exclusive
		false,  // no-local
		false,  // no-wait
		nil,    // args
	)
	if err != nil {
		log.Fatalf("Failed to register consumer: %v", err)
	}

	log.Println("✓ Warehouse waiting for orders...")

	// Handle graceful shutdown
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		<-sigChan
		log.Println("\nShutting down...")
		stats.print()
		os.Exit(0)
	}()

	// Process messages with multiple workers
	var wg sync.WaitGroup
	numWorkers := 10

	for i := 0; i < numWorkers; i++ {
		wg.Add(1)
		go func(workerID int) {
			defer wg.Done()
			for msg := range msgs {
				var order WarehouseOrder
				if err := json.Unmarshal(msg.Body, &order); err != nil {
					log.Printf("Worker %d: Failed to parse order: %v", workerID, err)
					msg.Nack(false, false) // Don't requeue bad messages
					continue
				}

				log.Printf("Worker %d: Processing order %s", workerID, order.OrderID)

				// Update statistics (thread-safe)
				stats.addOrder(order)

				// IMPORTANT: Manual acknowledgement
				msg.Ack(false)

				log.Printf("Worker %d: ✓ Order %s processed", workerID, order.OrderID)
			}
		}(i)
	}

	wg.Wait()
}
```

### go.mod for Warehouse

Create `warehouse-service/go.mod`:
```
module warehouse-service

go 1.21

require (
	github.com/rabbitmq/amqp091-go v1.9.0
)
```

### Dockerfile for Warehouse

Create `warehouse-service/Dockerfile`:
```dockerfile
FROM golang:1.21-alpine AS build
RUN apk add --no-cache git

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -ldflags="-s -w" -o warehouse .

FROM alpine:latest
RUN apk add --no-cache ca-certificates

WORKDIR /app
COPY --from=build /app/warehouse .

ENTRYPOINT ["./warehouse"]
```

### Testing Your Service
```bash
# Start RabbitMQ first
docker run -d --name rabbitmq \
  -p 5672:5672 -p 15672:15672 \
  -e RABBITMQ_DEFAULT_USER=admin \
  -e RABBITMQ_DEFAULT_PASS=admin123 \
  rabbitmq:3-management

# Start warehouse service
cd warehouse-service
go mod download
go run main.go

# In another terminal, manually publish a test message
# Go to http://localhost:15672 (admin/admin123)
# Navigate to Queues → warehouse_orders → Publish message
# Paste this JSON:
{
  "order_id": "TEST-001",
  "cart_id": "CART-001",
  "customer_id": "CUST-001",
  "items": [
    {"product_id": "PROD-001", "quantity": 2}
  ],
  "timestamp": "2025-11-13T10:00:00Z"
}

# You should see the warehouse service process it!
# Press Ctrl+C to see statistics
```

---

## Testing End-to-End Flow

Once all services are implemented:
```bash
# Start all services
docker-compose up --build

# Create a cart
CART_ID=$(curl -s -X POST http://localhost:8082/shopping-carts \
  -H "Content-Type: application/json" \
  -d '{"customer_id":"TEST-123"}' | jq -r '.cart_id')

# Add items
curl -X POST http://localhost:8082/shopping-carts/$CART_ID/items \
  -H "Content-Type: application/json" \
  -d '{"product_id":"PROD-001","quantity":2}'

# Checkout
curl -X POST http://localhost:8082/shopping-carts/$CART_ID/checkout \
  -H "Content-Type: application/json" \
  -d '{"credit_card_number":"1234-5678-9012-3456"}'

# Check RabbitMQ UI to see message was sent to warehouse
# Open http://localhost:15672

# Check warehouse service logs to see order processed
docker logs warehouse-service
```
