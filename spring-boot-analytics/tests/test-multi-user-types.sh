#!/bin/bash
# Name: test-multi-user-realistic.sh

echo "========================================="
echo "Multi User Types Simulation"
echo "========================================="

# Function: Active coder (fast typer, many events)
simulate_active_coder() {
  local user_id=$1
  local session_id="active-coder-${user_id}-$(date +%s)"
  local num_events=200 # Active coders produce more events

  echo "Active Coder $user_id starting..."

  for i in $(seq 1 $num_events); do
    curl -X POST http://localhost:8080/api/events \
      -H "Content-Type: application/json" \
      -H "X-API-Key: custom-api-key-here" \
      -d "{
        \"sessionId\": \"$session_id\",
        \"clientTimestampMs\": $(date +%s)000,
        \"fileUri\": \"file:///active${user_id}/Main.java\",
        \"fileName\": \"Main.java\",
        \"lineNumber\": $i,
        \"textNormalized\": \"active coding line $i\",
        \"source\": \"active-coder\"
      }" -s -o /dev/null &

    # Fast typing (batch every 20)
    if [ $((i % 20)) -eq 0 ]; then
      wait
      sleep 0.1
    fi
  done
  wait
  echo "Active Coder $user_id finished"
}

# Function: Casual coder (slower, with pauses)
simulate_casual_coder() {
  local user_id=$1
  local session_id="casual-coder-${user_id}-$(date +%s)"
  local num_events=50

  echo "Casual Coder $user_id starting..."

  for i in $(seq 1 $num_events); do
    curl -X POST http://localhost:8080/api/events \
      -H "Content-Type: application/json" \
      -H "X-API-Key: custom-api-key-here" \
      -d "{
        \"sessionId\": \"$session_id\",
        \"clientTimestampMs\": $(date +%s)000,
        \"fileUri\": \"file:///casual${user_id}/Test.java\",
        \"fileName\": \"Test.java\",
        \"lineNumber\": $i,
        \"textNormalized\": \"casual coding line $i\",
        \"source\": \"casual-coder\"
      }" -s -o /dev/null &

    # Slower typing
    if [ $((i % 5)) -eq 0 ]; then
      wait
      sleep 0.$((RANDOM % 5 + 5)) # 0.5-0.9 seconds between bursts
    fi
  done
  wait
  echo "Casual Coder $user_id finished"
}

# Function: Refactorer (editing many files)
simulate_refactorer() {
  local user_id=$1
  local session_id="refactorer-${user_id}-$(date +%s)"
  local num_events=150
  local num_files=10 # Working on many files

  echo "Refactorer $user_id starting..."

  for i in $(seq 1 $num_events); do
    local file_num=$((i % num_files))

    curl -X POST http://localhost:8080/api/events \
      -H "Content-Type: application/json" \
      -H "X-API-Key: custom-api-key-here" \
      -d "{
        \"sessionId\": \"$session_id\",
        \"clientTimestampMs\": $(date +%s)000,
        \"fileUri\": \"file:///refactor${user_id}/Class${file_num}.java\",
        \"fileName\": \"Class${file_num}.java\",
        \"lineNumber\": $i,
        \"textNormalized\": \"refactoring line $i\",
        \"source\": \"refactorer\"
      }" -s -o /dev/null &

    if [ $((i % 15)) -eq 0 ]; then
      wait
      sleep 0.2
    fi
  done
  wait
  echo "Refactorer $user_id finished"
}

# Function: Beginner (slow, making mistakes, deleting/retyping)
simulate_beginner() {
  local user_id=$1
  local session_id="beginner-${user_id}-$(date +%s)"
  local num_events=30

  echo "Beginner $user_id starting..."

  for i in $(seq 1 $num_events); do
    curl -X POST http://localhost:8080/api/events \
      -H "Content-Type: application/json" \
      -H "X-API-Key: custom-api-key-here" \
      -d "{
        \"sessionId\": \"$session_id\",
        \"clientTimestampMs\": $(date +%s)000,
        \"fileUri\": \"file:///beginner${user_id}/HelloWorld.java\",
        \"fileName\": \"HelloWorld.java\",
        \"lineNumber\": $i,
        \"textNormalized\": \"learning to code line $i\",
        \"source\": \"beginner\"
      }" -s -o /dev/null &

    # Very slow typing
    if [ $((i % 3)) -eq 0 ]; then
      wait
      sleep 1 # 1 second pauses
    fi
  done
  wait
  echo "Beginner $user_id finished"
}

# Start simulation
START_TIME=$(date +%s)

# Launch different user types
echo "Launching users..."
echo ""

# 20 active coders
for i in {1..20}; do
  simulate_active_coder $i &
done

# 30 casual coders
for i in {1..30}; do
  simulate_casual_coder $i &
done

# 10 refactorers
for i in {1..10}; do
  simulate_refactorer $i &
done

# 10 beginners
for i in {1..10}; do
  simulate_beginner $i &
done

TOTAL_USERS=70
echo "⏳ $TOTAL_USERS users active..."
wait

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Calculate expected events
EXPECTED_EVENTS=$((20*200 + 30*50 + 10*150 + 10*30))

echo ""
echo "✅ All users finished!"
echo "Duration: $DURATION seconds"
echo "Expected events: $EXPECTED_EVENTS"
echo "Throughput: $((EXPECTED_EVENTS / DURATION)) events/second"

echo ""
echo "⏳ Waiting for processing and analytics..."
sleep 90

# Verify results
RAW_EVENTS=$(docker exec vibe_mongo mongosh vibe_learn --quiet --eval "
  db.events.countDocuments({sessionId: /^(active-coder|casual-coder|refactorer|beginner)-/})
")

ANALYTICS_COUNT=$(docker exec vibe_mongo mongosh vibe_learn --quiet --eval "
  db.session_analytics.countDocuments({sessionId: /^(active-coder|casual-coder|refactorer|beginner)-/})
")

echo "Events in MongoDB: $RAW_EVENTS / $EXPECTED_EVENTS"
echo "Analytics documents: $ANALYTICS_COUNT / $TOTAL_USERS"

# Show breakdown by user type
echo ""
echo "Analytics breakdown by user type:"
docker exec vibe_mongo mongosh vibe_learn --quiet --eval "
  ['active-coder', 'casual-coder', 'refactorer', 'beginner'].forEach(function(type) {
    var count = db.session_analytics.countDocuments({sessionId: new RegExp('^' + type)});
    var total = 0;
    db.session_analytics.find({sessionId: new RegExp('^' + type)}).forEach(function(doc) {
      total += doc.totalEvents;
    });
    print(type + ': ' + count + ' users, ' + total + ' total events');
  });
"

echo ""
echo "========================================="

if [ "$RAW_EVENTS" -ge $((EXPECTED_EVENTS * 95 / 100)) ] && [ "$ANALYTICS_COUNT" -eq "$TOTAL_USERS" ]; then
  echo ""
  echo "✅✅✅ MULTI-USER TYPES TEST PASSED! ✅✅✅"
  exit 0  # ⭐ Success (allowing 5% data loss tolerance)
else
  echo ""
  echo "⚠️  Test failed"
  exit 1  # ⭐ Failure
fi