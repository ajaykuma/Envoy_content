#!/bin/bash

# ============================================
# Envoy JWT + Rate Limit Test Script
# ============================================

ENVOY_URL=${1:-"http://192.168.49.2:31000"}  # Envoy listener
ROUTES=("/httpbin/get" "/nginx")             # Routes to test
NUM_REQUESTS=10                              # Number of requests per route
DELAY_BETWEEN_REQUESTS=0.2                   # Delay between requests in seconds
JWT_SECRET="testsecret"
JWT_ISSUER="test-issuer"
ROLE="admin"

# --------------------------------------------
# Generate JWT token using Python
# --------------------------------------------
JWT_TOKEN=$(python3 - <<END
import jwt, datetime
payload = {
    "sub": "123",
    "role": "$ROLE",
    "iss": "$JWT_ISSUER",
    "iat": datetime.datetime.utcnow()
}
token = jwt.encode(payload, "$JWT_SECRET", algorithm="HS256")
print(token)
END
)

echo "Generated JWT Token: $JWT_TOKEN"
echo "=========================================="

# Function to test a route
test_route() {
    local endpoint=$1
    local success=0
    local rate_limited=0
    local other=0

    echo -e "\nTesting $endpoint ..."

    for i in $(seq 1 $NUM_REQUESTS); do
        # Make request with JWT
        response=$(curl -s -H "Authorization: Bearer $JWT_TOKEN" \
            -w "HTTP_STATUS:%{http_code};TIME:%{time_total}" -o /dev/null \
            "$ENVOY_URL$endpoint")

        http_code=$(echo $response | grep -o 'HTTP_STATUS:[0-9]*' | cut -d: -f2)

        # Classify responses
        if [[ "$http_code" == "200" ]]; then
            echo "Request $i: SUCCESS (HTTP $http_code)"
            ((success++))
        elif [[ "$http_code" == "429" ]]; then
            echo "Request $i: RATE LIMITED (HTTP $http_code)"
            ((rate_limited++))
        else
            echo "Request $i: OTHER (HTTP $http_code)"
            ((other++))
        fi

        sleep $DELAY_BETWEEN_REQUESTS
    done

    echo -e "\nSummary for $endpoint:"
    echo "  Success: $success"
    echo "  Rate Limited: $rate_limited"
    echo "  Other: $other"

    # Show rate-limit headers
    echo "Rate limit headers:"
    curl -s -I -H "Authorization: Bearer $JWT_TOKEN" "$ENVOY_URL$endpoint" | grep -i "x-envoy\|x-ratelimit" || echo "  None"
}

# --------------------------------------------
# Main
# --------------------------------------------
for route in "${ROUTES[@]}"; do
    test_route "$route"
done

echo -e "\nTesting complete."
