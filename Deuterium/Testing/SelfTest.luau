--!strict
-- Dr.Testing.SelfTest — TestKit self-acceptance + full W1.x chain end-to-end.
-- Command bar: require(game.ReplicatedStorage.Deuterium.Testing.SelfTest).RunAll()

local Debug = require(game:GetService("ReplicatedStorage"):WaitForChild("Debug"))

local RunContext = require(game:GetService("ReplicatedStorage").Deuterium.Runtime.Environment.RunContext)
local FeatureFlags = require(game:GetService("ReplicatedStorage").Deuterium.Runtime.Environment.FeatureFlags)
local Kernel = require(game:GetService("ReplicatedStorage").Deuterium.Core.Container.Kernel)
local Configuration = require(game:GetService("ReplicatedStorage").Deuterium.Core.Lifecycle.Configuration)
local Demo = require(game:GetService("ReplicatedStorage").Deuterium.Extensions.Demo)

local Suite = require(script.Parent.TestSuite)
local TestRunner = require(script.Parent.TestRunner)
local Assert = require(script.Parent.Assert)

local SelfTest = {}

function SelfTest.RunAll(): boolean
	assert(RunContext.IsStudio(), "[Dr.SelfTest.Testing] Studio-only")

	-- Surface check: TestKit must actually catch failures and report them.
	local metaSuite = Suite.Define("Dr.TestKit.Meta", function(t)
		t.Test("assert true passes", function()
			Assert.IsTrue(1 + 1 == 2, "arithmetic")
		end)
		t.Test("assert throws on failure", function()
			Assert.Throws(function()
				Assert.Equal(1, 2, "mismatch")
			end, "DR.TEST", "assert raises DrError")
		end)
		t.Test("equal works on frozen tables", function()
			Assert.Equal(table.freeze({ a = 1 }), table.freeze({ a = 1 }), "identity isn't the ask here")
		end)
	end)

	local summary = TestRunner.Run(metaSuite)
	if summary.failed ~= 0 then
		Debug.warn("[Dr.SelfTest.Testing] TestKit meta report failed", summary)
		return false
	end

	-- Kernel end-to-end with a bad provider.
	Kernel.Reset()
	local calls: { string } = {}
	local goodProvider = {
		Name = "W17.Good",
		Dependencies = {} :: { string },
		Init = function(self: any, _ctx: any)
			table.insert(calls, "Good.Init")
			self.Marker = "alive"
		end,
		Start = function(self: any)
			table.insert(calls, "Good.Start")
			Assert.IsTrue(self.Marker == "alive", "init state survived Start")
		end,
	}
	local badProvider = {
		Name = "W17.BadEgg",
		Init = function()
			error("intentional")
		end,
	}
	Kernel.Register(goodProvider)
	Kernel.Register(badProvider)
	local constructed = Kernel.Construct()
	Assert.IsTrue(constructed, "construct")
	local allHealthy = Kernel.Init()
	Assert.IsTrue(not allHealthy, "Init must report partial failure")
	Assert.IsTrue(Kernel.IsProviderFailed("W17.BadEgg"), "BadEgg marked failed")
	Kernel.Start()
	Assert.IsTrue(table.find(calls, "Good.Start") ~= nil, "good started")
	Assert.IsTrue(Kernel.GetState() == "Started", "kernel Started")

	-- Configuration + FeatureFlags around it.
	if not Configuration.IsLoaded() then
		Configuration.Load()
	end
	Assert.IsTrue(table.find(Configuration.SectionNames(), "FeatureFlags") ~= nil, "FeatureFlags section visible")
	if not FeatureFlags.IsLocked() then
		FeatureFlags.LoadFromConfig()
	end
	Assert.Equal(FeatureFlags.Get("Dr.Security.StrictSchema"), true, "strict schema flag on")

	-- Demo extension: clean boot + fault isolation with real registrations.
	Kernel.Reset()
	Kernel.Register(Demo.BadActor :: any)
	Kernel.Register(Demo.Provider :: any)
	Assert.IsTrue(Kernel.Construct(), "demo construct")
	Kernel.Init()
	Kernel.Start()
	Assert.IsTrue(Demo.WasStarted(), "demo started despite bad actor")
	Assert.IsTrue(Kernel.IsProviderFailed("W17.DemoBadActor"), "bad actor isolated")

	Debug.print("[Dr.SelfTest.Testing] end-to-end OK")
	return true
end

return table.freeze(SelfTest)
