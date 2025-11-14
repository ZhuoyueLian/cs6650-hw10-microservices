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
        c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request", "message": err.Error()})
        return
    }

    // Validate credit card format: XXXX-XXXX-XXXX-XXXX (digits only)
    pattern := `^\d{4}-\d{4}-\d{4}-\d{4}$`
    matched, _ := regexp.MatchString(pattern, req.CreditCardNumber)
    if !matched {
        c.JSON(http.StatusBadRequest, gin.H{"error": "invalid credit card format", "message": "Format must be XXXX-XXXX-XXXX-XXXX"})
        return
    }

    // Simulate authorization: 90% Authorized, 10% Declined
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
