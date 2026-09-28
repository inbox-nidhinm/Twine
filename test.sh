#!/bin/bash
# Runs every unit test: the model, the file format, and the command and undo layer.
# Shows only the lines worth reading, but fails whenever the tests fail or do
# not build, which the filter alone would hide.
set -uo pipefail
cd "$(dirname "$0")"
out=$(swift test --package-path Packages/MotionKit 2>&1)
status=$?
echo "$out" | grep -E "✔|✘|passed|failed|error|warning" | grep -vE "^\s*$" || true
exit $status
