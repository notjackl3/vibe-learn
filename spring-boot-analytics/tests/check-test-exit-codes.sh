#!/bin/bash
# Name: tests/check-test-exit-codes.sh

echo "Checking which tests have proper exit codes..."
echo ""

for test in test-*.sh; do
  if grep -q "exit 0" "$test" || grep -q "exit 1" "$test"; then
    echo "✅ $test - Has exit codes"
  else
    echo "⚠️  $test - Missing exit codes"
  fi
done

echo ""
echo "Tests missing exit codes should be updated to include:"
echo "  exit 0  # for success"
echo "  exit 1  # for failure"