#!/bin/bash
# Chaotic high-volume traffic generator
# Simulates production-like chaos with bursts, failures, and unpredictable patterns

echo "========================================="
echo "🔥 CHAOTIC HIGH-VOLUME SYSTEM 🔥"
echo "========================================="
echo ""
echo "This system will:"
echo "  • Send 50-500 events per second"
echo "  • Simulate 20+ concurrent users"
echo "  • Create random traffic spikes"
echo "  • Inject failures and retries"
echo "  • Cleanup database every 5 minutes"
echo "  • Stress test your infrastructure"
echo ""
echo "⚠️  WARNING: This generates HEAVY load!"
echo ""
read -p "Press ENTER to start chaos, or Ctrl+C to cancel..."
echo ""

# Configuration
CLEANUP_INTERVAL=300  # 5 minutes
LAST_CLEANUP=$(date +%s)
TOTAL_EVENTS=0
TOTAL_ERRORS=0
CYCLE_EVENTS=0

# Traffic intensity (changes dynamically)
CURRENT_INTENSITY="NORMAL"  # LOW, NORMAL, HIGH, EXTREME, SPIKE

# Concurrent user pool
NUM_USERS=25
declare -a ACTIVE_PIDS=()

# Statistics
STATS_FILE="/tmp/chaos_stats.txt"
echo "0" > "$STATS_FILE"

# Cleanup function
cleanup_database() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔄 DATABASE CLEANUP CYCLE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Kill all background traffic generators
    echo "⏸️  Stopping traffic generators..."
    for pid in "${ACTIVE_PIDS[@]}"; do
        kill "$pid" 2>/dev/null
    done
    wait 2>/dev/null
    ACTIVE_PIDS=()

    sleep 2

    # Get stats
    EVENTS_BEFORE=$(docker exec vibe_mongo mongosh vibe_learn --quiet --eval "db.events.countDocuments({})" 2>/dev/null || echo "0")
    ANALYTICS_BEFORE=$(docker exec vibe_mongo mongosh vibe_learn --quiet --eval "db.session_analytics.countDocuments({})" 2>/dev/null || echo "0")

    echo "📊 Before cleanup:"
    echo "   Events: $EVENTS_BEFORE"
    echo "   Analytics: $ANALYTICS_BEFORE"
    echo "   Events this cycle: $CYCLE_EVENTS"
    echo "   Total events sent: $TOTAL_EVENTS"
    echo "   Total errors: $TOTAL_ERRORS"

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

    echo "✅ Cleanup complete!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Reset cycle counter
    CYCLE_EVENTS=0
    LAST_CLEANUP=$(date +%s)
}

# Function to send a single event (with failure simulation)
send_event() {
    local user=$1
    local session_id=$2
    local line_num=$3
    local file_name=$4

    # Simulate random failures (5% chance)
    if [ $((RANDOM % 100)) -lt 5 ]; then
        # Send with wrong API key (will be rejected)
        curl -X POST http://localhost:8080/api/events \
            -H "Content-Type: application/json" \
            -H "X-API-Key: wrong-key" \
            -d "{\"sessionId\":\"$session_id\",\"clientTimestampMs\":$(date +%s)000,\"fileUri\":\"file:///$file_name\",\"fileName\":\"$file_name\",\"lineNumber\":$line_num,\"textNormalized\":\"line $line_num\",\"source\":\"chaos\"}" \
            -s -o /dev/null
        TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
        return
    fi

    # Normal request
    curl -X POST http://localhost:8080/api/events \
        -H "Content-Type: application/json" \
        -H "X-API-Key: custom-api-key-here" \
        -d "{
            \"sessionId\": \"$session_id\",
            \"clientTimestampMs\": $(date +%s)000,
            \"fileUri\": \"file:///$user/$file_name\",
            \"fileName\": \"$file_name\",
            \"lineNumber\": $line_num,
            \"textNormalized\": \"$user chaos line $line_num\",
            \"source\": \"chaos-system\"
        }" -s -o /dev/null

    TOTAL_EVENTS=$((TOTAL_EVENTS + 1))
    CYCLE_EVENTS=$((CYCLE_EVENTS + 1))

    # Update stats file
    echo "$CYCLE_EVENTS" > "$STATS_FILE"
}

# Rapid fire burst generator
burst_generator() {
    local user=$1
    local burst_size=$2
    local session_id="burst-$(date +%s)-$user"
    local file_name="Burst${RANDOM}.java"

    for i in $(seq 1 $burst_size); do
        send_event "$user" "$session_id" "$i" "$file_name" &
    done
    wait
}

# Sustained traffic generator (runs in background)
sustained_generator() {
    local user=$1
    local rate=$2  # Events per second
    local session_id="sustained-$(date +%s)-$user"
    local line_num=1
    local file_num=$((RANDOM % 20 + 1))
    local file_name="Project${file_num}.java"

    while true; do
        send_event "$user" "$session_id" "$line_num" "$file_name"
        line_num=$((line_num + 1))

        # Sleep based on rate
        sleep $(echo "scale=3; 1 / $rate" | bc)

        # Occasionally switch files
        if [ $((RANDOM % 50)) -eq 0 ]; then
            file_num=$((RANDOM % 20 + 1))
            file_name="Project${file_num}.java"
        fi
    done
}

