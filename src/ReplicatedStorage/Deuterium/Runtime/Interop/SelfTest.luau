--!strict
-- Dr.Runtime.Interop.SelfTest
-- Studio-only sanity checks. Run in Studio server command bar:
--   require(game.ReplicatedStorage.Deuterium.Runtime.Interop.SelfTest).RunAll()

local Debug = require(script.Parent.Parent.Parent.Parent.Debug)
local ErrorHandler = require(script.Parent.Parent.Parent.Core.Foundation.ErrorHandler)

local RunContext = require(script.Parent.Parent.Environment.RunContext)
local LegacyBridge = require(script.Parent.LegacyBridge)
local ExternalBridge = require(script.Parent.ExternalBridge)
local ServerRegistry = require(script.Parent.Parent.Platform.ServerRegistry)
local ServerBrowser = require(script.Parent.Parent.Platform.ServerBrowser)

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
	assert(RunContext.IsStudio(), "[Dr.SelfTest.Interop] Studio-only")
	local failures = 0
	local function record(label: string, ok: boolean, msg: string)
		if ok then
			Debug.print("[Dr.SelfTest.Interop] PASS", label)
		else
			failures += 1
			Debug.warn("[Dr.SelfTest.Interop] FAIL", msg)
		end
	end

	local tests = {
		{
			name = "LegacyBridge requires the Debug module",
			fn = function()
				-- 相对路径：保留 WaitForChild（行为不变），但不再在加载/执行期碰 game
				local dbg = script.Parent.Parent.Parent.Parent:WaitForChild("Debug")
				local ok, mod = LegacyBridge.SafeRequire(dbg)
				expect(ok, "Debug required")
				expect(type(mod) == "table", "Debug returns table")
				local alsoOk = LegacyBridge.TryCall((mod :: any).print, "[test] legacy bridge")
				expect(alsoOk, "TryCall Debug.print")
			end,
		},
		{
			name = "LegacyBridge rejects a Folder",
			fn = function()
				local bad = Instance.new("Folder")
				local ok, err = LegacyBridge.SafeRequire(bad)
				expect(not ok, "must fail")
				expect(type(err) == "string", "error as string")
				bad:Destroy()
			end,
		},
		{
			name = "ExternalBridge facade returns (ok, ...) always",
			fn = function()
				local surface = {
					Good = function(x)
						return (x :: number) * 2
					end,
					Bad = function()
						error("boom")
					end,
				}
				local facade = ExternalBridge.Define("SelfTestVendor", surface)
				local goodOk, goodResult = facade.Good(21)
				expect(goodOk, "good call ok")
				expect(goodResult == 42, "good call value")
				local badOk = facade.Bad()
				expect(not badOk, "bad call caught")
			end,
		},
		{
			name = "ServerRegistry starts/stops in Studio fallback",
			fn = function()
				expect(ServerRegistry.Start() == true, "start ok")
				expect(ServerRegistry.IsRegistered(), "registered")
				ServerRegistry.Stop()
				expect(not ServerRegistry.IsRegistered(), "stopped")
			end,
		},
		{
			name = "ServerBrowser lists our own job",
			fn = function()
				ServerRegistry.Start()
				local list = ServerBrowser.ListServers()
				expect(type(list) == "table", "list is table")
				expect(#list >= 1, "at least one server")
				local ours = nil
				for _, entry in list do
					if entry.jobId == ServerRegistry.GetJobId() then
						ours = entry
						break
					end
				end
				expect(ours ~= nil, "contains our JobId")
			end,
		},
	}

	for _, entry in tests do
		local ok, msg = check(entry.name, entry.fn)
		record(entry.name, ok, msg)
	end

	Debug.print(("[Dr.SelfTest.Interop] %d/%d passed"):format(#tests - failures, #tests))
	return failures == 0
end

return SelfTest
