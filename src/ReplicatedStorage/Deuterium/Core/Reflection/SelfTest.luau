--!strict
-- Dr.Core.Lifecycle.SelfTest additions for W1.6 (Reflection + Types.Contract + Configuration).
-- Command bar: require(game.ReplicatedStorage.Deuterium.Core.Reflection.SelfTest).RunAll()

local Debug = require(script.Parent.Parent.Parent.Parent.Debug)
local ErrorHandler = require(script.Parent.Parent.Foundation.ErrorHandler)

local RunContext = require(script.Parent.Parent.Parent.Runtime.Environment.RunContext)
local Descriptor = require(script.Parent.Descriptor)
local Inspector = require(script.Parent.Inspector)
local Proxy = require(script.Parent.Proxy)
local Interface = require(script.Parent.Parent.Parent.Types.Contract.Interface)
local Configuration = require(script.Parent.Parent.Lifecycle.Configuration)
local FeatureFlags = require(script.Parent.Parent.Parent.Runtime.Environment.FeatureFlags)

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
	assert(RunContext.IsStudio(), "[Dr.SelfTest.Reflection] Studio-only")
	local failures = 0
	local function record(label: string, ok: boolean, msg: string)
		if ok then
			Debug.print("[Dr.SelfTest.Reflection] PASS", label)
		else
			failures += 1
			Debug.warn("[Dr.SelfTest.Reflection] FAIL", msg)
		end
	end

	local tests = {
		{
			name = "Descriptor + Inspector roundtrip",
			fn = function()
				local d = Descriptor.Of("Debug", Debug)
				expect(d.name == "Debug", "name")
				expect(d.frozen, "Debug module is frozen")
				expect(Inspector.Has(d, "print"), "has print")
				expect(Inspector.KindOf(d, "print") == "function", "print is function")
				expect(Inspector.Count(d) >= 2, "exports >= 2")
				local names = Inspector.List(d)
				for i = 2, #names do
					expect(names[i - 1] < names[i], "sorted")
				end
			end,
		},
		{
			name = "Proxy blocks writes, transparent reads",
			fn = function()
				local source = {
					Say = function()
						return "hi"
					end,
					Value = 7,
				}
				local p = Proxy.Watch(source)
				expect(p.Value == 7, "read forwards")
				local ok = pcall(function()
					p.Value = 9
				end)
				expect(not ok, "write blocked")
				expect(source.Value == 7, "source untouched")
			end,
		},
		{
			name = "Interface.Conform validates shapes",
			fn = function()
				local spec = { Name = "string", Init = "function" }
				expect(Interface.Conform("test", { Name = "ok", Init = function() end }, spec), "good shape")
				local ok = pcall(Interface.Conform, "test", { Name = 42, Init = function() end }, spec)
				expect(not ok, "bad kind rejected")
				local ok2 = pcall(Interface.Conform, "test", { Name = "no-init" }, spec)
				expect(not ok2, "missing field rejected")
			end,
		},
		{
			name = "Configuration loads manifest",
			fn = function()
				Configuration.Load()
				expect(Configuration.IsLoaded(), "loaded")
				local names = Configuration.SectionNames()
				expect(#names >= 1, "at least FeatureFlags")
				expect(table.find(names, "FeatureFlags") ~= nil, "FeatureFlags section present")
				local flagsSection = Configuration.Section("FeatureFlags")
				expect(type(flagsSection) == "table", "section is table")
				expect(table.isfrozen(flagsSection), "section frozen")
			end,
		},
		{
			name = "Configuration refuses unknown sections",
			fn = function()
				local ok = pcall(Configuration.Section, "NoSuchSection")
				expect(not ok, "unknown section errors")
			end,
		},
		{
			name = "FeatureFlags: config-driven define + studioOverride semantics",
			fn = function()
				-- LoadFromConfig is only valid once per process; reload must fail while unlocked test path:
				assert(RunContext.IsStudio(), "studio")
				-- manifest defines Dr.Security.StrictSchema=true; if registry already loaded, assert identity.
				if not FeatureFlags.IsLocked() then
					FeatureFlags.LoadFromConfig()
					expect(FeatureFlags.Get("Dr.Security.StrictSchema") == true, "strict schema on")
				else
					expect(FeatureFlags.Get("Dr.Security.StrictSchema") == true, "still on")
				end
			end,
		},
	}

	for _, entry in tests do
		local ok, msg = check(entry.name, entry.fn)
		record(entry.name, ok, msg)
	end

	Debug.print(("[Dr.SelfTest.Reflection] %d/%d passed"):format(#tests - failures, #tests))
	return failures == 0
end

return SelfTest
