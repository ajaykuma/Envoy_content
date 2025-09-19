#!/bin/bash

# Simple rate limit test script
JWT_TOKEN="eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjMiLCJyb2xlIjoiYWRtaW4iLCJpc3MiOiJ0ZXN0LWlzc3VlciIsImlhdCI6MTc1ODI4MzI5Mn0.T9cRHjWPWA9jgVOwt9AY1JOwqlmgd3SY0T67CaS0v5k"
ENVOY_URL="http://192.168.49.2:31000"

echo "Simple Rate Limit Test"
echo "========================="

# Test httpbin route quickly (should hit 2 req/sec limit)
echo "Testing /httpbin/get with rapid requests (should be rate limited after 2 requests)..."
for i in {1..5}; do
    echo -n "Request $i: "
    response=$(curl -s -w "HTTP_CODE:%{http_code}" -H "Authorization: Bearer $JWT_TOKEN" "$ENVOY_URL/httpbin/get" -o /dev/null)
    http_code=$(echo $response | grep -o 'HTTP_CODE:[0-9]*' | cut -d: -f2)
    
    if [ "$http_code" = "200" ]; then
        echo "SUCCESS"
    elif [ "$http_code" = "429" ]; then
        echo "RATE LIMITED"
    else
        echo "HTTP $http_code"
    fi
    
    # Don't sleep, send requests as fast as possible
done

echo
echo "Checking rate limit headers from last request..."
curl -s -I -H "Authorization: Bearer $JWT_TOKEN" "$ENVOY_URL/httpbin/get" | grep -i "x-.*rate\|x-envoy"

echo
echo "Waiting 2 seconds for rate limit window to reset..."
sleep 2

echo "Testing again after reset..."
for i in {1..3}; do
    echo -n "Request $i: "
    response=$(curl -s -w "HTTP_CODE:%{http_code}" -H "Authorization: Bearer $JWT_TOKEN" "$ENVOY_URL/httpbin/get" -o /dev/null)
    http_code=$(echo $response | grep -o 'HTTP_CODE:[0-9]*' | cut -d: -f2)
    
    if [ "$http_code" = "200" ]; then
        echo "✓ SUCCESS"
    elif [ "$http_code" = "429" ]; then
        echo "RATE LIMITED"
    else
        echo " HTTP $http_code"
    fi
done
