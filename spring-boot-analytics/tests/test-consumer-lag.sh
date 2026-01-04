#!/bin/bash
# Name: test-consumer-lag.sh

echo "========================================="
echo "Test 4: Consumer Lag Check"
echo "========================================="

# Check consumer groups
docker exec vibe_kafka /opt/kafka/bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --describe \
  --all-groups

echo ""
echo "Checking Prometheus for consumer lag..."
curl -s "http://localhost:9090/api/v1/query?query=kafka_consumer_records_lag_max" | \
  jq -r '.data.result[] | "\(.metric.service) - Group: \(.metric.group_id) - Lag: \(.value[1])"'

echo ""
echo "========================================="
echo "Test 4 Complete!"
echo "========================================="
# Test completed
exit 0
