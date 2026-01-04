#!/bin/bash

echo "========================================="
echo "Test 1: End-to-End Analytics Flow"
echo "========================================="

SESSION_ID="e2e-test-$(date +%s)"
echo "Session ID: $SESSION_ID"

# Send 30 events
echo "Sending 30 events..."
for i in {1..30}; do
  curl -X POST http://localhost:8080/api/events \
    -H "Content-Type: application/json" \
    -H "X-API-Key: custom-api-key-here" \
    -d "{
      \"sessionId\": \"$SESSION_ID\",
      \"clientTimestampMs\": $(date +%s)000,
      \"fileUri\": \"file:///Test$((i % 3)).java\",
      \"fileName\": \"Test$((i % 3)).java\",
      \"lineNumber\": $i,
      \"textNormalized\": \"line $i code testing\",
      \"source\": \"e2e-test\"
    }" -s -o /dev/null
  sleep 0.1
done

echo "✅ Sent 30 events"
echo ""
echo "⏳ Waiting 30 seconds for Kafka consumption..."
sleep 30

# Check raw events in MongoDB
echo "Checking MongoDB for raw events..."
RAW_COUNT=$(docker exec vibe_mongo mongosh vibe_learn --quiet --eval "db.events.countDocuments({sessionId: '$SESSION_ID'})")
echo "Raw events in MongoDB: $RAW_COUNT"

if [ "$RAW_COUNT" -eq 30 ]; then
  echo "✅ All events stored in MongoDB"
else
  echo "❌ Expected 30 events, found $RAW_COUNT"
fi

echo ""
echo "⏳ Waiting 60 seconds for analytics flush..."
sleep 60

# Check analytics in MongoDB
echo "Checking MongoDB for analytics..."
docker exec vibe_mongo mongosh vibe_learn --quiet --eval "
  db.session_analytics.find({sessionId: '$SESSION_ID'}).forEach(function(doc) {
    print('Session ID: ' + doc.sessionId);
    print('Total Events: ' + doc.totalEvents);
    print('Total Lines: ' + doc.totalLines);
    print('Files Modified: ' + doc.filesModified);
    print('Lines Per Minute: ' + doc.linesPerMinute);
    print('Events Per Minute: ' + doc.eventsPerMinute);
  });
"

echo ""
echo "========================================="
echo "Test 1 Complete!"
echo "========================================="
# Test completed
exit 0
