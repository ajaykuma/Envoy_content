#!/bin/bash

# ============================================
# Envoy JWT + Rate Limit Test Script
# ============================================

ENVOY_URL=${1:-"http://192.168.49.2:31000"}  # Envoy listener
ROUTES=("/httpbin/get" "/nginx")             # Routes to test
NUM_REQUESTS=15                              # Increased to better test rate limits
DELAY_BETWEEN_REQUESTS=0.1                   # Faster requests to trigger rate limits
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
echo "Role: $ROLE"
echo "=========================================="

# Function to test connectivity first
test_connectivity() {
    echo "Testing connectivity to Envoy..."
    if curl -s -f "$ENVOY_URL/httpbin/get" -H "Authorization: Bearer $JWT_TOKEN" > /dev/null; then
        echo "✓ Connectivity OK"
    else
        echo "✗ Connectivity failed - check if services are running"
        exit 1
    fi
    echo
}

# Function to test a route
test_route() {
    local endpoint=$1
    local success=0
    local rate_limited=0
    local auth_failed=0
    local other=0
    local start_time=$(date +%s)

    echo -e "\n Testing $endpoint ..."
    echo "Expected rate limit for admin role:"
    if [[ "$endpoint" == *"httpbin"* ]]; then
        echo "  - HTTPBin: 2 requests/second"
    else
        echo "  - Nginx: 5 requests/minute"
    fi
    echo

    for i in $(seq 1 $NUM_REQUESTS); do
        # Make request with JWT and capture headers
        response=$(curl -s -H "Authorization: Bearer $JWT_TOKEN" \
            -w "HTTP_STATUS:%{http_code};TIME:%{time_total}" \
            -D /tmp/headers_$$.txt \
            -o /dev/null \
            "$ENVOY_URL$endpoint")

        http_code=$(echo $response | grep -o 'HTTP_STATUS:[0-9]*' | cut -d: -f2)
        time_taken=$(echo $response | grep -o 'TIME:[0-9.]*' | cut -d: -f2)

        # Read rate limit headers
        rate_limit_headers=$(grep -i "x-.*ratelimit\|x-envoy.*rate" /tmp/headers_$$.txt 2>/dev/null || echo "")

        # Classify responses
        case "$http_code" in
            200)
                echo "Request $i: SUCCESS (HTTP $http_code) [${time_taken}s]"
                ((success++))
                ;;
            429)
                echo "Request $i: RATE LIMITED (HTTP $http_code) [${time_taken}s]"
                if [[ -n "$rate_limit_headers" ]]; then
                    echo "    Rate limit headers: $(echo $rate_limit_headers | tr '\n' ' ' | tr -s ' ')"
                fi
                ((rate_limited++))
                ;;
            401|403)
                echo "Request $i: AUTH FAILED (HTTP $http_code) [${time_taken}s]"
                ((auth_failed++))
                ;;
            *)
                echo "Request $i: OTHER (HTTP $http_code) [${time_taken}s]"
                ((other++))
                ;;
        esac

        sleep $DELAY_BETWEEN_REQUESTS
    done

    local end_time=$(date +%s)
    local total_time=$((end_time - start_time))

    echo -e "\nSummary for $endpoint:"
    echo "  Success: $success"
    echo "  Rate Limited: $rate_limited"
    echo "  Auth Failed: $auth_failed"
    echo "  Other: $other"
    echo "  Total time: ${total_time}s"
    echo "  Rate: $(echo "scale=2; $NUM_REQUESTS / $total_time" | bc -l) req/s"

    # Show current rate-limit headers
    echo -e "\nCurrent rate limit headers:"
    curl -s -I -H "Authorization: Bearer $JWT_TOKEN" "$ENVOY_URL$endpoint" 2>/dev/null | \
        grep -i "x-.*ratelimit\|x-envoy.*rate" | \
        while IFS= read -r line; do
            echo "    $line"
        done || echo "    None found"

    # Clean up temp file
    rm -f /tmp/headers_$$.txt
}

# Function to test without JWT
test_no_jwt() {
    echo -e "\nTesting without JWT token..."
    response=$(curl -s -w "HTTP_STATUS:%{http_code}" -o /dev/null "$ENVOY_URL/httpbin/get")
    http_code=$(echo $response | grep -o 'HTTP_STATUS:[0-9]*' | cut -d: -f2)
    
    if [[ "$http_code" == "401" ]]; then
        echo "✓ Correctly rejected unauthorized request (HTTP $http_code)"
    else
        echo "  Unexpected response without JWT (HTTP $http_code)"
    fi
}

# Function to show Envoy stats
show_envoy_stats() {
    echo -e "\n Envoy Rate Limit Stats:"
    echo "Fetching from $ENVOY_URL:9901/stats?filter=rate_limit..."
    curl -s "$ENVOY_URL:9901/stats?filter=rate_limit" 2>/dev/null | \
        grep -E "(rate_limit|ratelimit)" | \
        head -10 || echo "Could not fetch stats (admin interface may not be accessible)"
}

# --------------------------------------------
# Main execution
# --------------------------------------------
echo " Starting Rate Limit Test"
echo "Envoy URL: $ENVOY_URL"
echo "Requests per route: $NUM_REQUESTS"
echo "Delay between requests: ${DELAY_BETWEEN_REQUESTS}s"
echo

# Check if bc is available for calculations
if ! command -v bc &> /dev/null; then
    echo "  'bc' command not found. Install it for rate calculations."
fi

test_connectivity
test_no_jwt

for route in "${ROUTES[@]}"; do
    test_route "$route"
    echo -e "\n" "="*50
done

show_envoy_stats

echo -e "\n Testing complete."
echo
echo " Tips for troubleshooting:"
echo "  - Check pod logs: kubectl logs -f deployment/ratelimit-global"
echo "  - Check Envoy logs: kubectl logs -f deployment/envoy"
echo "  - Check Envoy admin: $ENVOY_URL:9901"
echo "  - Verify services: kubectl get pods,svc"
