#!/usr/bin/env bash
# Runs a real match between two separate game processes on this machine: a host and a
# client, each played by a bot, plus two bots on the host. Passes if both processes
# finish the match and agree on the result.
set -uo pipefail
cd "$(dirname "$0")/../.."
logs=$(mktemp -d)
godot --headless -- --host --autostart=2 --autopilot --quick --netlog --name=Host > "$logs/host.log" 2>&1 &
host_pid=$!
sleep 2
godot --headless -- --join=127.0.0.1 --autopilot --netlog --name=Client > "$logs/client.log" 2>&1 &
client_pid=$!

# Give the match up to 8 minutes, then stop whatever is still running.
( sleep 480; kill $host_pid $client_pid 2>/dev/null ) &
watchdog=$!
wait $host_pid
sleep 2
kill $client_pid $watchdog 2>/dev/null
wait 2>/dev/null

# Every round result and the final score, as each process saw them.
results() { grep "^NET" "$1" | grep -E "ROUND_END|MATCH_END" | grep -o "round=[0-9]* phase=[A-Z_]* scores=\[[0-9, ]*\]" | uniq; }
host_results=$(results "$logs/host.log")
client_results=$(results "$logs/client.log")
echo "--- host saw:"
echo "$host_results"
echo "--- client saw:"
echo "$client_results"
echo "--- logs: $logs"

if ! echo "$host_results" | grep -q MATCH_END; then
	echo "FAILED: the host did not finish the match"; exit 1
fi
if [ "$host_results" != "$client_results" ]; then
	echo "FAILED: host and client disagree on the results"; exit 1
fi
if grep -q -E "SCRIPT ERROR|Invalid packet|Node not found" "$logs/host.log" "$logs/client.log"; then
	grep -E -A1 "SCRIPT ERROR|Invalid packet|Node not found" "$logs/host.log" "$logs/client.log" | head -20
	echo "FAILED: errors in the logs"; exit 1
fi
echo "PASSED: both processes played the whole match and agree on every round"
