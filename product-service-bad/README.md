# Product Service (Bad Version)

This version returns 503 Service Unavailable errors 50% of the time.
Used to demonstrate Load Balancer health checks and routing.

**Key Difference from Normal Product Service:**
- Added `simulateFailure()` function that returns true 50% of the time
- All endpoints (GET, POST, search) check this before processing
- Health check always returns 200 OK (so Load Balancer can detect it)

Port: 8080 (mapped to 8081 on host in docker-compose)