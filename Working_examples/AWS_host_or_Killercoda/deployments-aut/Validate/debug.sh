#!/bin/bash

echo "Debugging Rate Limiting Setup"
echo "=================================="

# Check if all pods are running
echo "1. Checking pod status:"
kubectl get pods -o wide

echo -e "\n2. Checking services:"
kubectl get svc

echo -e "\n3. Checking rate limit service logs:"
echo "Rate limit service logs (last 50 lines):"
kubectl logs deployment/ratelimit-global --tail=50

echo -e "\n4. Checking Envoy logs:"
echo "Envoy logs (last 30 lines):"
kubectl logs deployment/envoy --tail=30

echo -e "\n5. Testing rate limit service health:"
# Get the rate limit service cluster IP
RATELIMIT_IP=$(kubectl get svc ratelimit-global -o jsonpath='{.spec.clusterIP}')
echo "Rate limit service IP: $RATELIMIT_IP"

# Test if rate limit service is reachable from within cluster
kubectl run debug-pod --image=curlimages/curl --rm -it --restart=Never -- sh -c "
echo 'Testing rate limit service health...'
curl -v http://$RATELIMIT_IP:8080/healthcheck
echo
echo 'Testing rate limit service gRPC port...'
curl -v http://$RATELIMIT_IP:8081/
"

echo -e "\n6. Checking Envoy admin stats:"
curl -s "http://192.168.49.2:31901/stats?filter=rate_limit" | grep -E "(rate_limit|ratelimit)" | head -10

echo -e "\n7. Checking Envoy clusters:"
curl -s "http://192.168.49.2:31901/clusters" | grep -A5 -B5 "ratelimit"

echo -e "\n8. Checking rate limit service config:"
kubectl get configmap ratelimit-config-global -o yaml

echo -e "\n9. Manual rate limit test:"
echo "Testing a single request with verbose output..."
JWT_TOKEN="eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjMiLCJyb2xlIjoiYWRtaW4iLCJpc3MiOiJ0ZXN0LWlzc3VlciIsImlhdCI6MTc1ODI4MzI5Mn0.T9cRHjWPWA9jgVOwt9AY1JOwqlmgd3SY0T67CaS0v5k"

echo "Making request with full headers..."
curl -v -H "Authorization: Bearer $JWT_TOKEN" "http://192.168.49.2:31000/httpbin/get" | head -20

echo -e "\n10. Checking JWT payload extraction:"
echo "JWT payload should contain role=admin"
echo $JWT_TOKEN | cut -d. -f2 | base64 -d 2>/dev/null | jq . || echo "Could not decode JWT"
