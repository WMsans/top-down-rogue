#!/bin/bash
# Runs gdUnit4 suites one Godot process at a time. A whole-directory run crashes
# Godot during suite scanning, so suites must be run individually.
# Usage: tools/run_unit_suites.sh <out_file> <suite.gd>...
set -u
out=$1; shift
: > "$out"
status=0
for f in "$@"; do
	r=$(perl -e 'alarm shift; exec @ARGV' 120 godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
		--ignoreHeadlessMode -a "res://$f" 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
	summ=$(echo "$r" | grep "Overall Summary" | tail -1)
	fails=$(echo "$r" | grep " FAILED" | sed 's/.*> //; s/ FAILED.*//' | sort -u | tr '\n' ',')
	echo "$f | ${summ:-NO SUMMARY (crash/parse error)} | $fails" >> "$out"
	if [ -z "$summ" ] || ! echo "$summ" | grep -q "0 errors | 0 failures"; then
		status=1
	fi
done
exit $status
