#!/bin/bash

echo "========================================="
echo "Database Cleanup Utility"
echo "========================================="

read -p "This will DELETE ALL test data. Continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
  echo "Cleanup cancelled."
  exit 0
fi

echo ""
echo "Cleaning MongoDB..."

docker exec vibe_mongo mongosh vibe_learn --quiet --eval "
  print('Before cleanup:');
  print('  Events: ' + db.events.countDocuments({}));
  print('  Analytics: ' + db.session_analytics.countDocuments({}));
  print('');

  db.events.deleteMany({});
  db.session_analytics.deleteMany({});

  print('After cleanup:');
  print('  Events: ' + db.events.countDocuments({}));
  print('  Analytics: ' + db.session_analytics.countDocuments({}));
  print('');
  print('✅ Cleanup complete!');
"

echo ""
echo "Resetting Kafka consumer offsets..."

docker exec vibe_kafka /opt/kafka/bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --group event-consumer-group \
  --reset-offsets \
  --to-earliest \
  --topic code-events \
  --execute

docker exec vibe_kafka /opt/kafka/bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --group analytics-group \
  --reset-offsets \
  --to-earliest \
  --topic code-events \
  --execute

echo ""
echo "✅ Database and Kafka offsets reset!"
echo ""
echo "Services will reconnect automatically."