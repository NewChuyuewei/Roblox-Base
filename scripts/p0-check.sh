#!/usr/bin/env bash
# P0 guard (README.md §2 gate 5 / spec invariant I1).
#
# The [P0] hot paths must not grow: string lookups, anonymous closure allocation and
# table.insert growth are counted per directory and compared against a committed
# baseline. The baseline is a RATCHET — it may only go down.
#
# Usage:
#   scripts/p0-check.sh                 # verify against scripts/p0-baseline.txt
#   scripts/p0-check.sh --write-baseline  # re-record (only when counts went DOWN)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASELINE="$ROOT/scripts/p0-baseline.txt"

# Directories that hold hot paths. Missing ones are skipped: later waves add them.
SCAN_DIRS=(
	"Deuterium/Core"
	"Deuterium/Net"
	"TritiumSQL/Tri/Request"
	"TritiumSQL/Tri/Storage"
	"TritiumSQL/Tri/Index"
	"TritiumSQL/Tri/Txn"
	"TritiumSQL/Tri/Wal"
	"TritiumSQL/Tri/Query"
)

PATTERNS=(
	"table.insert("
	"game:GetService("
	"loadstring("
)

# Fixed-string, occurrence-counting grep. -o prints one line per match, so wc -l is
# the occurrence count. Avoids `grep -c`'s "file:count" output, which would break on
# Windows drive-letter paths.
count_pattern() { # $1 = pattern
	local total=0 dir n
	for dir in "${SCAN_DIRS[@]}"; do
		[ -d "$ROOT/$dir" ] || continue
		n=$(grep -rFo --include='*.luau' -- "$1" "$ROOT/$dir" 2>/dev/null | wc -l | tr -d ' ')
		total=$((total + n))
	done
	echo "$total"
}

if [ "${1:-}" = "--write-baseline" ]; then
	: >"$BASELINE"
	for pattern in "${PATTERNS[@]}"; do
		printf '%s\t%s\n' "$pattern" "$(count_pattern "$pattern")" >>"$BASELINE"
	done
	echo "baseline written: $BASELINE"
	cat "$BASELINE"
	exit 0
fi

if [ ! -f "$BASELINE" ]; then
	echo "FAIL: missing $BASELINE (run: scripts/p0-check.sh --write-baseline)" >&2
	exit 1
fi

failed=0
printf '%-20s %8s %8s   %s\n' "PATTERN" "ACTUAL" "BASELINE" "VERDICT"
while IFS=$'\t' read -r pattern expected; do
	[ -n "$pattern" ] || continue
	actual=$(count_pattern "$pattern")
	if [ "$actual" -gt "$expected" ]; then
		verdict="FAIL (grew)"
		failed=1
	elif [ "$actual" -lt "$expected" ]; then
		verdict="OK (dropped - tighten the baseline)"
	else
		verdict="OK"
	fi
	printf '%-20s %8s %8s   %s\n' "$pattern" "$actual" "$expected" "$verdict"
done <"$BASELINE"

if [ "$failed" -ne 0 ]; then
	echo >&2
	echo "P0 guard failed: a hot path grew. Either remove the new occurrence or justify it" >&2
	echo "in review and lower the baseline with --write-baseline." >&2
	exit 1
fi

echo "P0 guard OK"
