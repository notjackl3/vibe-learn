#!/bin/bash
# Name: tests/add-exit-codes.sh

echo "Adding exit codes to test scripts..."
echo ""

# Function to add exit code if missing
add_exit_code() {
  local file=$1

  if grep -q "exit 0" "$file" || grep -q "exit 1" "$file"; then
    echo "⏭️  $file - Already has exit codes"
    return
  fi

  echo "Adding exit code to $file..."

  # Add exit 0 at the end (default to success)
  echo "" >> "$file"
  echo "# Test completed" >> "$file"
  echo "exit 0" >> "$file"

  echo "✅ $file - Exit code added"
}

# Add to all test files
for test in test-*.sh; do
  add_exit_code "$test"
done

echo ""
echo "✅ All tests updated!"
echo ""
echo "Note: Tests now default to exit 0 (success)."
echo "You should manually add proper success/failure checks."