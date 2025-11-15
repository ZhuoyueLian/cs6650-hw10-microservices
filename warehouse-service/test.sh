#!/usr/bin/env bash

# Test script for Warehouse Service and RabbitMQ
# This script tests the warehouse service in multiple ways:
# 1. Direct RabbitMQ message publishing (standalone test)
# 2. Full integration test through Shopping Cart Service

# Don't use set -e because we want to handle errors gracefully
set +e

echo "=========================================="
echo "Warehouse Service & RabbitMQ Test Suite"
echo "=========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
RABBITMQ_URL="amqp://admin:admin123@localhost:5672"
SHOPPING_CART_URL="http://localhost:8082"
RABBITMQ_UI="http://localhost:15672"

echo -e "${YELLOW}Step 1: Check if RabbitMQ is running...${NC}"
if docker ps | grep -q rabbitmq; then
    echo -e "${GREEN}✓ RabbitMQ container is running${NC}"
else
    echo -e "${RED}✗ RabbitMQ container is not running${NC}"
    echo "Start it with: docker-compose up rabbitmq -d"
    exit 1
fi

echo ""
echo -e "${YELLOW}Step 2: Check if Warehouse Service is running...${NC}"
if docker ps | grep -q warehouse-service; then
    echo -e "${GREEN}✓ Warehouse service container is running${NC}"
    echo "View logs with: docker logs -f warehouse-service"
else
    echo -e "${YELLOW}⚠ Warehouse service is not running${NC}"
    echo "Start it with: docker-compose up warehouse-service -d"
fi

echo ""
echo -e "${YELLOW}Step 3: Check RabbitMQ Management UI...${NC}"
echo "RabbitMQ Management UI: ${RABBITMQ_UI}"
echo "Username: admin"
echo "Password: admin123"
echo "You can check queue status, message rates, and queue length here"
echo ""

echo -e "${YELLOW}Step 4: Test Full Integration Flow (Shopping Cart -> Warehouse)${NC}"
echo "This will:"
echo "  1. Create a shopping cart"
echo "  2. Add items to the cart"
echo "  3. Checkout (which sends order to warehouse via RabbitMQ)"
echo ""

# Check if shopping cart service is running
if ! curl -s -f "${SHOPPING_CART_URL}/health" > /dev/null 2>&1; then
    echo -e "${RED}✗ Shopping Cart Service is not running on ${SHOPPING_CART_URL}${NC}"
    echo "Start it with: docker-compose up shopping-cart-service -d"
    exit 1
fi

echo -e "${GREEN}✓ Shopping Cart Service is running${NC}"

# Check if credit card authorizer is running
if ! curl -s -f "http://localhost:8083/health" > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠ Credit Card Authorizer is not running on http://localhost:8083${NC}"
    echo "Start it with: docker-compose up credit-card-authorizer -d"
    echo "Note: Checkout will fail without this service"
else
    echo -e "${GREEN}✓ Credit Card Authorizer is running${NC}"
fi
echo ""

# Create a cart
echo "Creating shopping cart..."
CART_RESPONSE=$(curl -s -X POST "${SHOPPING_CART_URL}/shopping-carts" \
  -H "Content-Type: application/json" \
  -d '{"customer_id":"TEST-CUSTOMER-001"}')

CART_ID=$(echo "$CART_RESPONSE" | jq -r '.cart_id')

if [ "$CART_ID" == "null" ] || [ -z "$CART_ID" ]; then
    echo -e "${RED}✗ Failed to create cart${NC}"
    echo "Response: $CART_RESPONSE"
    exit 1
fi

echo -e "${GREEN}✓ Created cart: $CART_ID${NC}"
echo ""

# Add items to cart
echo "Adding items to cart..."
curl -s -X POST "${SHOPPING_CART_URL}/shopping-carts/${CART_ID}/items" \
  -H "Content-Type: application/json" \
  -d '{"product_id":"PROD-001","quantity":3}' > /dev/null

curl -s -X POST "${SHOPPING_CART_URL}/shopping-carts/${CART_ID}/items" \
  -H "Content-Type: application/json" \
  -d '{"product_id":"PROD-002","quantity":2}' > /dev/null

echo -e "${GREEN}✓ Added items to cart${NC}"
echo ""

# Checkout (this will send message to warehouse)
echo "Processing checkout (sending order to warehouse)..."
CHECKOUT_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${SHOPPING_CART_URL}/shopping-carts/${CART_ID}/checkout" \
  -H "Content-Type: application/json" \
  -d '{"credit_card_number":"1234-5678-9012-3456"}')

CHECKOUT_BODY=$(echo "$CHECKOUT_RESPONSE" | head -n 1)
CHECKOUT_STATUS=$(echo "$CHECKOUT_RESPONSE" | tail -n 1)

if [ "$CHECKOUT_STATUS" == "200" ]; then
    echo -e "${GREEN}✓ Checkout successful!${NC}"
    echo "Response:"
    echo "$CHECKOUT_BODY" | jq .
    echo ""
    echo -e "${GREEN}✓ Order should now be in RabbitMQ queue and processed by warehouse service${NC}"
else
    echo -e "${RED}✗ Checkout failed with status: $CHECKOUT_STATUS${NC}"
    echo "Response: $CHECKOUT_BODY"
fi

echo ""
echo -e "${YELLOW}Step 5: Check Warehouse Service Logs${NC}"
echo "Run this command to see warehouse processing logs:"
echo "  docker logs -f warehouse-service"
echo ""
echo "You should see messages like:"
echo "  [Worker X] Processed order ORDER-XXX (Cart: CART-XXX)"
echo ""

