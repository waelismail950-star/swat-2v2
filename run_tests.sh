#!/usr/bin/env bash
# Runs the full headless test suite. Exit code 0 = all passed and no script errors.
set -uo pipefail
cd "$(dirname "$0")"
godot --headless --import >/dev/null 2>&1
output=$(godot --headless --fixed-fps 60 res://tests/test_runner.tscn 2>&1)
status=$?
echo "$output"
if echo "$output" | grep -q "SCRIPT ERROR"; then
	echo "FAILED: script errors above"
	exit 1
fi
exit $status
