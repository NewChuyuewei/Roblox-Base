--!strict
-- Dr.Diagnostics.Logging.StructuredLog — pure record construction + single-line rendering.
--
-- Zero requires, zero side effects. This is the part of Dr.Logging that runs anywhere,
-- including headless CI (see .plan/STEPS.md Step 7). It deliberately does NOT require
-- ErrorHandler: ErrorHandler requires Debug, Debug requires Logger, so any dependency
-- added here would close a cycle. Programmer errors therefore use plain `assert`.
--
-- Ownership: StructuredLog builds and renders records. Level filtering and tag ownership
-- live in Logger; the actual writing (print/warn/Scribe) lives in LogSink.
-- `data` is the structured-fields slot; LogAggregator (D6.1b) is what fills it in bulk.

export type Level = "debug" | "info" | "warn" | "error"

export type Record = {
	level: Level,
	tag: string,
	msg: string,
	data: { [string]: any }?,
	ts: number,
}

-- Nesting depth rendered before falling back to tostring(); this also breaks cycles.
local MAX_DEPTH = 2

-- Single source of truth for level ordering (Logger filters with Rank()).
local LEVEL_RANK: { [string]: number } = {
	debug = 10,
	info = 20,
	warn = 30,
	error = 40,
}

local StructuredLog = {}

local function renderValue(value: any, depth: number): string
	if depth <= 0 then
		return tostring(value)
	end
	if type(value) == "string" then
		return value
	end
	if type(value) ~= "table" then
		return tostring(value)
	end
	-- Keys are sorted so a rendered line is deterministic (and therefore testable).
	local keys: { any } = {}
	for key in value :: { [any]: any } do
		table.insert(keys, key)
	end
	table.sort(keys, function(left: any, right: any): boolean
		return tostring(left) < tostring(right)
	end)
	local parts: { string } = table.create(#keys, "")
	for index, key in keys do
		parts[index] = `{tostring(key)}={renderValue((value :: { [any]: any })[key], depth - 1)}`
	end
	return "{" .. table.concat(parts, " ") .. "}"
end

-- print-like message joining (tab separated), NOT printf. The 51 existing
-- Debug.print/Debug.warn call sites already pass pre-formatted strings plus extra
-- values, so joining must match `print` semantics rather than string.format.
function StructuredLog.Join(...: any): string
	local count = select("#", ...)
	if count == 0 then
		return ""
	end
	if count == 1 then
		return renderValue((...), MAX_DEPTH)
	end
	local parts: { string } = table.create(count, "")
	for index = 1, count do
		parts[index] = renderValue((select(index, ...)), MAX_DEPTH)
	end
	return table.concat(parts, "\t")
end

function StructuredLog.Rank(level: Level): number
	local rank = LEVEL_RANK[level]
	assert(rank ~= nil, `[Dr.StructuredLog] invalid level: {tostring(level)}`)
	return rank :: number
end

function StructuredLog.NormalizeLevel(value: any): Level?
	if type(value) == "string" and LEVEL_RANK[value] ~= nil then
		return (value :: any) :: Level
	end
	return nil
end

function StructuredLog.New(
	level: Level,
	tag: string,
	msg: string,
	data: { [string]: any }?,
	ts: number?
): Record
	assert(LEVEL_RANK[level] ~= nil, `[Dr.StructuredLog] invalid level: {tostring(level)}`)
	assert(type(tag) == "string" and #tag > 0, "[Dr.StructuredLog] tag required")
	assert(type(msg) == "string", "[Dr.StructuredLog] msg must be a string")
	return table.freeze({
		level = level,
		tag = tag,
		msg = msg,
		data = data,
		ts = ts or os.time(),
	}) :: Record
end

-- `[warn][Dr.Kernel] msg` (+ rendered structured fields when present).
-- Timestamp is intentionally absent: human time formatting is a Sink concern, so this
-- stays pure and its tests do not depend on the clock.
function StructuredLog.Format(record: Record): string
	local line = `[{record.level}][{record.tag}] {record.msg}`
	local data = record.data
	if data ~= nil then
		line ..= " " .. renderValue(data, MAX_DEPTH)
	end
	return line
end

return table.freeze(StructuredLog)
