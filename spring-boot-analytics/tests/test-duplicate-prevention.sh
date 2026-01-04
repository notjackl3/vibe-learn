#!/bin/bash

echo "========================================="
echo "Duplicate Event Prevention Test"
echo "========================================="

SESSION_ID="dup-test-$(date +%s)"
TIMESTAMP=$(date +%s)000

echo "Sending 5 identical events..."
for i in {1..5}; do
  curl -X POST http://localhost:8080/api/events \
    -H "Content-Type: application/json" \
    -H "X-API-Key: custom-api-key-here" \
    -d "{
      \"sessionId\": \"$SESSION_ID\",
      \"clientTimestampMs\": $TIMESTAMP,
      \"fileUri\": \"file:///Duplicate.java\",
      \"fileName\": \"Duplicate.java\",
      \"lineNumber\": 42,
      \"textNormalized\": \"exact duplicate\",
      \"source\": \"duplicate-test\"
    }" -s -o /dev/null
  echo "  Sent duplicate $i"
done

sleep 10

COUNT=$(docker exec vibe_mongo mongosh vibe_learn --quiet --eval "
  db.events.countDocuments({sessionId: '$SESSION_ID'})
")

echo ""
echo "Results:"
echo "  Events sent: 5 (identical)"
echo "  Events stored: $COUNT"

if [ "$COUNT" -eq 5 ]; then
  echo ""
  echo "✅ System ALLOWS duplicates"
  echo "This is the current behavior - all events are stored."
  echo ""
  echo "To prevent duplicates, add a unique index:"
  echo "  db.events.createIndex("
  echo "    {sessionId: 1, clientTimestampMs: 1, fileUri: 1, lineNumber: 1},"
  echo "    {unique: true}"
  echo "  )"
elif [ "$COUNT" -eq 1 ]; then
  echo ""
  echo "✅ System PREVENTS duplicates"
  echo "Unique constraint is active."
else
  echo ""
  echo "⚠️  Unexpected result: $COUNT events stored"
fi

# Cleanup
docker exec vibe_mongo mongosh vibe_learn --quiet --eval "
  db.events.deleteMany({sessionId: '$SESSION_ID'});
" > /dev/null

echo ""
echo "========================================="
# Test completed
exit 0
