#!/usr/bin/env bash
# P0 guard (README.md §2 gate 5 / spec invariant I1).
#
# The [P0] hot paths must not grow: string lookups, anonymous closure allocation and
# table.insert growth are counted per directory and compared against a committed
# baseline. The baseline is a RATCHET — it may only go down.
#
# Usage:
#   scripts/p0-check.sh                              # verify against scripts/p0-baseline.txt
#   scripts/p0-check.sh --write-baseline             # re-record; only lowers counts
#   scripts/p0-check.sh --write-baseline --allow-raise   # raise, review-approved only
#
# P1 加固（三条，都朝「宁可假红也不假绿」的方向）：
#   1. 扫描覆盖度本身成为棘轮量 `files`。原实现把不存在的目录静默跳过
#      （`[ -d ] || continue`），于是 8 个目录里有 6 个还没建、对应两个模式的计数恒为 0
#      —— 目录被改名/删除时计数掉到 0 也算「下降」，照样 OK。这正是 .plan/README.md
#      R23 记过的形状，现在覆盖度下降即 FAIL。
#   2. --write-baseline 不再无条件重写：抬高任何计数都要显式 --allow-raise，
#      文件头那句「only when counts went DOWN」从此才名副其实。
#   3. 未识别的参数报错退出（原来 `--write-basline` 打错字会静默变成校验模式）。
#   4. 基线必须逐键齐全：少一行 = 那个模式不再被约束，现在直接 FAIL。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASELINE="$ROOT/scripts/p0-baseline.txt"

# Directories that hold hot paths. Missing ones are skipped: later waves add them.
SCAN_DIRS=(
	"src/ReplicatedStorage/Deuterium/Core"
	"src/ReplicatedStorage/Deuterium/Net"
	"src/ReplicatedStorage/TritiumSQL/Tri/Request"
	"src/ReplicatedStorage/TritiumSQL/Tri/Storage"
	"src/ReplicatedStorage/TritiumSQL/Tri/Index"
	"src/ReplicatedStorage/TritiumSQL/Tri/Txn"
	"src/ReplicatedStorage/TritiumSQL/Tri/Wal"
	"src/ReplicatedStorage/TritiumSQL/Tri/Query"
)

PATTERNS=(
	"table.insert("
	"game:GetService("
	"loadstring("
)

# `files` 是覆盖度键，与三个模式键一起进基线；顺序即基线里的顺序。
KEYS=("files" "${PATTERNS[@]}")

present=()
missing=()
for dir in "${SCAN_DIRS[@]}"; do
	if [ -d "$ROOT/$dir" ]; then
		present+=("$dir")
	else
		missing+=("$dir")
	fi
done

if [ "${#present[@]}" -eq 0 ]; then
	echo "FAIL: 扫描目录一个都不存在，P0 门禁无从计量：" >&2
	for dir in "${SCAN_DIRS[@]}"; do echo "        $dir" >&2; done
	exit 1
fi

usage() {
	echo "用法：scripts/p0-check.sh [--write-baseline [--allow-raise]]"
}

mode="verify"
allow_raise=0
for arg in "$@"; do
	case "$arg" in
	--write-baseline) mode="write" ;;
	--allow-raise) allow_raise=1 ;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		echo "FAIL: 未知参数 $arg" >&2
		usage >&2
		exit 2
		;;
	esac
done

# Fixed-string, occurrence-counting grep. -o prints one line per match, so wc -l is
# the occurrence count. Avoids `grep -c`'s "file:count" output, which would break on
# Windows drive-letter paths.
measure() { # $1 = key, prints its current value over the existing scan dirs
	local key="$1" total=0 dir n
	for dir in "${present[@]}"; do
		if [ "$key" = "files" ]; then
			n=$(find "$ROOT/$dir" -type f -name '*.luau' | wc -l | tr -d ' ')
		else
			n=$(grep -rFo --include='*.luau' -- "$key" "$ROOT/$dir" 2>/dev/null | wc -l | tr -d ' ')
		fi
		total=$((total + n))
	done
	echo "$total"
}

current=()
declare -A cur=()
for key in "${KEYS[@]}"; do
	n=$(measure "$key")
	current+=("$n")
	cur["$key"]="$n"
done

