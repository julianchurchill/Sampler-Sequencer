#!/bin/sh
# Installs the project's pre-commit hook into .git/hooks/.
# Run once after cloning: sh scripts/install-hooks.sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cp "$SCRIPT_DIR/pre-commit.sh" "$REPO_ROOT/.git/hooks/pre-commit"
chmod +x "$REPO_ROOT/.git/hooks/pre-commit"
echo "Pre-commit hook installed at $REPO_ROOT/.git/hooks/pre-commit"
