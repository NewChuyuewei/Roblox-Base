--!strict
-- Dr.Diagnostics.Logging.Logger — level filtering + tag ownership + sink forwarding.
--
-- API is print-like varargs, NOT printf: the existing Debug.print/Debug.warn call sites
-- already pass pre-formatted strings plus extra values, and they must keep working
-- unchanged. Message joining is StructuredLog.Join's job.
--
-- No ErrorHandler require on purpose — ErrorHandler requires Debug, which requires
-- Logger, so depending on it here would close a cycle. Programmer errors use `assert`.

local StructuredLog = require(script.Parent.StructuredLog)
local LogSink = require(script.Parent.LogSink)

export type Level = StructuredLog.Level
export type Record = StructuredLog.Record
export type Sink = LogSink.Sink

export type Logger = {
	debug: (...any) -> (),
	info: (...any) -> (),
	warn: (...any) -> (),
	error: (...any) -> (),
	SetLevel: (level: Level) -> (),
	GetLevel: () -> Level,
}

-- "info" keeps every legacy Debug.print visible while still silencing debug chatter.
local DEFAULT_LEVEL: Level = "info"

local Logger = {}

-- Read through this on every emit rather than capturing it in each Logger, so that
-- Logger.SetDefaultSink (D6.1b) retrofits loggers that were built before the swap.
local _defaultSink: Sink = LogSink.StudioSink

function Logger.New(tag: string, sink: Sink?): Logger
	assert(type(tag) == "string" and #tag > 0, "[Dr.Logger] tag required")

	local currentLevel: Level = DEFAULT_LEVEL
	local currentRank = StructuredLog.Rank(currentLevel)
	local ownSink = sink

	local function emit(level: Level, ...: any): ()
		if StructuredLog.Rank(level) < currentRank then
			return
		end
		local target = ownSink or _defaultSink
		target.Write(StructuredLog.New(level, tag, StructuredLog.Join(...)))
	end

	return table.freeze({
		debug = function(...: any): ()
			emit("debug", ...)
		end,
		info = function(...: any): ()
			emit("info", ...)
		end,
		warn = function(...: any): ()
			emit("warn", ...)
		end,
		error = function(...: any): ()
			emit("error", ...)
		end,
		SetLevel = function(level: Level): ()
			currentLevel = level
			currentRank = StructuredLog.Rank(level)
		end,
		GetLevel = function(): Level
			return currentLevel
		end,
	}) :: Logger
end

function Logger.SetDefaultSink(sink: Sink): ()
	assert(type(sink) == "table" and type(sink.Write) == "function", "[Dr.Logger] sink needs Write")
	_defaultSink = sink
end

function Logger.GetDefaultSink(): Sink
	return _defaultSink
end

return table.freeze(Logger)
