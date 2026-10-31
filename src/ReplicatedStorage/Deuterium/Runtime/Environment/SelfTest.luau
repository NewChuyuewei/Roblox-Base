--!strict
-- Dr.Runtime.Environment.SelfTest
-- Minimal assert-based sanity checks; TestKit (W1.7) will formalize this.
-- Run in Studio server command bar:
--   require(game.ReplicatedStorage.Deuterium.Runtime.Environment.SelfTest).RunAll()

local Debug = require(script.Parent.Parent.Parent.Parent.Debug)
local ErrorHandler = require(script.Parent.Parent.Parent.Core.Foundation.ErrorHandler)

local RunContext = require(script.Parent.RunContext)
local EngineVersion = require(script.Parent.EngineVersion)
local FeatureFlags = require(script.Parent.FeatureFlags)

local SelfTest = {}

local function check(name: string, fn: () -> ()): (boolean, string)
	local err = ""
	-- xpcall keeps the signature single-valued; pcall(()->()) would type its 2nd return as never.
	local ok = xpcall(fn, function(e: unknown)
		err = ErrorHandler.Render(e)
	end)
	return ok, if ok then name else (name .. " -> " .. err)
end

function SelfTest.RunAll(): boolean
	-- Guard: self-test mutates the shared FeatureFlags registry (Lock/Define),
	-- which would wreck the real boot if executed in a live server.
	assert(RunContext.IsStudio(), "[Dr.SelfTest] Studio-only")
	local failures = 0
	local function record(label: string, ok: boolean, msg: string)
		if ok then
			Debug.print("[Dr.SelfTest] PASS", label)
		else
			failures += 1
			Debug.warn("[Dr.SelfTest] FAIL", msg)
		end
	end

	local function expect(cond: boolean, what: string)
		assert(cond, what)
	end

	local tests = {
		{
			name = "RunContext side consistent",
			fn = function()
				expect(RunContext.IsServer() ~= RunContext.IsClient(), "server/client xor")
				expect(
					RunContext.GetSide() == if RunContext.IsServer() then "Server" else "Client",
					"side value"
				)
			end,
		},
		{
			name = "RunContext kind enum",
			fn = function()
				local kind = RunContext.GetRunKind()
				expect(kind == "StudioEdit" or kind == "StudioPlay" or kind == "Production", "kind in set")
				expect(RunContext.IsProduction() == (kind == "Production"), "production flag")
			end,
		},
		{
			name = "EngineVersion non-empty",
			fn = function()
				expect(#EngineVersion.Get() > 0, "version string")
				expect(type(EngineVersion.GetInfo().studio) == "boolean", "engine info shape")
				expect(
					EngineVersion.HasEngineFeature("__DeuteriumDoesNotExist__") == false,
					"bogus feature is false"
				)
			end,
		},
		{
			name = "FeatureFlags config load",
			fn = function()
				FeatureFlags.LoadFromConfig()
				expect(FeatureFlags.Get("Dr.Security.StrictSchema") == true, "config flag readable")
				local snap = FeatureFlags.Snapshot()
				expect(type(snap["Dr.Diagnostics.StructuredLogs"]) == "boolean", "snapshot")
				-- config table must be frozen (tamper-proof)
				-- 相对路径（原来是跨行的绝对 require）：以便本套件在 headless 下也能被装载
				local raw = require(script.Parent.Parent.Parent.Parent.Configs.Deuterium.FeatureFlags)
				expect(table.isfrozen(raw), "config table frozen")
				expect(table.isfrozen(raw[1]), "config entry frozen")
				expect(pcall(FeatureFlags.Get, "Dr.Security.StrictSchema") == true, "get after lock ok")
			end,
		},
		{
			name = "FeatureFlags guards",
			fn = function()
				local okUnknown = pcall(FeatureFlags.Get, "SelfTest.Missing")
				expect(not okUnknown, "unknown flag errors")
				FeatureFlags.Lock()
				local okLate = pcall(FeatureFlags.Define, "SelfTest.Late", true)
				expect(not okLate, "define after lock errors")
				-- double-load after lock must fail
				local okReload = pcall(FeatureFlags.LoadFromConfig)
				expect(not okReload, "reload after lock errors")
				expect(FeatureFlags.IsLocked(), "locked")
			end,
		},
	}

	for _, entry in tests do
		local ok, msg = check(entry.name, entry.fn)
		record(entry.name, ok, msg)
	end

	Debug.print(("[Dr.SelfTest] %d/%d passed"):format(#tests - failures, #tests))
	return failures == 0
end

return SelfTest
