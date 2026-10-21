#!/bin/bash
# Runs gdUnit4 suites one Godot process at a time. A whole-directory run crashes
# Godot during suite scanning, so suites must be run individually.
# Usage: tools/run_unit_suites.sh <out_file> <suite.gd>...
set -u
cd "$(dirname "$0")/.." || exit 1
out=$1; shift
: > "$out"
status=0

# Pick the timeout tool once: `timeout` on Linux, `gtimeout` on macOS, and the
# perl alarm form as a last resort (exec clears a pending alarm on POSIX).
if command -v timeout >/dev/null 2>&1; then
	TIMEOUT_CMD=timeout
elif command -v gtimeout >/dev/null 2>&1; then
	TIMEOUT_CMD=gtimeout
else
	TIMEOUT_CMD=""
fi

# Runs one suite, writing its raw output to $2. Returns Godot's own exit code.
run_suite() {
	local suite=$1
	local raw=$2
	local cmd=(godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd
		--ignoreHeadlessMode -a "res://$suite")
	if [ -n "$TIMEOUT_CMD" ]; then
		"$TIMEOUT_CMD" 120 "${cmd[@]}" >"$raw" 2>&1
	else
		perl -e 'alarm shift; exec @ARGV' 120 "${cmd[@]}" >"$raw" 2>&1
	fi
}

for f in "$@"; do
	raw=$(mktemp)
	run_suite "$f" "$raw"
	rc=$?
	sed 's/\x1b\[[0-9;]*m//g' "$raw" > "$raw.txt"
	summ=$(grep "Overall Summary" "$raw.txt" | tail -1)
	fails=$(grep " FAILED" "$raw.txt" | sed 's/.*> //; s/ FAILED.*//' | sort -u | tr '\n' ',')
	echo "$f | ${summ:-NO SUMMARY (crash/parse error)} | $fails" >> "$out"
	# A non-zero exit means the suite was not clean, even if a summary was printed.
	if [ "$rc" -ne 0 ] || [ -z "$summ" ] || ! echo "$summ" | grep -q "0 errors | 0 failures"; then
		status=1
	fi
	rm -f "$raw" "$raw.txt"
done
exit $status
