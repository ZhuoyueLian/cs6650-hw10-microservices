package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	amqp "github.com/rabbitmq/amqp091-go"
)

// ShoppingCart represents a customer's shopping cart
type ShoppingCart struct {
	CartID     string     `json:"cart_id"`
	CustomerID string     `json:"customer_id"`
	Items      []CartItem `json:"items"`
	CreatedAt  time.Time  `json:"created_at"`
}

// CartItem represents an item in the cart
type CartItem struct {
	ProductID string `json:"product_id"`
	Quantity  int    `json:"quantity"`
}

// CreateCartRequest for creating a new cart
type CreateCartRequest struct {
	CustomerID string `json:"customer_id" binding:"required"`
}

// AddItemRequest for adding items to cart
type AddItemRequest struct {
	ProductID string `json:"product_id" binding:"required"`
	Quantity  int    `json:"quantity" binding:"required,min=1,max=10000"`
}

// CheckoutRequest for checkout
type CheckoutRequest struct {
	CreditCardNumber string `json:"credit_card_number" binding:"required"`
}

// CCARequest for credit card authorization
type CCARequest struct {
	CreditCardNumber string  `json:"credit_card_number"`
	Amount           float64 `json:"amount"`
}

// CCAResponse from credit card authorizer
type CCAResponse struct {
	Status        string `json:"status"`
	TransactionID string `json:"transaction_id,omitempty"`
	Message       string `json:"message,omitempty"`
}

// WarehouseOrder message to send to warehouse
type WarehouseOrder struct {
	OrderID    string     `json:"order_id"`
	CartID     string     `json:"cart_id"`
	CustomerID string     `json:"customer_id"`
	Items      []CartItem `json:"items"`
	Timestamp  string     `json:"timestamp"`
}

// Global storage for shopping carts (in-memory)
var (
	carts        sync.Map
	rabbitmqCh   *amqp.Channel
	rabbitmqConn *amqp.Connection
)

// Configuration from environment
var (
	serverPort    = getEnv("PORT", "8080")
	rabbitmqURL   = getEnv("RABBITMQ_URL", "amqp://admin:admin123@localhost:5672")
	ccaServiceURL = getEnv("CCA_SERVICE_URL", "http://localhost:8083")
)

func main() {
	// Initialize RabbitMQ connection
	if err := initRabbitMQ(); err != nil {
		log.Fatalf("Failed to initialize RabbitMQ: %v", err)
	}
	defer closeRabbitMQ()

	router := gin.Default()

	// Health check
	router.GET("/health", healthCheck)

	// Shopping cart endpoints
	router.POST("/shopping-carts", createCart)
	router.GET("/shopping-carts/:id", getCart)
	router.POST("/shopping-carts/:id/items", addItemToCart)
	router.POST("/shopping-carts/:id/checkout", checkout)

	log.Printf("Shopping Cart Service starting on port %s", serverPort)
	router.Run(":" + serverPort)
}

// initRabbitMQ establishes connection and channel to RabbitMQ
func initRabbitMQ() error {
	var err error

	// Connect to RabbitMQ with retry logic
	for i := 0; i < 5; i++ {
		rabbitmqConn, err = amqp.Dial(rabbitmqURL)
		if err == nil {
			break
		}
		log.Printf("Failed to connect to RabbitMQ (attempt %d/5): %v", i+1, err)
		time.Sleep(time.Second * 5)
	}
	if err != nil {
		return fmt.Errorf("could not connect to RabbitMQ: %w", err)
	}

	// Create channel
	rabbitmqCh, err = rabbitmqConn.Channel()
	if err != nil {
		return fmt.Errorf("failed to open channel: %w", err)
	}

	// Declare the warehouse orders queue
	_, err = rabbitmqCh.QueueDeclare(
		"warehouse_orders", // queue name
		true,               // durable
		false,              // delete when unused
		false,              // exclusive
		false,              // no-wait
		nil,                // arguments
	)
	if err != nil {
		return fmt.Errorf("failed to declare queue: %w", err)
	}

	log.Println("✓ Connected to RabbitMQ and declared warehouse_orders queue")
	return nil
}

// closeRabbitMQ closes RabbitMQ connections
func closeRabbitMQ() {
	if rabbitmqCh != nil {
		rabbitmqCh.Close()
	}
	if rabbitmqConn != nil {
		rabbitmqConn.Close()
	}
	log.Println("RabbitMQ connections closed")
}

// healthCheck endpoint
func healthCheck(c *gin.Context) {
	health := gin.H{
		"status":      "healthy",
		"rabbitmq":    "disconnected",
		"carts_count": 0,
	}

	// Check RabbitMQ connection
	if rabbitmqConn != nil && !rabbitmqConn.IsClosed() {
		health["rabbitmq"] = "connected"
	}

	// Count carts
	count := 0
	carts.Range(func(key, value interface{}) bool {
		count++
		return true
	})
	health["carts_count"] = count

	c.JSON(http.StatusOK, health)
}

// createCart creates a new shopping cart
func createCart(c *gin.Context) {
	var req CreateCartRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request body"})
		return
	}

	// Create new cart
	cart := ShoppingCart{
		CartID:     uuid.New().String(),
		CustomerID: req.CustomerID,
		Items:      []CartItem{},
		CreatedAt:  time.Now(),
	}

	// Store in memory
	carts.Store(cart.CartID, cart)

	log.Printf("Created cart %s for customer %s", cart.CartID, cart.CustomerID)
	c.JSON(http.StatusCreated, cart)
}

// getCart retrieves a cart by ID
func getCart(c *gin.Context) {
	cartID := c.Param("id")

	value, exists := carts.Load(cartID)
	if !exists {
		c.JSON(http.StatusNotFound, gin.H{"error": "cart not found"})
		return
	}

	cart := value.(ShoppingCart)
	c.JSON(http.StatusOK, cart)
}