# Spike generator - sudden massive burst
generate_spike() {
    echo ""
    echo "⚡️⚡️⚡️ TRAFFIC SPIKE! Sending 1000 events in 5 seconds..."

    for i in {1..1000}; do
        send_event "spike-user" "spike-$(date +%s)" "$i" "Spike.java" &

        if [ $((i % 100)) -eq 0 ]; then
            sleep 0.5
        fi
    done

    wait
    echo "⚡️ Spike complete!"
    echo ""
}

# Traffic pattern controller
change_intensity() {
    local new_intensity=$1

    if [ "$new_intensity" = "$CURRENT_INTENSITY" ]; then
        return
    fi

    echo ""
    echo "🎚️  Changing intensity: $CURRENT_INTENSITY → $new_intensity"

    # Kill existing generators
    for pid in "${ACTIVE_PIDS[@]}"; do
        kill "$pid" 2>/dev/null
    done
    wait 2>/dev/null
    ACTIVE_PIDS=()

    CURRENT_INTENSITY=$new_intensity

    # Start new generators based on intensity
    case $new_intensity in
        "LOW")
            # 5 users, 2 events/sec each = 10 events/sec
            for i in {1..5}; do
                sustained_generator "user-$i" 2 &
                ACTIVE_PIDS+=($!)
            done
            echo "   Active: 5 users @ 2 events/sec = ~10 events/sec"
            ;;

        "NORMAL")
            # 10 users, 5 events/sec each = 50 events/sec
            for i in {1..10}; do
                sustained_generator "user-$i" 5 &
                ACTIVE_PIDS+=($!)
            done
            echo "   Active: 10 users @ 5 events/sec = ~50 events/sec"
            ;;

        "HIGH")
            # 20 users, 10 events/sec each = 200 events/sec
            for i in {1..20}; do
                sustained_generator "user-$i" 10 &
                ACTIVE_PIDS+=($!)
            done
            echo "   Active: 20 users @ 10 events/sec = ~200 events/sec"
            ;;

        "EXTREME")
            # 25 users, 20 events/sec each = 500 events/sec
            for i in {1..25}; do
                sustained_generator "user-$i" 20 &
                ACTIVE_PIDS+=($!)
            done
            echo "   Active: 25 users @ 20 events/sec = ~500 events/sec"
            ;;
    esac
    echo ""
}

# Statistics display (runs in background)
display_stats() {
    while true; do
        sleep 10

        local cycle_events=$(cat "$STATS_FILE" 2>/dev/null || echo "0")
        local events_per_sec=$((cycle_events / 10))

        echo "📈 Stats: $cycle_events events this cycle | ~${events_per_sec}/sec | Total: $TOTAL_EVENTS | Errors: $TOTAL_ERRORS | Mode: $CURRENT_INTENSITY"

        echo "0" > "$STATS_FILE"
    done
}

# Chaos coordinator (main orchestrator)
chaos_coordinator() {
    local time_in_mode=0
    local mode_duration=$((RANDOM % 20 + 20))  # 20-40 seconds per mode

    while true; do
        # Check if time for cleanup
        current_time=$(date +%s)
        if [ $((current_time - LAST_CLEANUP)) -ge $CLEANUP_INTERVAL ]; then
            cleanup_database
            time_in_mode=0
        fi

        # Change intensity randomly
        if [ $time_in_mode -ge $mode_duration ]; then
            local modes=("LOW" "NORMAL" "HIGH" "EXTREME")
            local random_mode=${modes[$RANDOM % ${#modes[@]}]}
            change_intensity "$random_mode"

            time_in_mode=0
            mode_duration=$((RANDOM % 30 + 20))  # 20-50 seconds
        fi

        # Random spike (5% chance every 10 seconds)
        if [ $((RANDOM % 100)) -lt 5 ]; then
            generate_spike
        fi

        # Random burst (10% chance)
        if [ $((RANDOM % 100)) -lt 10 ]; then
            local burst_size=$((RANDOM % 100 + 50))
            echo "💥 Random burst: $burst_size events"
            burst_generator "burst-user-$RANDOM" "$burst_size"
        fi

        sleep 10
        time_in_mode=$((time_in_mode + 10))
    done
}

# Cleanup on exit
trap 'echo ""; echo "🛑 Stopping chaos..."; for pid in "${ACTIVE_PIDS[@]}"; do kill "$pid" 2>/dev/null; done; wait 2>/dev/null; echo "✅ Chaos stopped"; exit 0' EXIT INT TERM

# Start everything
echo "🚀 Starting chaos system..."
echo ""

# Start with NORMAL intensity
change_intensity "NORMAL"

# Start stats display
display_stats &
STATS_PID=$!

# Start chaos coordinator
chaos_coordinator