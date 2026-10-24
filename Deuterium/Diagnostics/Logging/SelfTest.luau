--!strict
-- Dr.Diagnostics.Logging.SelfTest — checks for the logging core.
--
-- Deliberately free of ErrorHandler / Debug / RunContext requires: logging must stay
-- testable headlessly, and "to test logging you need logging" would be a silly loop.
-- Results therefore go to plain print/warn.
--
-- Studio:
--   require(game.ReplicatedStorage.Deuterium.Diagnostics.Logging.SelfTest).RunAll()

local StructuredLog = require(script.Parent.StructuredLog)
local LogSink = require(script.Parent.LogSink)
local Logger = require(script.Parent.Logger)

local SelfTest = {}

local function recorder(): (LogSink.Sink, { StructuredLog.Record })
	local seen: { StructuredLog.Record } = {}
	local sink: LogSink.Sink = {
		Write = function(record: StructuredLog.Record): ()
			table.insert(seen, record)
		end,
	}
	return sink, seen
end

local function check(name: string, fn: () -> ()): (boolean, string)
	local err = ""
	local ok = xpcall(fn, function(e: unknown)
		err = tostring(e)
	end)
	return ok, if ok then name else (name .. " -> " .. err)
end

function SelfTest.RunAll(): boolean
	local failures = 0

	local function record(label: string, ok: boolean, msg: string)
		if ok then
			print("[Dr.SelfTest.Logging] PASS", label)
		else
			failures += 1
			warn("[Dr.SelfTest.Logging] FAIL", msg)
		end
	end

	local function expect(cond: boolean, what: string)
		assert(cond, what)
	end

	local tests = {
		{
			name = "Join matches print semantics",
			fn = function()
				expect(StructuredLog.Join() == "", "no args -> empty")
				expect(StructuredLog.Join("solo") == "solo", "single arg passes through")
				expect(StructuredLog.Join("a:", 1, true) == "a:\t1\ttrue", "tab joined, tostring'd")
			end,
		},
		{
			name = "Join renders tables deterministically",
			fn = function()
				local left = StructuredLog.Join({ b = 2, a = 1 })
				local right = StructuredLog.Join({ a = 1, b = 2 })
				expect(left == right, `key order must not change output ({left} vs {right})`)
				expect(left == "{a=1 b=2}", `unexpected render: {left}`)
				-- nesting caps out instead of recursing forever
				local cyclic: any = {}
				cyclic.self = cyclic
				expect(type(StructuredLog.Join(cyclic)) == "string", "cycles must not hang")
			end,
		},
		{
			name = "New validates and freezes records",
			fn = function()
				local r = StructuredLog.New("warn", "Dr.X", "boom")
				expect(r.level == "warn" and r.tag == "Dr.X" and r.msg == "boom", "fields preserved")
				expect(type(r.ts) == "number" and r.ts > 0, "ts defaults to now")
				expect(table.isfrozen(r), "record frozen")
				expect(not pcall(StructuredLog.New, "bogus" :: any, "t", "m"), "bad level rejected")
				expect(not pcall(StructuredLog.New, "info", "" :: any, "m"), "empty tag rejected")
			end,
		},
		{
			name = "Level helpers agree",
			fn = function()
				expect(StructuredLog.Rank("debug") < StructuredLog.Rank("error"), "ordering ascends")
				expect(StructuredLog.NormalizeLevel("warn") == "warn", "valid level normalized")
				expect(StructuredLog.NormalizeLevel("nope") == nil, "invalid level -> nil")
				expect(StructuredLog.NormalizeLevel(42) == nil, "non-string -> nil")
				expect(not pcall(StructuredLog.Rank, "nope" :: any), "Rank asserts on bad input")
			end,
		},
		{
			name = "Format shape",
			fn = function()
				expect(StructuredLog.Format(StructuredLog.New("info", "Dr.K", "hi")) == "[info][Dr.K] hi", "plain line")
				local withData = StructuredLog.Format(StructuredLog.New("warn", "Dr.K", "hi", { n = 3, z = "x" }))
				expect(withData == "[warn][Dr.K] hi {n=3 z=x}", `unexpected: {withData}`)
			end,
		},
		{
			name = "Logger forwards at or above its threshold",
			fn = function()
				local sink, seen = recorder()
				local log = Logger.New("Dr.T", sink)
				expect(log:GetLevel() == "info", "default level is info")
				log:info("a", 1)
				log:warn("b")
				log:error("c")
				expect(#seen == 3, `expected 3 records, got {#seen}`)
				expect(seen[1].msg == "a\t1", "varargs joined")
				expect(seen[1].tag == "Dr.T", "tag attached")
				expect(seen[3].level == "error", "level attached")
			end,
		},
		{
			name = "Logger filters below threshold",
			fn = function()
				local sink, seen = recorder()
				local log = Logger.New("Dr.T", sink)
				log:debug("dropped")
				expect(#seen == 0, "debug below default info")
				log:SetLevel("debug")
				log:debug("kept")
				expect(#seen == 1, "debug kept after SetLevel")
				log:SetLevel("error")
				log:warn("dropped")
				log:error("kept")
				expect(#seen == 2, "warn dropped at error level")
				expect(log:GetLevel() == "error", "GetLevel reflects SetLevel")
			end,
		},
		{
			name = "Default sink is read at emit time (retrofit)",
			fn = function()
				local original = Logger.GetDefaultSink()
				local sink, seen = recorder()
				local ok, err = pcall(function()
					local log = Logger.New("Dr.T") -- no explicit sink: built BEFORE the swap
					Logger.SetDefaultSink(sink)
					log:warn("routed")
					expect(#seen == 1, "logger built earlier still follows the new default")
					expect(seen[1].msg == "routed", "record content")
				end)
				Logger.SetDefaultSink(original) -- never leak a test sink into the session
				if not ok then
					error(err, 0)
				end
			end,
		},
	}

	for _, entry in tests do
		local ok, msg = check(entry.name, entry.fn)
		record(entry.name, ok, msg)
	end

	print(("[Dr.SelfTest.Logging] %d/%d passed"):format(#tests - failures, #tests))
	return failures == 0
end

return table.freeze(SelfTest)