declare -A old=()
if [ -f "$BASELINE" ]; then
	lineno=0
	while IFS=$'\t' read -r key value || [ -n "${key:-}" ]; do
		lineno=$((lineno + 1))
		[ -n "${key:-}" ] || continue
		case "$value" in
		'' | *[!0-9]*)
			echo "FAIL: 基线第 $lineno 行的值不是整数：'$key' -> '$value'" >&2
			echo "      基线格式为 <key><TAB><count>，请核对后重录（--write-baseline）。" >&2
			exit 1
			;;
		esac
		old["$key"]="$value"
	done <"$BASELINE"
fi

if [ "$mode" = "write" ]; then
	raised=0
	for key in "${KEYS[@]}"; do
		prev="${old[$key]:-}"
		# 覆盖度上升是好事（新目录建起来了），不受棘轮约束；模式计数只许下降。
		if [ -n "$prev" ] && [ "$key" != "files" ] && [ "${cur[$key]}" -gt "$prev" ]; then
			raised=1
			echo "RAISE  $key: $prev -> ${cur[$key]}" >&2
		fi
	done
	if [ "$raised" -eq 1 ] && [ "$allow_raise" -eq 0 ]; then
		echo >&2
		echo "FAIL: 上面这些计数比基线高，棘轮只许下降。" >&2
		echo "      先消除热路径上新增的出现点；确需放行时由评审批准后重跑：" >&2
		echo "        scripts/p0-check.sh --write-baseline --allow-raise" >&2
		exit 1
	fi
	: >"$BASELINE"
	i=0
	for key in "${KEYS[@]}"; do
		printf '%s\t%s\n' "$key" "${current[$i]}" >>"$BASELINE"
		i=$((i + 1))
	done
	echo "baseline written: $BASELINE"
	cat "$BASELINE"
	exit 0
fi

if [ ! -f "$BASELINE" ]; then
	echo "FAIL: missing $BASELINE (run: scripts/p0-check.sh --write-baseline)" >&2
	exit 1
fi

if [ "${#missing[@]}" -gt 0 ]; then
	echo "note: ${#missing[@]}/${#SCAN_DIRS[@]} 个扫描目录尚不存在（后续 Wave 建起后自动纳入计量）："
	for dir in "${missing[@]}"; do echo "        $dir"; done
fi

failed=0
declare -A seen_keys=()
printf '%-20s %8s %8s   %s\n' "KEY" "ACTUAL" "BASELINE" "VERDICT"
while IFS=$'\t' read -r key expected; do
	[ -n "${key:-}" ] || continue
	if [ -z "${cur[$key]+x}" ]; then
		echo "FAIL: 基线里有未预期的键 '$key'（脚本与基线不一致，请核对）" >&2
		failed=1
		continue
	fi
	seen_keys["$key"]=1
	actual="${cur[$key]}"
	if [ "$key" = "files" ]; then
		# 覆盖度是下界：少扫一个文件，就意味着少约束一片热路径。
		if [ "$actual" -lt "$expected" ]; then
			verdict="FAIL (coverage shrank: a scan dir moved or was renamed)"
			failed=1
		elif [ "$actual" -gt "$expected" ]; then
			verdict="OK (grew - re-record to lock it in)"
		else
			verdict="OK"
		fi
	elif [ "$actual" -gt "$expected" ]; then
		verdict="FAIL (grew)"
		failed=1
	elif [ "$actual" -lt "$expected" ]; then
		verdict="OK (dropped - tighten the baseline)"
	else
		verdict="OK"
	fi
	printf '%-20s %8s %8s   %s\n' "$key" "$actual" "$expected" "$verdict"
done <"$BASELINE"

for key in "${KEYS[@]}"; do
	if [ -z "${seen_keys[$key]+x}" ]; then
		echo "FAIL: 基线缺少 '$key' 这一行 —— 棘轮被悄悄削弱了，请重录基线" >&2
		failed=1
	fi
done

if [ "$failed" -ne 0 ]; then
	echo >&2
	echo "P0 guard failed: a hot path grew, or the guard itself was weakened." >&2
	echo "Either remove the new occurrence or justify it in review and lower the" >&2
	echo "baseline with --write-baseline (raising it takes --allow-raise)." >&2
	exit 1
fi

echo "P0 guard OK"
