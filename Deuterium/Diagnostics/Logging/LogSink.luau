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
local function stamp(): string
	local ok, text = pcall(os.date, "%H:%M:%S")
	if ok and type(text) == "string" then
		return text
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
