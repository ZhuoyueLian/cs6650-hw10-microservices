package main

import (
	"fmt"
	"math/rand"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
)

// Product represents data about a product.
type Product struct {
	ProductID    int    `json:"product_id"`
	Name         string `json:"name"`
	Category     string `json:"category"`
	Description  string `json:"description"`
	Brand        string `json:"brand"`
	SKU          string `json:"sku"`
	Manufacturer string `json:"manufacturer"`
	CategoryID   int    `json:"category_id"`
	Weight       int    `json:"weight"`
	SomeOtherID  int    `json:"some_other_id"`
}

// products sync.Map to store product data (productID -> Product)
var products sync.Map

// Initialize random seed
func init() {
	rand.Seed(time.Now().UnixNano())
}

// generateProducts creates 100,000 products with varied data
func generateProducts() {
	brands := []string{"Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Zeta", "Eta", "Theta"}
	categories := []string{"Electronics", "Books", "Home", "Sports", "Toys", "Clothing", "Food", "Garden"}

	for i := 1; i <= 100000; i++ {
		product := Product{
			ProductID:    i,
			Name:         fmt.Sprintf("Product %s %d", brands[i%len(brands)], i),
			Category:     categories[i%len(categories)],
			Description:  fmt.Sprintf("Description for product %d", i),
			Brand:        brands[i%len(brands)],
			SKU:          fmt.Sprintf("SKU-%d", i),
			Manufacturer: fmt.Sprintf("Manufacturer-%d", i%100),
			CategoryID:   i % 10,
			Weight:       100 + (i % 1000),
			SomeOtherID:  i * 10,
		}
		products.Store(i, product)
	}

	fmt.Printf("Generated 100,000 products\n")
}

// simulateFailure returns true 50% of the time to simulate service issues
func simulateFailure() bool {
	return rand.Float32() < 0.5
}

func main() {
	// Generate 100,000 products at startup
	generateProducts()

	router := gin.Default()
	router.GET("/health", healthCheck)
	router.GET("/products/:productId", getProductByID)
	router.POST("/products/:productId/details", postProductDetails)
	router.GET("/products/search", searchProducts)

	fmt.Println("⚠️  BAD PRODUCT SERVICE - Returns 503 errors 50% of the time")
	router.Run(":8080")
}

// health check endpoint for load balancer
func healthCheck(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"status": "healthy"})
}

// getProductByID locates the product whose ID matches the id parameter
// MODIFIED: Returns 503 Service Unavailable 50% of the time
func getProductByID(c *gin.Context) {
	// Simulate failure 50% of the time
	if simulateFailure() {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"error":   "service temporarily unavailable",
			"message": "please try again later",
		})
		return
	}

	// Get the id from URL parameter and convert it to int
	idStr := c.Param("productId")

	// Convert string id to int
	idInt, err := strconv.Atoi(idStr)
	if err != nil {
		c.IndentedJSON(http.StatusBadRequest, gin.H{"message": "invalid product ID format"})
		return
	}

	// Look up the product in the sync.Map
	value, exists := products.Load(idInt)

	// If exists, return it with StatusOK
	if exists {
		product := value.(Product)
		c.IndentedJSON(http.StatusOK, product)
	} else {
		c.IndentedJSON(http.StatusNotFound, gin.H{"error": "NOT_FOUND", "message": "product not found"})
	}
}

// postProductDetails adds or updates product details
// MODIFIED: Returns 503 Service Unavailable 50% of the time
func postProductDetails(c *gin.Context) {
	// Simulate failure 50% of the time
	if simulateFailure() {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"error":   "service temporarily unavailable",
			"message": "please try again later",
		})
		return
	}

	// Get productId from URL and convert to int
	idStr := c.Param("productId")

	idInt, err := strconv.Atoi(idStr)
	if err != nil {
		c.IndentedJSON(http.StatusBadRequest, gin.H{"message": "invalid product ID format"})
		return
	}

	// Bind the JSON body to a Product struct
	var newProduct Product
	if err := c.BindJSON(&newProduct); err != nil {
		c.IndentedJSON(http.StatusBadRequest, gin.H{"message": "invalid input data"})
		return
	}

	// Store in the sync.Map using the ID from the URL
	products.Store(idInt, newProduct)

	// Return 204 No Content
	c.Status(http.StatusNoContent)
}

// searchProducts searches through products by name and category
// MODIFIED: Returns 503 Service Unavailable 50% of the time
func searchProducts(c *gin.Context) {
	// Simulate failure 50% of the time
	if simulateFailure() {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"error":   "service temporarily unavailable",
			"message": "please try again later",
		})
		return
	}

	query := c.Query("q")
	if query == "" {
		c.IndentedJSON(http.StatusBadRequest, gin.H{"message": "query parameter 'q' is required"})
		return
	}

	// Convert query to lowercase for case-insensitive matching
	queryLower := strings.ToLower(query)

	var results []Product
	checkedCount := 0
	maxCheck := 100  // Check exactly 100 products
	maxResults := 20 // Return max 20 results

	// Iterate through products using Range and check exactly 100
	products.Range(func(key, value interface{}) bool {
		if checkedCount >= maxCheck {
			return false // Stop iteration
		}
		checkedCount++

		product := value.(Product)

		// Check if query matches name or category (case-insensitive)
		nameLower := strings.ToLower(product.Name)
		categoryLower := strings.ToLower(product.Category)

		if strings.Contains(nameLower, queryLower) || strings.Contains(categoryLower, queryLower) {
			results = append(results, product)
			if len(results) >= maxResults {
				return false // Stop iteration
			}
		}

		return true // Continue iteration
	})

	// Return response
	c.IndentedJSON(http.StatusOK, gin.H{
		"products":    results,
		"total_found": len(results),
		"checked":     checkedCount,
	})
}
