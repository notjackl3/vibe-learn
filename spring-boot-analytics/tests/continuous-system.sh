#!/bin/bash
# Continuous system that simulates realistic traffic patterns

echo "========================================="
echo "Vibe Learn Continuous System"
echo "========================================="
echo ""
echo "This will:"
echo "  • Send realistic traffic continuously"
echo "  • Simulate multiple users/sessions"
echo "  • Clean database every 10 minutes"
echo "  • Run until you press Ctrl+C"
echo ""
echo "Press Ctrl+C to stop"
echo ""

# Configuration
CLEANUP_INTERVAL=600  # Clean database every 10 minutes (600 seconds)
LAST_CLEANUP=$(date +%s)
SESSION_COUNTER=1
EVENT_COUNTER=0

# User profiles (different coding patterns)
declare -A USER_PROFILES
USER_PROFILES=(
    ["alice"]="fast"      # Types fast: 2 events/sec
    ["bob"]="moderate"    # Moderate: 1 event/sec
    ["charlie"]="slow"    # Slow: 1 event/3sec
    ["diana"]="burst"     # Bursts: 10 events, then pause
)

# Function to send event
send_event() {
    local user=$1
    local session_id=$2
    local line_num=$3
    local file_num=$4

    curl -X POST http://localhost:8080/api/events \
        -H "Content-Type: application/json" \
        -H "X-API-Key: custom-api-key-here" \
        -d "{
            \"sessionId\": \"${session_id}\",
            \"clientTimestampMs\": $(date +%s)000,
            \"fileUri\": \"file:///${user}/Project${file_num}.java\",
            \"fileName\": \"Project${file_num}.java\",
            \"lineNumber\": ${line_num},
            \"textNormalized\": \"${user} coding line ${line_num}\",
            \"source\": \"continuous-system\"
        }" -s -o /dev/null

    EVENT_COUNTER=$((EVENT_COUNTER + 1))
}

# Function to cleanup database
cleanup_database() {
    echo ""
    echo "⏸️  PAUSING TRAFFIC - Database cleanup starting..."

    # Get stats before cleanup
    EVENTS_BEFORE=$(docker exec vibe_mongo mongosh vibe_learn --quiet --eval "db.events.countDocuments({})" 2>/dev/null || echo "0")
    ANALYTICS_BEFORE=$(docker exec vibe_mongo mongosh vibe_learn --quiet --eval "db.session_analytics.countDocuments({})" 2>/dev/null || echo "0")

    echo "   Before: $EVENTS_BEFORE events, $ANALYTICS_BEFORE analytics docs"

    # Clean MongoDB
    docker exec vibe_mongo mongosh vibe_learn --quiet --eval "
        db.events.deleteMany({});
        db.session_analytics.deleteMany({});
    " > /dev/null 2>&1

    # Reset Kafka offsets
    docker exec vibe_kafka /opt/kafka/bin/kafka-consumer-groups.sh \
        --bootstrap-server localhost:9092 \
        --group event-consumer-group \
        --reset-offsets \
        --to-latest \
        --topic code-events \
        --execute > /dev/null 2>&1

    docker exec vibe_kafka /opt/kafka/bin/kafka-consumer-groups.sh \
        --bootstrap-server localhost:9092 \
        --group analytics-group \
        --reset-offsets \
        --to-latest \
        --topic code-events \
        --execute > /dev/null 2>&1

    echo "   After: Database cleaned, Kafka offsets reset"
    echo "▶️  RESUMING TRAFFIC..."
    echo ""

    # Reset counters
    EVENT_COUNTER=0
    SESSION_COUNTER=$((SESSION_COUNTER + 1))
}

# Function to simulate one user's activity
simulate_user() {
    local user=$1
    local profile=${USER_PROFILES[$user]}
    local session_id="session-${SESSION_COUNTER}-${user}-$(date +%s)"
    local line_num=1
    local file_num=$((RANDOM % 10 + 1))

    case $profile in
        "fast")
            # Fast typer: 2 events/sec for 30 seconds
            for i in {1..60}; do
                send_event "$user" "$session_id" "$line_num" "$file_num"
                line_num=$((line_num + 1))
                sleep 0.5

                # Check if time for cleanup
                current_time=$(date +%s)
                if [ $((current_time - LAST_CLEANUP)) -ge $CLEANUP_INTERVAL ]; then
                    cleanup_database
                    LAST_CLEANUP=$(date +%s)
                    return
                fi
            done
            ;;

        "moderate")
            # Moderate typer: 1 event/sec for 60 seconds
            for i in {1..60}; do
                send_event "$user" "$session_id" "$line_num" "$file_num"
                line_num=$((line_num + 1))
                sleep 1

                current_time=$(date +%s)
                if [ $((current_time - LAST_CLEANUP)) -ge $CLEANUP_INTERVAL ]; then
                    cleanup_database
                    LAST_CLEANUP=$(date +%s)
                    return
                fi
            done
            ;;

        "slow")
            # Slow typer: 1 event/3sec for 90 seconds
            for i in {1..30}; do
                send_event "$user" "$session_id" "$line_num" "$file_num"
                line_num=$((line_num + 1))
                sleep 3

                current_time=$(date +%s)
                if [ $((current_time - LAST_CLEANUP)) -ge $CLEANUP_INTERVAL ]; then
                    cleanup_database
                    LAST_CLEANUP=$(date +%s)
                    return
                fi
            done
            ;;

        "burst")
            # Burst typer: 10 events quickly, then pause
            for i in {1..10}; do
                send_event "$user" "$session_id" "$line_num" "$file_num"
                line_num=$((line_num + 1))
                sleep 0.2
            done
            sleep 5

            current_time=$(date +%s)
            if [ $((current_time - LAST_CLEANUP)) -ge $CLEANUP_INTERVAL ]; then
                cleanup_database
                LAST_CLEANUP=$(date +%s)
                return
            fi
            ;;
    esac
}

# Main loop
echo "Starting continuous traffic..."
echo ""

while true; do
    # Pick a random user
    users=("alice" "bob" "charlie" "diana")
    user=${users[$RANDOM % ${#users[@]}]}

    # Show status every 50 events
    if [ $((EVENT_COUNTER % 50)) -eq 0 ] && [ $EVENT_COUNTER -gt 0 ]; then
        echo "📊 Status: $EVENT_COUNTER events sent in this cycle (User: $user)"
    fi

    # Simulate this user's activity
    simulate_user "$user"

    # Small pause between users
    sleep $((RANDOM % 3 + 1))
done