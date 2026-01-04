#!/bin/bash

echo "========================================="
echo "Test 5: Load Test (100 events/session, 5 sessions)"
echo "========================================="

for session in {1..5}; do
  SESSION_ID="load-test-$session-$(date +%s)"
  echo "Starting session $session: $SESSION_ID"

  for i in {1..100}; do
    curl -X POST http://localhost:8080/api/events \
      -H "Content-Type: application/json" \
      -H "X-API-Key: custom-api-key-here" \
      -d "{
        \"sessionId\": \"$SESSION_ID\",
        \"clientTimestampMs\": $(date +%s)000,
        \"fileUri\": \"file:///Load$((i % 10)).java\",
        \"fileName\": \"Load$((i % 10)).java\",
        \"lineNumber\": $i,
        \"textNormalized\": \"load test line $i\",
        \"source\": \"load-test\"
      }" -s -o /dev/null &

    # Batch requests
    if [ $((i % 10)) -eq 0 ]; then
      wait
      sleep 0.5
    fi
  done
  wait
  echo "✅ Session $session complete (100 events)"
done

echo ""
echo "Total events sent: 500"
echo "⏳ Waiting 70 seconds for processing and flush..."
sleep 70

# Check results
echo "Checking results..."
RAW_EVENTS=$(docker exec vibe_mongo mongosh vibe_learn --quiet --eval "db.events.countDocuments({sessionId: /load-test/})")
ANALYTICS=$(docker exec vibe_mongo mongosh vibe_learn --quiet --eval "db.session_analytics.countDocuments({sessionId: /load-test/})")

echo "Raw events stored: $RAW_EVENTS"
echo "Analytics documents: $ANALYTICS"

if [ "$RAW_EVENTS" -eq 500 ] && [ "$ANALYTICS" -eq 5 ]; then
  echo "✅ LOAD TEST PASSED!"
else
  echo "⚠️  Expected 500 events and 5 analytics, got $RAW_EVENTS events and $ANALYTICS analytics"
fi

# Check consumer lag after load
echo ""
echo "Checking consumer lag after load..."
docker exec vibe_kafka /opt/kafka/bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --describe \
  --group event-consumer-group \
  | grep "LAG"

echo ""
echo "========================================="
echo "Test 5 Complete!"
echo "========================================="
# Test completed
exit 0
