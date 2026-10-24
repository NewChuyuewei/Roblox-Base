--!strict
-- Dr.Runtime.Platform.SelfTest
-- Same style as Environment.SelfTest: assert-based, Studio-only, formalized later by TestKit.
-- Run in Studio server command bar:
--   require(game.ReplicatedStorage.Deuterium.Runtime.Platform.SelfTest).RunAll()

local Debug = require(game:GetService("ReplicatedStorage"):WaitForChild("Debug"))
local ErrorHandler = require(game:GetService("ReplicatedStorage").Deuterium.Core.Foundation.ErrorHandler)

local RunContext = require(script.Parent.Parent.Environment.RunContext)
local ServiceLocator = require(script.Parent.ServiceLocator)
local InstanceTracker = require(script.Parent.InstanceTracker)
local PhysicsProxy = require(script.Parent.PhysicsProxy)

local SelfTest = {}

local function check(name: string, fn: () -> ()): (boolean, string)
	local err: unknown = nil
	local ok = xpcall(fn, function(e)
		err = ErrorHandler.Render(e)
	end)
	return ok, if ok then name else (name .. " -> " .. tostring(err))
end

function SelfTest.RunAll(): boolean
	assert(RunContext.IsStudio(), "[Dr.SelfTest] Studio-only")
	local failures = 0
	local function record(label: string, ok: boolean, msg: string)
		if ok then
			Debug.print("[Dr.SelfTest.Platform] PASS", label)
		else
			failures += 1
			Debug.warn("[Dr.SelfTest.Platform] FAIL", msg)
		end
	end

	local function expect(cond: boolean, what: string)
		assert(cond, what)
	end

	local tests = {
		{
			name = "ServiceLocator resolves real services",
			fn = function()
				local players = ServiceLocator.Get("Players")
				expect(typeof(players) == "Instance", "returns Instance")
				expect(players.ClassName == "Players", "right service")
				local players2 = ServiceLocator.Get("Players")
				expect(rawequal(players, players2), "memoized identity")
			end,
		},
		{
			name = "ServiceLocator denies garbage names",
			fn = function()
				-- Empty / nonsense service names must surface as an engine error, not nil-swallowing.
				local ok1 = pcall(ServiceLocator.Get, "")
				expect(not ok1, "empty name must error")
				local ok2 = pcall(ServiceLocator.Get, "__NotAService__")
				expect(not ok2, "nonsense name must error")
			end,
		},
		{
			name = "InstanceTracker track/release/idempotent",
			fn = function()
				local inst = Instance.new("Folder")
				local handle = InstanceTracker.Track(inst)
				expect(handle.Instance == inst, "handle references instance")
				expect(InstanceTracker.IsTracked(inst), "tracked")
				expect(InstanceTracker.Release(handle), "first release ok")
				expect(InstanceTracker.Release(handle) == false, "idempotent second release")
				expect(InstanceTracker.IsTracked(inst) == false, "no longer tracked")
				inst:Destroy()
			end,
		},
		{
			name = "InstanceTracker auto-drop on Destroy",
			fn = function()
				local inst = Instance.new("Folder")
				InstanceTracker.Track(inst)
				inst:Destroy()
				-- Destroying may dispatch deferred; give it one beat before asserting.
				task.wait()
				expect(
					InstanceTracker.IsTracked(inst) == false or InstanceTracker.Count() == 0,
					"dead instance must not leak"
				)
			end,
		},
		{
			name = "PhysicsProxy distance math (squared)",
			fn = function()
				expect(PhysicsProxy.WithinDistance(Vector3.zero, Vector3.new(3, 0, 4), 5.0), "3-4-5 within 5")
				expect(
					PhysicsProxy.WithinDistance(Vector3.zero, Vector3.new(3, 0, 4), 4.9) == false,
					"3-4-5 outside 4.9"
				)
				expect(PhysicsProxy.DistanceSquared(Vector3.zero, Vector3.new(3, 0, 4)) == 25, "squared distance exact")
			end,
		},
		{
			name = "PhysicsProxy raycast returns boolean-first",
			fn = function()
				-- Pointing straight up from high above origin should normally miss in an empty baseplate scene,
				-- so we don't assert hit-vs-miss, only the boolean contract.
				local hit, result = PhysicsProxy.Raycast(Vector3.new(0, 1000, 0), Vector3.new(0, 100, 0))
				expect(type(hit) == "boolean", "first return is boolean")
				expect(hit == (result ~= nil), "boolean matches result presence")
			end,
		},
	}

	for _, entry in tests do
		local ok, msg = check(entry.name, entry.fn)
		record(entry.name, ok, msg)
	end

	Debug.print(("[Dr.SelfTest.Platform] %d/%d passed"):format(#tests - failures, #tests))
	return failures == 0
end

return SelfTest
