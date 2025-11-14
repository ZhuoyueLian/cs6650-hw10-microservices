#!/usr/bin/env bash

# Simple Bash script to test the Credit Card Authorizer endpoints.
# Run this while services are running (docker-compose or local).

BASE="http://localhost:8080"

echo "Health check..."
curl -s "$BASE/health" | jq .

echo -e "\nTest valid card (expected 200 or 402):"
VALID_PAYLOAD=$(jq -n \
  --arg cc "1234-5678-9012-3456" \
  --argjson amount 12.34 \
  '{credit_card_number: $cc, amount: $amount}')

# Perform request and capture status code
VALID_RESPONSE=$(curl -s -w "\n%{http_code}" -H "Content-Type: application/json" \
  -d "$VALID_PAYLOAD" "$BASE/authorize")

# Split response and status
VALID_BODY=$(echo "$VALID_RESPONSE" | head -n 1)
VALID_STATUS=$(echo "$VALID_RESPONSE" | tail -n 1)

echo "Status: $VALID_STATUS"
echo "Response:"
echo "$VALID_BODY" | jq .

echo -e "\nTest invalid format (expected 400):"
BAD_PAYLOAD=$(jq -n \
  --arg cc "1234567890123456" \
  --argjson amount 10.00 \
  '{credit_card_number: $cc, amount: $amount}')

BAD_RESPONSE=$(curl -s -w "\n%{http_code}" -H "Content-Type: application/json" \
  -d "$BAD_PAYLOAD" "$BASE/authorize")

BAD_BODY=$(echo "$BAD_RESPONSE" | head -n 1)
BAD_STATUS=$(echo "$BAD_RESPONSE" | tail -n 1)

echo "Status: $BAD_STATUS"
echo "Response:"
echo "$BAD_BODY" | jq .
