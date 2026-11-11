#!/usr/bin/env bash
# Runs the full headless test suite. Exit code 0 = all passed.
set -euo pipefail
cd "$(dirname "$0")"
godot --headless --import >/dev/null 2>&1
exec godot --headless --fixed-fps 60 res://tests/test_runner.tscn
