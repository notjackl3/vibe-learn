#!/bin/bash

echo "========================================="
echo "Test 3: Prometheus Metrics Collection"
echo "========================================="

echo "Checking Prometheus targets..."
curl -s http://localhost:9090/api/v1/targets | \
  jq -r '.data.activeTargets[] | "\(.labels.service): \(.health)"'

echo ""
echo "Checking analytics.events.processed metric..."
EVENTS_PROCESSED=$(curl -s "http://localhost:9090/api/v1/query?query=analytics_events_processed_total" | \
  jq -r '.data.result[0].value[1]')

echo "Total events processed by analytics: $EVENTS_PROCESSED"

echo ""
echo "Checking analytics.flushes metric..."
FLUSHES=$(curl -s "http://localhost:9090/api/v1/query?query=analytics_flushes_total" | \
  jq -r '.data.result[0].value[1]')

echo "Total analytics flushes: $FLUSHES"

echo ""
echo "Checking HTTP request rate..."
curl -s "http://localhost:9090/api/v1/query?query=rate(http_server_requests_seconds_count[1m])" | \
  jq -r '.data.result[] | "\(.metric.service): \(.value[1]) req/sec"'

echo ""
echo "========================================="
echo "Test 3 Complete!"
echo "========================================="
# Test completed
exit 0
