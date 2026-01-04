#!/bin/bash

echo "========================================="
echo "Extreme Load Test"
echo "10,000 events with parallel batching"
echo "========================================="

SESSION_ID="extreme-load-$(date +%s)"
echo "Session ID: $SESSION_ID"

START_TIME=$(date +%s)

# Function to send a batch of events
send_batch() {
  local start=$1
  local end=$2
  local session_id=$3

  for i in $(seq $start $end); do
    curl -X POST http://localhost:8080/api/events \
      -H "Content-Type: application/json" \
      -H "X-API-Key: custom-api-key-here" \
      -d "{
        \"sessionId\": \"$session_id\",
        \"clientTimestampMs\": $(date +%s)000,
        \"fileUri\": \"file:///Extreme${i}.java\",
        \"fileName\": \"Extreme${i}.java\",
        \"lineNumber\": $i,
        \"textNormalized\": \"extreme load line $i\",
        \"source\": \"extreme-load-test\"
      }" -s -o /dev/null &
  done
  wait
}

echo "Sending 10,000 events in parallel batches..."

# Send in batches of 200, with 10 batches running in parallel
BATCH_SIZE=200
TOTAL_EVENTS=10000
PARALLEL_BATCHES=10

batch_start=1
for batch_num in $(seq 1 $((TOTAL_EVENTS / BATCH_SIZE / PARALLEL_BATCHES))); do
  # Launch 10 batches in parallel
  for parallel in $(seq 1 $PARALLEL_BATCHES); do
    batch_end=$((batch_start + BATCH_SIZE - 1))
    if [ $batch_end -gt $TOTAL_EVENTS ]; then
      batch_end=$TOTAL_EVENTS
    fi

    send_batch $batch_start $batch_end "$SESSION_ID" &

    batch_start=$((batch_end + 1))

    if [ $batch_start -gt $TOTAL_EVENTS ]; then
      break
    fi
  done

  wait # Wait for this round of parallel batches
  echo "Progress: $batch_start / $TOTAL_EVENTS events sent"

  if [ $batch_start -gt $TOTAL_EVENTS ]; then
    break
  fi
done

wait # Ensure all background jobs complete

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
echo "✅ 10,000 events sent!"
echo "Duration: $DURATION seconds"

if [ $DURATION -gt 0 ]; then
  echo "Throughput: $((10000 / DURATION)) events/second"
else
  echo "Throughput: Very fast! (< 1 second)"
fi

echo ""
echo "⏳ Waiting 30 seconds for Kafka consumption..."
sleep 30

RAW_EVENTS=$(docker exec vibe_mongo mongosh vibe_learn --quiet --eval "db.events.countDocuments({sessionId: '$SESSION_ID'})")
echo "Raw events in MongoDB: $RAW_EVENTS / 10000"

echo ""
echo "Checking consumer lag..."
LAG=$(docker exec vibe_kafka /opt/kafka/bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --describe \
  --group event-consumer-group 2>/dev/null \
  | grep code-events | awk '{sum+=$6} END {print sum}')

echo "Current consumer lag: ${LAG:-0}"

if [ "$LAG" -gt 1000 ]; then
  echo "⚠️  High lag detected, waiting additional 30 seconds..."
  sleep 30
fi

echo ""
echo "⏳ Waiting 70 seconds for analytics flush..."
sleep 70

# Check analytics
ANALYTICS_DOC=$(docker exec vibe_mongo mongosh vibe_learn --quiet --eval "
  var doc = db.session_analytics.findOne({sessionId: '$SESSION_ID'});
  if (doc) {
    print('found');
    print(doc.totalEvents);
  } else {
    print('notfound');
    print('0');
  }
")

ANALYTICS_FOUND=$(echo "$ANALYTICS_DOC" | head -1)
ANALYTICS_TOTAL=$(echo "$ANALYTICS_DOC" | tail -1)

if [ "$ANALYTICS_FOUND" = "found" ]; then
  echo "Analytics Summary:"
  docker exec vibe_mongo mongosh vibe_learn --quiet --eval "
    var doc = db.session_analytics.findOne({sessionId: '$SESSION_ID'});
    print('  Total Events: ' + doc.totalEvents + ' / 10000');
    print('  Total Lines: ' + doc.totalLines);
    print('  Unique Files: ' + doc.uniqueFilesCount);
    print('  Lines/Min: ' + doc.linesPerMinute.toFixed(2));
  "
else
  echo "❌ Analytics document not found!"
fi

echo ""
echo "========================================="
echo "Extreme Load Test Complete!"
echo "========================================="

# Success criteria: At least 95% of events stored and analytics created
MIN_EVENTS=$((10000 * 95 / 100))

if [ "$RAW_EVENTS" -ge "$MIN_EVENTS" ] && [ "$ANALYTICS_FOUND" = "found" ]; then
  echo ""
  echo "✅✅✅ EXTREME LOAD TEST PASSED! ✅✅✅"
  echo "Events stored: $RAW_EVENTS / 10000 ($(echo "scale=1; $RAW_EVENTS * 100 / 10000" | bc)%)"
  exit 0
else
  echo ""
  echo "⚠️  Test failed. Results:"
  echo "   Raw events: $RAW_EVENTS / 10000 (need ≥ $MIN_EVENTS)"
  echo "   Analytics: $ANALYTICS_FOUND"
  if [ "$ANALYTICS_FOUND" = "found" ]; then
    echo "   Analytics total events: $ANALYTICS_TOTAL"
  fi
  exit 1
fi