package main

import (
	"encoding/json"
	"fmt"
	"log"
	"os"
	"os/signal"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	amqp "github.com/rabbitmq/amqp091-go"
)

// WarehouseOrder represents an order message from the shopping cart service
type WarehouseOrder struct {
	OrderID    string     `json:"order_id"`
	CartID     string     `json:"cart_id"`
	CustomerID string     `json:"customer_id"`
	Items      []CartItem `json:"items"`
	Timestamp  string     `json:"timestamp"`
}

// CartItem represents an item in the order
type CartItem struct {
	ProductID string `json:"product_id"`
	Quantity  int    `json:"quantity"`
}

// Thread-safe counters
var (
	totalOrders  int64                    // Total number of orders processed
	productQty   = make(map[string]int64) // ProductID -> quantity (protected by productMutex)
	productMutex sync.Mutex               // Mutex to protect productQty map
	numWorkers   = 10                     // Number of worker goroutines for processing messages
)

// Configuration from environment
var (
	rabbitmqURL = getEnv("RABBITMQ_URL", "amqp://admin:admin123@localhost:5672")
	queueName   = "warehouse_orders"
)

func main() {
	log.Println("Warehouse Service starting...")

	// Connect to RabbitMQ
	conn, err := connectRabbitMQ()
	if err != nil {
		log.Fatalf("Failed to connect to RabbitMQ: %v", err)
	}
	defer conn.Close()
	log.Println("✓ Connected to RabbitMQ")

	// Create channel for consuming
	ch, err := conn.Channel()
	if err != nil {
		log.Fatalf("Failed to open channel: %v", err)
	}
	defer ch.Close()

	// Declare queue (in case it doesn't exist yet)
	_, err = ch.QueueDeclare(
		queueName, // queue name
		true,      // durable
		false,     // delete when unused
		false,     // exclusive
		false,     // no-wait
		nil,       // arguments
	)
	if err != nil {
		log.Fatalf("Failed to declare queue: %v", err)
	}

	// Set QoS to prefetch messages (helps with load balancing across workers)
	// Prefetch count of 1 ensures fair distribution among workers
	err = ch.Qos(
		1,     // prefetch count
		0,     // prefetch size
		false, // global
	)
	if err != nil {
		log.Fatalf("Failed to set QoS: %v", err)
	}

	// Start consuming messages
	msgs, err := ch.Consume(
		queueName, // queue
		"",        // consumer tag (empty = auto-generate)
		false,     // auto-ack (false = manual acknowledgements)
		false,     // exclusive
		false,     // no-local
		false,     // no-wait
		nil,       // args
	)
	if err != nil {
		log.Fatalf("Failed to register consumer: %v", err)
	}

	log.Printf("✓ Started consuming from queue: %s", queueName)
	log.Printf("✓ Started %d worker goroutines for message processing", numWorkers)

	// Start worker goroutines
	var wg sync.WaitGroup
	messageChan := make(chan amqp.Delivery, numWorkers*2) // Buffered channel for messages

	// Message distributor: receives from RabbitMQ and distributes to workers
	wg.Add(1)
	go func() {
		defer wg.Done()
		for msg := range msgs {
			messageChan <- msg
		}
		close(messageChan)
	}()

	// Worker goroutines: process messages in parallel
	for i := 0; i < numWorkers; i++ {
		wg.Add(1)
		workerID := i
		go func() {
			defer wg.Done()
			processMessages(workerID, messageChan)
		}()
	}

	// Wait for interrupt signal
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)

	<-sigChan
	log.Println("\nShutting down warehouse service...")

	// Stop consuming (this will close the msgs channel)
	ch.Cancel("", false)

	// Wait for all workers to finish processing current messages
	log.Println("Waiting for workers to finish processing...")
	wg.Wait()

	// Print statistics
	printStatistics()
	log.Println("Warehouse service stopped")
}

// connectRabbitMQ connects to RabbitMQ with retry logic
func connectRabbitMQ() (*amqp.Connection, error) {
	var conn *amqp.Connection
	var err error

	// Retry connection with exponential backoff
	for i := 0; i < 5; i++ {
		conn, err = amqp.Dial(rabbitmqURL)
		if err == nil {
			return conn, nil
		}
		log.Printf("Failed to connect to RabbitMQ (attempt %d/5): %v", i+1, err)
		if i < 4 {
			time.Sleep(time.Second * time.Duration(1<<uint(i))) // Exponential backoff: 1s, 2s, 4s, 8s
		}
	}

	return nil, fmt.Errorf("could not connect to RabbitMQ after 5 attempts: %w", err)
}

// processMessages processes messages from the channel
func processMessages(workerID int, messageChan <-chan amqp.Delivery) {
	for msg := range messageChan {
		// Parse the order message
		var order WarehouseOrder
		if err := json.Unmarshal(msg.Body, &order); err != nil {
			log.Printf("[Worker %d] Failed to unmarshal order: %v", workerID, err)
			// Reject message and don't requeue (malformed message)
			msg.Nack(false, false)
			continue
		}

		// Process the order: update counters
		processOrder(&order)

		// Acknowledge message (manual acknowledgement as required)
		if err := msg.Ack(false); err != nil {
			log.Printf("[Worker %d] Failed to acknowledge message: %v", workerID, err)
		} else {
			log.Printf("[Worker %d] Processed order %s (Cart: %s)", workerID, order.OrderID, order.CartID)
		}
	}
	log.Printf("[Worker %d] Stopped processing messages", workerID)
}

// processOrder updates the order and product quantity counters (thread-safe)
func processOrder(order *WarehouseOrder) {
	// Increment total orders count (atomic operation)
	atomic.AddInt64(&totalOrders, 1)

	// Update quantity for each product in the order
	for _, item := range order.Items {
		// Use mutex to protect read-modify-write operation
		// This ensures atomicity when updating product quantities
		productMutex.Lock()
		productQty[item.ProductID] += int64(item.Quantity)
		productMutex.Unlock()
	}
}

// printStatistics prints the total number of orders and product quantities
func printStatistics() {
	separator := strings.Repeat("=", 50)
	fmt.Println("\n" + separator)
	fmt.Println("WAREHOUSE SERVICE STATISTICS")
	fmt.Println(separator)
	fmt.Printf("Total Orders Processed: %d\n", atomic.LoadInt64(&totalOrders))
	fmt.Println(separator)
	// Note: We don't print product quantities as per requirements
	// (it would be very long with many products)
}

// getEnv gets environment variable with default value
func getEnv(key, defaultValue string) string {
	value := os.Getenv(key)
	if value == "" {
		return defaultValue
	}
	return value
}
