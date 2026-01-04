#!/bin/bash

echo "╔═══════════════════════════════════════════════════╗"
echo "║     Analytics System - Complete Test Suite        ║"
echo "╚═══════════════════════════════════════════════════╝"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results tracking
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_RUN=0

# Function to print colored output
print_success() {
  echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
  echo -e "${RED}❌ $1${NC}"
}

print_warning() {
  echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
  echo -e "${BLUE}ℹ️  $1${NC}"
}

# Function to clean database
cleanup_database() {
  echo ""
  echo "========================================="
  echo "Cleaning Database"
  echo "========================================="

  # Drop test collections
  docker exec vibe_mongo mongosh vibe_learn --quiet --eval "
    var eventsCount = db.events.countDocuments({});
    var analyticsCount = db.session_analytics.countDocuments({});

    db.events.deleteMany({});
    db.session_analytics.deleteMany({});

    print('Cleared ' + eventsCount + ' events');
    print('Cleared ' + analyticsCount + ' analytics documents');
  "

  # Reset Kafka consumer offsets
  echo ""
  echo "Resetting Kafka consumer offsets..."
  docker exec vibe_kafka /opt/kafka/bin/kafka-consumer-groups.sh \
    --bootstrap-server localhost:9092 \
    --group event-consumer-group \
    --reset-offsets \
    --to-earliest \
    --topic code-events \
    --execute > /dev/null 2>&1

  docker exec vibe_kafka /opt/kafka/bin/kafka-consumer-groups.sh \
    --bootstrap-server localhost:9092 \
    --group analytics-group \
    --reset-offsets \
    --to-earliest \
    --topic code-events \
    --execute > /dev/null 2>&1

  print_success "Database cleaned successfully"
  echo ""
  sleep 5 # Give consumers time to reconnect
}

# Function to verify services are healthy
check_services() {
  echo "========================================="
  echo "Checking Service Health"
  echo "========================================="

  local all_healthy=true

  # Check each service
  services=("vibe_ingest" "vibe_consumer" "vibe_analytics" "vibe_kafka" "vibe_mongo")

  for service in "${services[@]}"; do
    if docker ps | grep -q "$service"; then
      echo "✓ $service: Running"
    else
      print_error "$service: NOT RUNNING"
      all_healthy=false
    fi
  done

  if [ "$all_healthy" = false ]; then
    print_error "Some services are not healthy!"
    echo ""
    echo "Start services with: cd .. && docker-compose up -d"
    exit 1
  fi

  print_success "All services healthy"
  echo ""
}

# Function to run a test and track results
run_test() {
  local test_name=$1
  local test_script=$2
  local cleanup_before=${3:-true}  # Default: cleanup before test

  ((TESTS_RUN++))

  echo ""
  echo "═══════════════════════════════════════════════════"
  echo "  Test $TESTS_RUN: $test_name"
  echo "═══════════════════════════════════════════════════"
  echo ""

  # Clean database before test (unless disabled)
  if [ "$cleanup_before" = true ]; then
    cleanup_database
  fi

  # Run the test
  if [ -f "$test_script" ]; then
    chmod +x "$test_script"

    # Run test and capture exit code
    if ./"$test_script"; then
      ((TESTS_PASSED++))
      print_success "$test_name PASSED"
    else
      ((TESTS_FAILED++))
      print_error "$test_name FAILED"
    fi
  else
    print_error "Test script not found: $test_script"
    ((TESTS_FAILED++))
  fi

  echo ""
  echo "Pausing 10 seconds before next test..."
  sleep 10
}

