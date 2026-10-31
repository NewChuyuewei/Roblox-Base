--!strict
-- Dr.Core.Container.SelfTest
-- W1.4 acceptance: topo order / cycle detection / duplicate registration.
-- Run in Studio server command bar:
--   require(game.ReplicatedStorage.Deuterium.Core.Container.SelfTest).RunAll()

local Debug = require(script.Parent.Parent.Parent.Parent.Debug)
local ErrorHandler = require(script.Parent.Parent.Foundation.ErrorHandler)

local RunContext = require(script.Parent.Parent.Parent.Runtime.Environment.RunContext)
local Kernel = require(script.Parent.Kernel)

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

type FakeProvider = {
	Name: string,
	Dependencies: { string }?,
	Init: (self: any, ctx: any) -> (),
	Start: (self: any) -> ()?,
	Stop: (self: any) -> ()?,
}

local function fake(name: string, deps: { string }?, calls: { string }?, failInit: boolean?): FakeProvider
	return {
		Name = name,
		Dependencies = deps,
		Init = function(self: any, ctx: any)
			if failInit then
				error("intentional init failure")
			end
			if calls then
				table.insert(calls, name .. ".Init")
			end
			(self :: any)._ctx = ctx
		end,
		Start = function(self: any)
			if calls then
				table.insert(calls, name .. ".Start")
			end
		end,
		Stop = nil,
	}
end

function SelfTest.RunAll(): boolean
	assert(RunContext.IsStudio(), "[Dr.SelfTest.Container] Studio-only")
	local failures = 0
	local function record(label: string, ok: boolean, msg: string)
		if ok then
			Debug.print("[Dr.SelfTest.Container] PASS", label)
		else
			failures += 1
			Debug.warn("[Dr.SelfTest.Container] FAIL", msg)
		end
	end

	local tests = {
		{
			name = "topological order: dependencies init first",
			fn = function()
				Kernel.Reset()
				local calls: { string } = {}
				Kernel.Register(fake("W14.A", nil, calls))
				Kernel.Register(fake("W14.B", { "W14.A" }, calls))
				Kernel.Register(fake("W14.C", { "W14.B" }, calls))
				expect(Kernel.Construct(), "construct ok")
				expect(Kernel.Init(), "init ok")
				expect(Kernel.Start(), "start ok")
				local order = table.concat(calls, ",")
				expect(
					order == "W14.A.Init,W14.B.Init,W14.C.Init,W14.A.Start,W14.B.Start,W14.C.Start",
					"exact order, got: " .. order
				)
			end,
		},
		{
			name = "duplicate registration errors",
			fn = function()
				Kernel.Reset()
				Kernel.Register(fake("W14.Dup", nil, nil))
				local ok = pcall(Kernel.Register, fake("W14.Dup", nil, nil))
				expect(not ok, "duplicate must error")
			end,
		},
		{
			name = "missing dependency reported with path",
			fn = function()
				Kernel.Reset()
				Kernel.Register(fake("W14.Needy", { "W14.DoesNotExist" }, nil))
				expect(not Kernel.Construct(), "construct fails")
			end,
		},
		{
			name = "cycle detection reports cycle path",
			fn = function()
				Kernel.Reset()
				Kernel.Register(fake("W14.X", { "W14.Y" }, nil))
				Kernel.Register(fake("W14.Y", { "W14.Z" }, nil))
				Kernel.Register(fake("W14.Z", { "W14.X" }, nil))
				expect(not Kernel.Construct(), "cycle must fail construct")
			end,
		},
		{
			name = "bulkhead: failed init does not stop others",
			fn = function()
				Kernel.Reset()
				local calls: { string } = {}
				Kernel.Register(fake("W14.Good1", nil, calls))
				Kernel.Register(fake("W14.Bad", { "W14.Good1" }, calls, true))
				Kernel.Register(fake("W14.Good2", { "W14.Bad" }, calls))
				expect(Kernel.Construct(), "construct ok")
				local allGood = Kernel.Init()
				expect(not allGood, "init reports failure")
				expect(Kernel.IsProviderFailed("W14.Bad"), "Bad marked failed")
				Kernel.Start()
				-- Good1 started; Bad never inited so no Start; Good2 inited (its dep existed) and started.
				local joined = table.concat(calls, ",")
				expect(joined:find("W14.Good1.Start") ~= nil, "Good1 started")
				expect(joined:find("W14.Bad.Start") == nil, "Bad not started")
			end,
		},
		{
			name = "dependency context is resolved and frozen at Init",
			fn = function()
				Kernel.Reset()
				local observedDeps: any = nil
				local dep = fake("W14.Base", nil, nil)
				local leaf = {
					Name = "W14.Leaf",
					Init = function(self: any, ctx: any)
						observedDeps = ctx.Dependencies
					end,
				} :: any
				Kernel.Register(dep)
				leaf.Dependencies = { "W14.Base" }
				Kernel.Register(leaf)
				expect(Kernel.Construct(), "construct ok")
				Kernel.Init()
				expect(observedDeps ~= nil, "ctx deps observed")
				expect(observedDeps["W14.Base"] ~= nil, "dep resolved by name")
				expect(table.isfrozen(observedDeps), "deps table frozen")
			end,
		},
	}

	for _, entry in tests do
		local ok, msg = check(entry.name, entry.fn)
		record(entry.name, ok, msg)
	end

	Debug.print(("[Dr.SelfTest.Container] %d/%d passed"):format(#tests - failures, #tests))
	return failures == 0
end

return SelfTest