// addItemToCart adds an item to the shopping cart
func addItemToCart(c *gin.Context) {
	cartID := c.Param("id")

	var req AddItemRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request body"})
		return
	}

	// Load cart
	value, exists := carts.Load(cartID)
	if !exists {
		c.JSON(http.StatusNotFound, gin.H{"error": "cart not found"})
		return
	}

	cart := value.(ShoppingCart)

	// Check if item already exists in cart
	found := false
	for i := range cart.Items {
		if cart.Items[i].ProductID == req.ProductID {
			cart.Items[i].Quantity += req.Quantity
			found = true
			break
		}
	}

	// If not found, add new item
	if !found {
		cart.Items = append(cart.Items, CartItem(req))
	}

	// Store updated cart
	carts.Store(cartID, cart)

	log.Printf("Added %d x %s to cart %s", req.Quantity, req.ProductID, cartID)
	c.JSON(http.StatusOK, cart)
}

// checkout processes checkout with CCA authorization and warehouse notification
func checkout(c *gin.Context) {
	cartID := c.Param("id")

	var req CheckoutRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request body"})
		return
	}

	// Load cart
	value, exists := carts.Load(cartID)
	if !exists {
		c.JSON(http.StatusNotFound, gin.H{"error": "cart not found"})
		return
	}

	cart := value.(ShoppingCart)

	// Validate cart is not empty
	if len(cart.Items) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "cannot checkout empty cart"})
		return
	}

	log.Printf("Processing checkout for cart %s", cartID)

	// Step 1: Authorize payment with Credit Card Authorizer
	amount := calculateTotal(cart.Items)
	ccaReq := CCARequest{
		CreditCardNumber: req.CreditCardNumber,
		Amount:           amount,
	}

	ccaResp, err := authorizePayment(ccaReq)
	if err != nil {
		log.Printf("CCA authorization failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "payment authorization failed",
			"message": err.Error(),
		})
		return
	}

	// Check if payment was declined
	if ccaResp.Status != "Authorized" {
		log.Printf("Payment declined for cart %s", cartID)
		c.JSON(http.StatusPaymentRequired, gin.H{
			"error":   "payment declined",
			"message": ccaResp.Message,
		})
		return
	}

	log.Printf("✓ Payment authorized for cart %s", cartID)

	// Step 2: Send order to warehouse via RabbitMQ
	orderID := uuid.New().String()
	order := WarehouseOrder{
		OrderID:    orderID,
		CartID:     cartID,
		CustomerID: cart.CustomerID,
		Items:      cart.Items,
		Timestamp:  time.Now().Format(time.RFC3339),
	}

	if err := publishToWarehouse(order); err != nil {
		log.Printf("Failed to send order to warehouse: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":   "failed to send order to warehouse",
			"message": err.Error(),
		})
		return
	}

	log.Printf("✓ Order %s sent to warehouse for cart %s", orderID, cartID)

	// Step 3: Clear the cart (checkout successful)
	carts.Delete(cartID)

	// Return success response
	c.JSON(http.StatusOK, gin.H{
		"message":              "checkout successful",
		"order_id":             orderID,
		"authorization_status": "Authorized",
		"transaction_id":       ccaResp.TransactionID,
		"total_amount":         amount,
	})
}

// authorizePayment calls the Credit Card Authorizer service
func authorizePayment(req CCARequest) (*CCAResponse, error) {
	jsonData, err := json.Marshal(req)
	if err != nil {
		return nil, fmt.Errorf("failed to marshal request: %w", err)
	}

	// Make HTTP POST request to CCA
	resp, err := http.Post(
		ccaServiceURL+"/authorize",
		"application/json",
		bytes.NewBuffer(jsonData),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to call CCA service: %w", err)
	}
	defer resp.Body.Close()

	// Parse response
	var ccaResp CCAResponse
	if err := json.NewDecoder(resp.Body).Decode(&ccaResp); err != nil {
		return nil, fmt.Errorf("failed to decode CCA response: %w", err)
	}

	// Check for declined payment (402) or bad request (400)
	if resp.StatusCode == http.StatusPaymentRequired {
		return &ccaResp, nil // Return response with Declined status
	}
	if resp.StatusCode == http.StatusBadRequest {
		return nil, fmt.Errorf("invalid credit card format: %s", ccaResp.Message)
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("CCA service returned status %d", resp.StatusCode)
	}

	return &ccaResp, nil
}

// publishToWarehouse publishes order message to RabbitMQ
func publishToWarehouse(order WarehouseOrder) error {
	jsonData, err := json.Marshal(order)
	if err != nil {
		return fmt.Errorf("failed to marshal order: %w", err)
	}

	// Publish message to queue
	err = rabbitmqCh.Publish(
		"",                 // exchange
		"warehouse_orders", // routing key (queue name)
		false,              // mandatory
		false,              // immediate
		amqp.Publishing{
			DeliveryMode: amqp.Persistent, // Persistent message
			ContentType:  "application/json",
			Body:         jsonData,
		},
	)
	if err != nil {
		return fmt.Errorf("failed to publish message: %w", err)
	}

	return nil
}

// calculateTotal calculates total amount (mock - $10 per item for simplicity)
func calculateTotal(items []CartItem) float64 {
	total := 0.0
	for _, item := range items {
		total += float64(item.Quantity) * 10.0 // $10 per item
	}
	return total
}

// getEnv gets environment variable with default
func getEnv(key, defaultValue string) string {
	value := os.Getenv(key)
	if value == "" {
		return defaultValue
	}
	return value
}
