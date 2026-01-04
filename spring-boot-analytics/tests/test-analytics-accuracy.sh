#!/bin/bash

echo "========================================="
echo "Test 6: Analytics Accuracy Verification"
echo "========================================="

SESSION_ID="accuracy-test-$(date +%s)"
echo "Session ID: $SESSION_ID"

# Send exactly 60 events over 60 seconds (1 event/sec)
echo "Sending 60 events over 60 seconds..."
for i in {1..60}; do
  curl -X POST http://localhost:8080/api/events \
    -H "Content-Type: application/json" \
    -H "X-API-Key: custom-api-key-here" \
    -d "{
      \"sessionId\": \"$SESSION_ID\",
      \"clientTimestampMs\": $(date +%s)000,
      \"fileUri\": \"file:///Accuracy.java\",
      \"fileName\": \"Accuracy.java\",
      \"lineNumber\": $i,
      \"textNormalized\": \"accuracy test line $i\",
      \"source\": \"accuracy-test\"
    }" -s -o /dev/null
  echo -n "."
  sleep 1
done
echo ""

echo "⏳ Waiting 70 seconds for analytics..."
sleep 70

# Check analytics accuracy
echo "Verifying calculations..."
docker exec vibe_mongo mongosh vibe_learn --quiet --eval "
  var doc = db.session_analytics.findOne({sessionId: '$SESSION_ID'});
  if (doc) {
    print('Total Events: ' + doc.totalEvents + ' (expected: 60)');
    print('Total Lines: ' + doc.totalLines + ' (expected: 60)');
    print('Lines Per Minute: ' + doc.linesPerMinute.toFixed(2) + ' (expected: ~60)');
    print('Events Per Minute: ' + doc.eventsPerMinute.toFixed(2) + ' (expected: ~60)');
    print('Average Time Between Events: ' + doc.averageTimeBetweenEvents.toFixed(2) + ' ms (expected: ~1000)');
    print('Files Modified: ' + doc.uniqueFilesCount + ' (expected: 1)');

    // Verify accuracy
    var passed = true;
    if (doc.totalEvents !== 60) passed = false;
    if (Math.abs(doc.linesPerMinute - 60) > 5) passed = false;
    if (Math.abs(doc.averageTimeBetweenEvents - 1000) > 200) passed = false;

    if (passed) {
      print('');
      print('✅ ACCURACY TEST PASSED!');
    } else {
      print('');
      print('⚠️  Some calculations outside expected range');
    }
  } else {
    print('❌ Analytics document not found!');
  }
"

echo ""
echo "========================================="
echo "Test 6 Complete!"
echo "========================================="
# Test completed
exit 0
