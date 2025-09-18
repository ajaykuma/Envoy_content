#!/bin/bash

# Rate Limiting Test Script for Envoy
# Usage: ./test_rate_limiting.sh [envoy_url]

ENVOY_URL=${1:-"http://localhost:30081"}
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Testing Envoy Rate Limiting Configuration${NC}"
echo "Envoy URL: $ENVOY_URL"
echo "=================================="

# Function to test rate limiting for a specific endpoint
test_endpoint() {
    local endpoint=$1
    local expected_limit=$2
    local time_unit=$3
    
    echo -e "\n${YELLOW}Testing $endpoint endpoint (limit: $expected_limit requests per $time_unit)${NC}"
    echo "----------------------------------------"
    
    local success_count=0
    local rate_limited_count=0
    local other_count=0
    
    # Make requests and capture responses
    for i in $(seq 1 10); do
        response=$(curl -s -w "HTTP_STATUS:%{http_code};TIME:%{time_total}" -o /dev/null "$ENVOY_URL$endpoint")
        http_code=$(echo $response | grep -o 'HTTP_STATUS:[0-9]*' | cut -d: -f2)
        time_total=$(echo $response | grep -o 'TIME:[0-9.]*' | cut -d: -f2)
        
        if [ "$http_code" == "200" ]; then
            echo -e "Request $i: ${GREEN}SUCCESS${NC} (HTTP $http_code) - Time: ${time_total}s"
            ((success_count++))
        elif [ "$http_code" == "429" ]; then
            echo -e "Request $i: ${RED}RATE LIMITED${NC} (HTTP $http_code) - Time: ${time_total}s"
            ((rate_limited_count++))
        else
            echo -e "Request $i: ${YELLOW}OTHER${NC} (HTTP $http_code) - Time: ${time_total}s"
            ((other_count++))
        fi
        
        # Small delay between requests
        sleep 0.1
    done
    
    echo -e "\n${BLUE}Summary for $endpoint:${NC}"
    echo "  Success: $success_count"
    echo "  Rate Limited: $rate_limited_count"
    echo "  Other: $other_count"
    
    # Check if rate limiting is working as expected
    if [ "$rate_limited_count" -gt 0 ]; then
        echo -e "  ${GREEN}✓ Rate limiting appears to be working${NC}"
    else
        echo -e "  ${RED}✗ No rate limiting detected${NC}"
    fi
}

# Function to check if services are ready
check_services() {
    echo -e "${YELLOW}Checking service health...${NC}"
    
    # Check Envoy admin interface - Fixed the URL
    admin_url=$(echo $ENVOY_URL | sed 's/:30081/:30901/g')
    if curl -s "${admin_url}/ready" > /dev/null 2>&1; then
        echo -e "✓ Envoy Admin: ${GREEN}Ready${NC} (${admin_url})"
    else
        echo -e "✗ Envoy Admin: ${RED}Not Ready${NC} (${admin_url})"
    fi
    
    # Check if endpoints respond
    if curl -s "$ENVOY_URL/httpbin/get" > /dev/null 2>&1; then
        echo -e "✓ HTTPBin: ${GREEN}Accessible${NC}"
    else
        echo -e "✗ HTTPBin: ${RED}Not Accessible${NC}"
    fi
    
    if curl -s "$ENVOY_URL/nginx" > /dev/null 2>&1; then
        echo -e "✓ Nginx: ${GREEN}Accessible${NC}"
    else
        echo -e "✗ Nginx: ${RED}Not Accessible${NC}"
    fi
    
    echo ""
}

# Function to show rate limit headers
show_headers() {
    local endpoint=$1
    echo -e "\n${YELLOW}Rate Limit Headers for $endpoint:${NC}"
    headers=$(curl -s -I "$ENVOY_URL$endpoint" | grep -i "x-ratelimit\|x-envoy")
    if [ -z "$headers" ]; then
        echo "  No rate limit headers found"
    else
        echo "$headers" | sed 's/^/  /'
    fi
}

# Function to show debugging info
show_debug_info() {
    echo -e "\n${YELLOW}Debugging Information:${NC}"
    echo "=================================="
    
    # Check if we can reach the admin interface
    admin_url=$(echo $ENVOY_URL | sed 's/:30081/:30901/g')
    echo "Envoy Admin Interface: ${admin_url}"
    
    # Try to get stats
    echo -e "\n${BLUE}Attempting to fetch rate limit stats...${NC}"
    if curl -s "${admin_url}/stats?filter=ratelimit" 2>/dev/null | head -10; then
        echo "Stats retrieved successfully"
    else
        echo "Could not retrieve stats - admin interface may not be accessible"
    fi
    
    echo -e "\n${BLUE}To check logs manually:${NC}"
    echo "kubectl logs -l app=envoy-global --tail=50"
    echo "kubectl logs -l app=ratelimit-global --tail=50"
    echo "kubectl logs -l app=redis-global --tail=50"
    
    echo -e "\n${BLUE}To check pod status:${NC}"
    echo "kubectl get pods"
    echo "kubectl describe pod -l app=ratelimit-global"
}

# Main testing flow
main() {
    check_services
    
    # Test httpbin endpoint (2 requests per second)
    test_endpoint "/httpbin/get" 2 "second"
    show_headers "/httpbin/get"
    
    echo -e "\n${YELLOW}Waiting 5 seconds before testing nginx...${NC}"
    sleep 5
    
    # Test nginx endpoint (5 requests per minute)
    test_endpoint "/nginx" 5 "minute"
    show_headers "/nginx"
    
    show_debug_info
}

# Check if curl is available
if ! command -v curl &> /dev/null; then
    echo -e "${RED}Error: curl is required but not installed${NC}"
    exit 1
fi

# Run the tests
main
