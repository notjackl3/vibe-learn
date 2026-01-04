#!/bin/bash

SESSION_ID="analytics-test-$(date +%s)"
echo "Testing analytics with session: $SESSION_ID"

# Send 15 events across 3 files
FILES=("Controller.java" "Service.java" "Repository.java")

for i in {1..15}; do
  FILE=${FILES[$((RANDOM % 3))]}
  
  curl -X POST http://localhost:8080/api/events \
    -H "Content-Type: application/json" \
    -H "X-API-Key: custom-api-key-here" \
    -d "{
      \"sessionId\": \"$SESSION_ID\",
      \"clientTimestampMs\": $(date +%s)000,
      \"fileUri\": \"file:///$FILE\",
      \"fileName\": \"$FILE\",
      \"lineNumber\": $i,
      \"textNormalized\": \"line $i code\",
      \"source\": \"test-script\"
    }" \
    -s -o /dev/null -w "Sent event $i\n"
  
  sleep 0.5
done

echo ""
echo "✅ Sent 15 events for session: $SESSION_ID"
echo "⏳ Wait 60 seconds for analytics flush, then check MongoDB with:"
echo "   docker exec vibe_mongo mongosh vibe_learn --eval \"db.session_analytics.find().sort({_id: -1}).limit(1).pretty()\""
