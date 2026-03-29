#!/bin/sh
# Pre-commit hook: runs Flutter unit tests and blocks the commit on failure.
# Install via: sh scripts/install-hooks.sh
FLUTTER=$(command -v flutter 2>/dev/null)
if [ -z "$FLUTTER" ]; then
  echo "flutter not found in PATH — skipping tests."
  exit 0
fi
echo "Running Flutter tests..."
"$FLUTTER" test --no-pub
if [ $? -ne 0 ]; then
  echo ""
  echo "Tests failed. Commit aborted. Fix the failures above and try again."
  exit 1
fi
echo "All tests passed."
exit 0
