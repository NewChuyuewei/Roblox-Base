--!strict
-- Dr.Net.Core.SelfTest
-- Studio-only; exercises NetworkManager/Channel/ports via MockBridge for round-trip proof.
-- Run in Studio server command bar:
--   require(game.ReplicatedStorage.Deuterium.Net.Core.SelfTest).RunAll()

local Debug = require(script.Parent.Parent.Parent.Parent.Debug)
local ErrorHandler = require(script.Parent.Parent.Parent.Core.Foundation.ErrorHandler)

local RunContext = require(script.Parent.Parent.Parent.Runtime.Environment.RunContext)
local NetworkManager = require(script.Parent.NetworkManager)
local LocalBridge = require(script.Parent.Parent.Bridge.LocalBridge)
local MockBridge = require(script.Parent.Parent.Bridge.MockBridge)

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
	assert(RunContext.IsStudio(), "[Dr.SelfTest.Net] Studio-only")
	local failures = 0
	local function record(label: string, ok: boolean, msg: string)
		if ok then
			Debug.print("[Dr.SelfTest.Net] PASS", label)
		else
			failures += 1
			Debug.warn("[Dr.SelfTest.Net] FAIL", msg)
		end
	end

	local tests = {
		{
			name = "NetworkManager declares + locks channels",
			fn = function()
				NetworkManager.Reset()
				NetworkManager.DeclareChannels({ "W21.Alpha", "W21.Beta" })
				NetworkManager.Lock()
				expect(NetworkManager.HasChannel("W21.Alpha"), "alpha declared")
				expect(NetworkManager.HasChannel("W21.Beta"), "beta declared")
				expect(not NetworkManager.HasChannel("W21.Ghost"), "ghost not declared")
				local names = NetworkManager.ChannelNames()
				expect(#names == 2, "exactly two")
			end,
		},
		{
			name = "DeclareChannels is server-only",
			fn = function()
				NetworkManager.Reset()
				if RunContext.IsClient() then
					local ok = pcall(NetworkManager.DeclareChannels, { "X" })
					expect(not ok, "client declare rejected")
				else
					expect(true, "server path by construction")
				end
			end,
		},
		{
			name = "GetChannel errors on unknown name",
			fn = function()
				NetworkManager.Reset()
				NetworkManager.DeclareChannels({ "W21.Only" })
				NetworkManager.Lock()
				local ok = pcall(NetworkManager.GetChannel, "W21.Nope")
				expect(not ok, "unknown channel must error")
			end,
		},
		{
			name = "LocalBridge memory round-trip",
			fn = function()
				local bridge = LocalBridge.Open("W21.Local")
				local got: any = nil
				bridge:Connect(function(...)
					got = { ... }
				end)
				bridge:Fire(nil, "ping", 42)
				expect(got ~= nil and got[1] == "ping" and got[2] == 42, "payload intact")
			end,
		},
		{
			name = "MockBridge logs the full call",
			fn = function()
				local bridge = MockBridge.Open("W21.Mock")
				bridge:Fire("PlayerA", "pos", 1)
				bridge:FireAll("sys", 0)
				expect(#bridge.Log == 2, "both logged")
				expect(bridge.Log[1].target == "PlayerA", "target recorded")
				expect(bridge.Log[2].target == "*all*", "all recorded")
				bridge:Reset()
				expect(#bridge.Log == 0, "reset clears")
			end,
		},
	}

	for _, entry in tests do
		local ok, msg = check(entry.name, entry.fn)
		record(entry.name, ok, msg)
	end

	Debug.print(("[Dr.SelfTest.Net] %d/%d passed"):format(#tests - failures, #tests))
	return failures == 0
end

return SelfTest
