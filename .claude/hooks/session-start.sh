#!/bin/bash
set -euo pipefail

# Only run in remote (Claude Code on the web) environments.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

FLUTTER_DIR="/opt/flutter"

# Install Flutter stable if not already present.
# The container is cached after first run, so this only happens once.
if [ ! -f "$FLUTTER_DIR/bin/flutter" ]; then
  echo "Installing Flutter SDK (stable)..."
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$FLUTTER_DIR"
fi

# Persist Flutter on PATH for the entire session.
echo "export PATH=\"$FLUTTER_DIR/bin:\$PATH\"" >> "$CLAUDE_ENV_FILE"
export PATH="$FLUTTER_DIR/bin:$PATH"

# Install pub dependencies.
cd "$CLAUDE_PROJECT_DIR"
flutter pub get
