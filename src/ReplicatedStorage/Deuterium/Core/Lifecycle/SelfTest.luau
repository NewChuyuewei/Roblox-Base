--!strict
-- Dr.Core.Lifecycle.SelfTest
-- Studio-only sanity for the W1.5 lifecycle plumbing. Command bar:
--   require(game.ReplicatedStorage.Deuterium.Core.Lifecycle.SelfTest).RunAll()

local Debug = require(script.Parent.Parent.Parent.Parent.Debug)

local RunContext = require(script.Parent.Parent.Parent.Runtime.Environment.RunContext)
local Kernel = require(script.Parent.Parent.Container.Kernel)
local BootSequencer = require(script.Parent.BootSequencer)
local ShutdownManager = require(script.Parent.ShutdownManager)
local Lifecycle = require(script.Parent.Lifecycle)
local ErrorHandler = require(script.Parent.Parent.Foundation.ErrorHandler)
local Contract = require(script.Parent.Parent.Foundation.Contract)

local SelfTest = {}

local function check(name: string, fn: () -> ()): (boolean, string)
	local err: unknown = nil
	local ok = xpcall(fn, function(e)
		err = ErrorHandler.Render(e)
	end)
	return ok, if ok then name else (name .. " -> " .. tostring(err))
end

local function expect(cond: boolean, what: string)
	assert(cond, what)
end

function SelfTest.RunAll(): boolean
	assert(RunContext.IsStudio(), "[Dr.SelfTest.Lifecycle] Studio-only")
	local failures = 0
	local function record(label: string, ok: boolean, msg: string)
		if ok then
			Debug.print("[Dr.SelfTest.Lifecycle] PASS", label)
		else
			failures += 1
			Debug.warn("[Dr.SelfTest.Lifecycle] FAIL", msg)
		end
	end

	local tests = {
		{
			name = "ErrorHandler structured errors carry code",
			fn = function()
				local r = ErrorHandler.Try(function()
					error("plain boom")
				end, "DR.TEST", "selftest")
				expect(not r.ok, "try fails")
				expect(r.err ~= nil, "err present")
				expect(ErrorHandler.IsDrError((r :: any).err), "normalized to DrError")
				expect((r :: any).err.code == "DR.TEST", "fallback code")
			end,
		},
		{
			name = "Contract raises structured errors",
			fn = function()
				local ok = pcall(Contract.Precondition, false, "X", "must be X")
				expect(not ok, "precondition threw")
				local ok2 = pcall(function()
					Contract.Precondition(false, "X", "must be X")
					return true
				end)
				expect(not ok2, "again")
				local ok3, e = pcall(function()
					Contract.Precondition(false, "X", "must be X")
				end)
				expect(not ok3, "thrown once more")
				expect(ErrorHandler.IsDrError(e), "thrown value is DrError")
				expect(
					(((e :: any) :: any).code :: string):find("DR.CONTRACT.PRECONDITION", 1, true) ~= nil,
					"code namespace"
				)
			end,
		},
		{
			name = "Lifecycle phases ordered",
			fn = function()
				local phases = Lifecycle.Phases()
				expect(#phases == 5, "five phases")
				expect(Lifecycle.IsBefore("Collecting", "Started"), "ordering")
				expect(Lifecycle.IsKnown("Stopped"), "known")
				expect(not Lifecycle.IsKnown("Exploded"), "unknown")
			end,
		},
		{
			name = "BootSequencer run is once",
			fn = function()
				Kernel.Reset()
				-- no providers registered here; pure plumbing check
				expect(BootSequencer.Run(), "first boot ok")
				expect(Kernel.GetState() == "Started", "state reached")
				local ok = pcall(BootSequencer.Run)
				expect(not ok, "second boot refused")
			end,
		},
		{
			name = "ShutdownManager run is once",
			fn = function()
				Kernel.Reset()
				-- reseed a minimal provider so GetOrder has content
				local calls: { string } = {}
				Kernel.Register({
					Name = "W15.Seed",
					Init = function() end,
					Start = function() end,
					Stop = function()
						table.insert(calls, "Stop")
					end,
				})
				expect(Kernel.Construct(), "construct")
				Kernel.Init()
				Kernel.Start()
				local ran = pcall(ShutdownManager.Run)
				expect(ran, "shutdown once")
				expect(#calls == 1, "stop called once")
				local ok = pcall(ShutdownManager.Run)
				expect(not ok, "double shutdown refused")
			end,
		},
	}

	for _, entry in tests do
		local ok, msg = check(entry.name, entry.fn)
		record(entry.name, ok, msg)
	end

	Debug.print(("[Dr.SelfTest.Lifecycle] %d/%d passed"):format(#tests - failures, #tests))
	return failures == 0
end

return SelfTest