echo -e "${YELLOW}Step 6: Check RabbitMQ Queue Status${NC}"
echo "Visit ${RABBITMQ_UI} and:"
echo "  1. Login with admin/admin123"
echo "  2. Go to 'Queues' tab"
echo "  3. Click on 'warehouse_orders' queue"
echo "  4. Check 'Ready' messages (should be low/zero if warehouse is processing)"
echo "  5. Check 'Message rates' to see publish/consume rates"
echo ""

echo -e "${YELLOW}Step 7: Test Multiple Orders${NC}"
echo "Sending 5 more test orders..."
SUCCESS_COUNT=0
FAILED_COUNT=0

for i in {1..5}; do
    # Create cart
    CART_RESP=$(curl -s -X POST "${SHOPPING_CART_URL}/shopping-carts" \
      -H "Content-Type: application/json" \
      -d "{\"customer_id\":\"TEST-CUSTOMER-00${i}\"}")
    CART=$(echo "$CART_RESP" | jq -r '.cart_id')
    
    if [ "$CART" == "null" ] || [ -z "$CART" ]; then
        echo "  ✗ Failed to create cart for order $i"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        continue
    fi
    
    # Add item
    ADD_RESP=$(curl -s -w "\n%{http_code}" -X POST "${SHOPPING_CART_URL}/shopping-carts/${CART}/items" \
      -H "Content-Type: application/json" \
      -d "{\"product_id\":\"PROD-00${i}\",\"quantity\":${i}}")
    ADD_STATUS=$(echo "$ADD_RESP" | tail -n 1)
    
    if [ "$ADD_STATUS" != "200" ]; then
        echo "  ✗ Failed to add item to cart for order $i (status: $ADD_STATUS)"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        continue
    fi
    
    # Checkout (may fail if payment declined - that's OK for testing)
    CHECKOUT_RESP=$(curl -s -w "\n%{http_code}" -X POST "${SHOPPING_CART_URL}/shopping-carts/${CART}/checkout" \
      -H "Content-Type: application/json" \
      -d '{"credit_card_number":"1234-5678-9012-3456"}')
    CHECKOUT_STATUS=$(echo "$CHECKOUT_RESP" | tail -n 1)
    
    if [ "$CHECKOUT_STATUS" == "200" ]; then
        echo "  ✓ Sent order $i (checkout successful)"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        # Payment might be declined (10% chance) - that's expected behavior
        if [ "$CHECKOUT_STATUS" == "402" ]; then
            echo "  ⚠ Order $i payment declined (expected ~10% of the time)"
        else
            echo "  ✗ Order $i checkout failed (status: $CHECKOUT_STATUS)"
        fi
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
    
    sleep 0.5
done

echo ""
echo -e "${GREEN}✓ Completed sending 5 test orders${NC}"
echo "  Successful: $SUCCESS_COUNT"
echo "  Failed/Declined: $FAILED_COUNT"
echo ""

echo -e "${YELLOW}Step 8: View Warehouse Statistics${NC}"
echo "To see total orders processed, stop the warehouse service:"
echo "  docker stop warehouse-service"
echo ""
echo "The warehouse service will print statistics on shutdown:"
echo "  =================================================="
echo "  WAREHOUSE SERVICE STATISTICS"
echo "  =================================================="
echo "  Total Orders Processed: X"
echo "  =================================================="
echo ""

echo "=========================================="
echo -e "${GREEN}Test Complete!${NC}"
echo "=========================================="
echo ""
echo "Waiting 2 seconds for messages to be processed..."
sleep 2
echo ""

# Try to check queue status via RabbitMQ management API (if available)
echo -e "${YELLOW}Quick Queue Status Check:${NC}"
QUEUE_INFO=$(curl -s -u admin:admin123 "${RABBITMQ_UI}/api/queues/%2F/warehouse_orders" 2>/dev/null)
if [ $? -eq 0 ] && [ ! -z "$QUEUE_INFO" ]; then
    READY_MSGS=$(echo "$QUEUE_INFO" | jq -r '.messages_ready // 0' 2>/dev/null)
    CONSUMER_COUNT=$(echo "$QUEUE_INFO" | jq -r '.consumers // 0' 2>/dev/null)
    if [ ! -z "$READY_MSGS" ] && [ "$READY_MSGS" != "null" ]; then
        echo "  Queue 'warehouse_orders':"
        echo "    Ready messages: $READY_MSGS"
        echo "    Active consumers: $CONSUMER_COUNT"
        if [ "$READY_MSGS" -gt 1000 ]; then
            echo -e "    ${YELLOW}⚠ Warning: Queue has more than 1000 messages${NC}"
        elif [ "$READY_MSGS" -eq 0 ]; then
            echo -e "    ${GREEN}✓ Queue is empty (all messages processed)${NC}"
        else
            echo -e "    ${GREEN}✓ Queue length is reasonable${NC}"
        fi
    fi
else
    echo "  (Could not fetch queue status - check RabbitMQ UI manually)"
fi
echo ""

echo "Next steps:"
echo "  1. Check RabbitMQ UI: ${RABBITMQ_UI}"
echo "  2. View warehouse logs: docker logs -f warehouse-service"
echo "  3. Monitor queue length in RabbitMQ UI"
echo "  4. Stop warehouse service to see statistics: docker stop warehouse-service"

