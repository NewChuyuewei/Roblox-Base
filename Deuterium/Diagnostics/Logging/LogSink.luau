--!strict
-- Dr.Diagnostics.Logging.LogSink — the write boundary: the only impure part of Dr.Logging.
--
-- A Sink receives finished records. Callers never touch a Sink directly — they hold a
-- Logger — so swapping the default implementation (Scribe-backed, aggregator-backed,
-- file-backed) in D6.1b requires no call-site change.
-- Scribe is not installed in this repository yet, so the default is StudioSink.

local StructuredLog = require(script.Parent.StructuredLog)

export type Record = StructuredLog.Record

export type Sink = {
	Write: (record: Record) -> (),
}

local LogSink = {}

-- Human-readable wall clock for the console default. Never allowed to break logging.
--
-- `os.date("%H:%M:%S")` type-errors under the Roblox definitions: they declare os.date as
-- taking the literal union `"!*t" | "*t"`, not an arbitrary format string (luau-lsp,
-- 2026-10-25). So we ask for `*t` (a table) and format it ourselves — type-clean, and it
-- keeps the failure path (pcall) intact.
local function stamp(): string
	-- 同样要包成闭包：直接 pcall(os.date, "*t") 时 "*t" 会被放宽成 string，
	-- 又碰上那个字面量联合类型。闭包里的直接调用才能保住上下文类型。
	local ok, parts: any = pcall(function()
		return os.date("*t")
	end)
	if ok and type(parts) == "table" then
		return string.format("%02d:%02d:%02d", parts.hour, parts.min, parts.sec)
	end
	return "??:??:??"
end

-- Console default: debug/info go to print, warn/error go to warn so Studio's
-- warning filter still works.
LogSink.StudioSink = table.freeze({
	Write = function(record: Record): ()
		local line = `{stamp()} {StructuredLog.Format(record)}`
		if record.level == "warn" or record.level == "error" then
			warn(line)
		else
			print(line)
		end
	end,
}) :: Sink

return table.freeze(LogSink)
