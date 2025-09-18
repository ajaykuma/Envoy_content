#!/bin/bash
set -e

ADMIN_PORT=9901

echo "=== Checking Envoy Listeners ==="
curl -s http://localhost:${ADMIN_PORT}/listeners | jq .

echo ""
echo "=== Testing Multiplexer Listener (10000) ==="
curl -s -o /dev/null -w "HTTP %{http_code} - /httpbin/get\n" http://localhost:10000/httpbin/get
curl -s -o /dev/null -w "HTTP %{http_code} - /nginx/\n" http://localhost:10000/nginx/

echo ""
echo "=== Testing Dedicated httpbin Listener (10001) ==="
curl -s -o /dev/null -w "HTTP %{http_code} - /get\n" http://localhost:10001/get

echo ""
echo "=== Testing Dedicated nginx Listener (10002) ==="
curl -s -o /dev/null -w "HTTP %{http_code} - /\n" http://localhost:10002/

echo ""
echo "=== Stress Testing httpbin Listener (10001) ==="
ab -n 200 -c 50 http://localhost:10001/get | grep "Failed requests" || true

echo ""
echo "=== Circuit Breaker Stats ==="
curl -s http://localhost:${ADMIN_PORT}/stats | grep circuit_breaker || true

echo ""
echo "=== Outlier Detection Stats ==="
curl -s http://localhost:${ADMIN_PORT}/stats | grep outlier_detection || true

echo ""
echo "=== Done! ==="
