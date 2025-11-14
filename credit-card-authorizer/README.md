# Credit Card Authorizer (CCA)

This is the mock Credit Card Authorizer service used by the Shopping Cart Service.

Endpoints
- GET /health — health check
- POST /authorize — authorizes payments (expects JSON {credit_card_number, amount})

Behavior
- Validates credit card format: `1234-5678-9012-3456` (4 groups of 4 digits separated by dashes).
- Returns 400 Bad Request if format is invalid.
- Simulates processing: 90% Authorized (200 OK), 10% Declined (402 Payment Required).

Run locally (requires Go 1.21+):
```powershell
cd credit-card-authorizer
go mod download
go run main.go
# Service will listen on :8080 by default. Use PORT environment variable to change.
```

Run with Docker Compose
- `docker-compose.yml` in the repo wires this service in as `credit-card-authorizer` on port 8083.

Quick tests (PowerShell)
```powershell
# Healthy
curl http://localhost:8083/health

# Valid card (may return 200 or 402)
curl -Method POST http://localhost:8083/authorize -ContentType 'application/json' -Body '{"credit_card_number":"1234-5678-9012-3456","amount":10.00}'

# Invalid format (returns 400)
curl -Method POST http://localhost:8083/authorize -ContentType 'application/json' -Body '{"credit_card_number":"1234567890123456","amount":10.00}'
```