# Main test execution
main() {
  echo "Starting test suite at $(date)"
  echo ""

  # Pre-flight checks
  check_services

  # Initial cleanup
  echo "Performing initial database cleanup..."
  cleanup_database

  # ═══════════════════════════════════════════════════
  # QUICK TESTS (Fast validation)
  # ═══════════════════════════════════════════════════

  print_info "Running Quick Validation Tests..."
  echo ""

  run_test "End-to-End Flow Test" "test-analytics-e2e.sh"
  run_test "Prometheus Metrics Collection" "test-prometheus-metics.sh"
  run_test "Consumer Lag Check" "test-consumer-lag.sh"
  run_test "Duplicate Prevention Check" "test-duplicate-prevention.sh"

  # ═══════════════════════════════════════════════════
  # LOAD TESTS (Performance & Scale)
  # ═══════════════════════════════════════════════════

  print_info "Running Load & Performance Tests..."
  echo ""

  run_test "Basic Load Test" "test-analytics-load.sh"
  run_test "Extreme Load Test (10k events)" "test-analytics-load-extreme.sh"
  run_test "Multi-User Types (Realistic Behavior)" "test-multi-user-types.sh"
  run_test "Multi-Session Test" "test-analytics-multi-session.sh"

  # ═══════════════════════════════════════════════════
  # ACCURACY TESTS (Data Quality)
  # ═══════════════════════════════════════════════════

  print_info "Running Accuracy & Data Quality Tests..."
  echo ""

  run_test "Analytics Accuracy Verification" "test-analytics-accuracy.sh"

  # ═══════════════════════════════════════════════════
  # FINAL REPORT
  # ═══════════════════════════════════════════════════

  echo ""
  echo "╔═══════════════════════════════════════════════════╗"
  echo "║              Test Suite Complete                   ║"
  echo "╚═══════════════════════════════════════════════════╝"
  echo ""
  echo "Tests Run:    $TESTS_RUN"
  print_success "Tests Passed: $TESTS_PASSED"

  if [ $TESTS_FAILED -gt 0 ]; then
    print_error "Tests Failed: $TESTS_FAILED"
    echo ""
    echo "Please review the output above for failure details."
    exit 1
  else
    echo ""
    print_success "🎉 ALL TESTS PASSED! 🎉"
    echo ""
    echo "Your analytics system is working correctly!"
  fi

  # Final stats
  echo ""
  echo "Final Database Stats:"
  docker exec vibe_mongo mongosh vibe_learn --quiet --eval "
    print('Total events in database: ' + db.events.countDocuments({}));
    print('Total analytics documents: ' + db.session_analytics.countDocuments({}));
  "

  echo ""
  echo "Final Consumer Lag:"
  docker exec vibe_kafka /opt/kafka/bin/kafka-consumer-groups.sh \
    --bootstrap-server localhost:9092 \
    --describe \
    --group event-consumer-group \
    | grep -E "TOPIC|code-events"

  echo ""
  echo "Completed at $(date)"
}

# Handle command line arguments
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
  echo "Analytics Test Suite Runner"
  echo ""
  echo "Usage: ./run-all-analytics-tests.sh [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --help, -h     Show this help message"
  echo "  --quick        Run only quick validation tests"
  echo "  --load         Run only load tests"
  echo "  --accuracy     Run only accuracy tests"
  echo ""
  echo "Examples:"
  echo "  ./run-all-analytics-tests.sh          # Run all tests"
  echo "  ./run-all-analytics-tests.sh --quick  # Run quick tests only"
  exit 0
fi

if [ "$1" = "--quick" ]; then
  echo "Running QUICK tests only..."
  check_services
  cleanup_database
  run_test "End-to-End Flow Test" "test-analytics-e2e.sh"
  run_test "Prometheus Metrics" "test-prometheus-metics.sh"
  run_test "Consumer Lag" "test-consumer-lag.sh"
  exit 0
fi

if [ "$1" = "--load" ]; then
  echo "Running LOAD tests only..."
  check_services
  cleanup_database
  run_test "Basic Load" "test-analytics-load.sh"
  run_test "Extreme Load" "test-analytics-load-extreme.sh"
  run_test "Multi-User" "test-multi-user-types.sh"
  exit 0
fi

if [ "$1" = "--accuracy" ]; then
  echo "Running ACCURACY tests only..."
  check_services
  cleanup_database
  run_test "Analytics Accuracy" "test-analytics-accuracy.sh"
  exit 0
fi

# Run all tests
main