#!/bin/bash

# ==============================
# Envoy Mini Service Mesh Tester
# ==============================
# Run from a pod inside the cluster
# Example: kubectl run -it loadtester --image=radial/busyboxplus:curl --rm -- /bin/sh
# ./mesh_monitor.sh

ENVOY_URL=${1:-"http://example-app:10000"}   # Main Envoy listener
ADMIN_URL=${2:-"http://example-app:9901"}    # Envoy admin interface

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Envoy Mini Service Mesh Tester ===${NC}"
echo "Envoy URL: $ENVOY_URL"
echo "Admin URL: $ADMIN_URL"
echo "===================================="

# --------------------------------
# Check if services are accessible
# --------------------------------
check_services() {
    echo -e "\n${YELLOW}Checking service health...${NC}"
    endpoints=("httpbin/get" "nginx" "podb")

    for ep in "${endpoints[@]}"; do
        if curl -s -o /dev/null -w "%{http_code}" "$ENVOY_URL/$ep" | grep -q "2"; then
            echo -e "✓ $ep: ${GREEN}Accessible${NC}"
        else
            echo -e "✗ $ep: ${RED}Not Accessible${NC}"
        fi
    done

    # Admin interface check
    if curl -s -o /dev/null -w "%{http_code}" "$ADMIN_URL/ready" | grep -q "200"; then
        echo -e "✓ Envoy Admin: ${GREEN}Ready${NC}"
    else
        echo -e "✗ Envoy Admin: ${RED}Not Ready${NC}"
    fi
}

# --------------------------------
# Test endpoint with concurrent requests
# --------------------------------
test_endpoint() {
    local endpoint=$1
    local count=${2:-10}   # Number of requests
    local delay=${3:-0.1}  # Delay between requests

    echo -e "\n${YELLOW}Testing endpoint: $endpoint ($count requests)${NC}"

    success=0
    rate_limited=0
    other=0

    for i in $(seq 1 $count); do
        (
            response=$(curl -s -w "HTTP_STATUS:%{http_code}" -o /dev/null "$ENVOY_URL/$endpoint")
            code=$(echo $response | grep -o 'HTTP_STATUS:[0-9]*' | cut -d: -f2)
            if [ "$code" == "200" ]; then
                echo "SUCCESS"
                ((success++))
            elif [ "$code" == "429" ]; then
                echo "RATE_LIMITED"
                ((rate_limited++))
            else
                echo "OTHER($code)"
                ((other++))
            fi
        ) &
        sleep $delay
    done
    wait

    echo -e "\n${BLUE}Summary for $endpoint:${NC}"
    echo "  Success: $success"
    echo "  Rate Limited: $rate_limited"
    echo "  Other: $other"
}

# --------------------------------
# Show rate limit / envoy headers
# --------------------------------
show_headers() {
    local endpoint=$1
    echo -e "\n${YELLOW}Rate limit headers for $endpoint:${NC}"
    curl -s -I "$ENVOY_URL/$endpoint" | grep -i "x-ratelimit\|x-envoy" | sed 's/^/  /' || echo "  None found"
}

# --------------------------------
# Show debug info
# --------------------------------
show_debug_info() {
    echo -e "\n${YELLOW}Envoy Admin Stats (first 10 ratelimit entries)${NC}"
    curl -s "$ADMIN_URL/stats?filter=ratelimit" | head -10 || echo "  Admin interface not accessible"

    echo -e "\n${YELLOW}Pods in mesh:${NC}"
    kubectl get pods -l app=example-app
    kubectl get pods -l app=example-app-b
}

# --------------------------------
# Main
# --------------------------------
main() {
    check_services

    # Test each endpoint
    test_endpoint "httpbin/get" 5 0.05
    test_endpoint "nginx" 5 0.05
    test_endpoint "podb" 5 0.05

    # Show headers for reference
    show_headers "httpbin/get"
    show_headers "nginx"
    show_headers "podb"

    show_debug_info
}

# Ensure curl exists
if ! command -v curl &>/dev/null; then
    echo -e "${RED}Error: curl is required${NC}"
    exit 1
fi

main
