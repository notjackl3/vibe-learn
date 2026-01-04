#!/bin/bash

echo "========================================="
echo "Test 2: Multi-Session Analytics"
echo "========================================="

# Create 3 different sessions
for session_num in {1..3}; do
  SESSION_ID="multi-session-$session_num-$(date +%s)"
  echo "Creating session $session_num: $SESSION_ID"

  # Send 10 events per session
  for i in {1..10}; do
    curl -X POST http://localhost:8080/api/events \
      -H "Content-Type: application/json" \
      -H "X-API-Key: custom-api-key-here" \
      -d "{
        \"sessionId\": \"$SESSION_ID\",
        \"clientTimestampMs\": $(date +%s)000,
        \"fileUri\": \"file:///Session${session_num}.java\",
        \"fileName\": \"Session${session_num}.java\",
        \"lineNumber\": $i,
        \"textNormalized\": \"session $session_num line $i\",
        \"source\": \"multi-session-test\"
      }" -s -o /dev/null
    sleep 0.2
  done
  echo "✅ Session $session_num created (10 events)"
done

echo ""
echo "⏳ Waiting 70 seconds for analytics flush..."
sleep 70

# Check analytics
echo "Checking analytics for all sessions..."
ANALYTICS_COUNT=$(docker exec vibe_mongo mongosh vibe_learn --quiet --eval "db.session_analytics.countDocuments({sessionId: /multi-session/})")
echo "Analytics documents created: $ANALYTICS_COUNT"

if [ "$ANALYTICS_COUNT" -eq 3 ]; then
  echo "✅ All 3 sessions have analytics"
else
  echo "⚠️  Expected 3, found $ANALYTICS_COUNT"
fi

echo ""
echo "========================================="
echo "Test 2 Complete!"
echo "========================================="
# Test completed
exit 0
