#!/bin/bash
# Runs every unit test: the model, the file format, and the command and undo layer.
set -euo pipefail
cd "$(dirname "$0")"
swift test --package-path Packages/MotionKit 2>&1 | grep -E "✔|✘|passed|failed|error|warning" | grep -vE "^\s*$" || true
