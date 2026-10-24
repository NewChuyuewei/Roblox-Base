--!strict
-- Dr.Runtime.Platform.InstanceTracker
-- What it is: a lightweight ownership registry so Deuterium never leaks Instances.
-- Rules:
--  * Track(inst) returns a frozen TrackHandle; callers may only Release(handle).
--  * Releases are idempotent — double-release is a no-op, not an error.
--  * An instance being Destroy()ed drops itself from the registry automatically
--    (no dangling references survive a destroy).

local RuntimeTypes = require(script.Parent.Parent.RuntimeTypes)

local InstanceTracker = {}

-- Weak keys: a forgotten instance that is GC'd without Destroy must never leak.
-- Values are `true` for membership only; typed boolean to allow nil-out on release.
-- Plain tables, no weak keys: in Roblox an Instance that goes away without Destroy()
-- essentially never happens (engine references anchor it), and weak tables scramble
-- strict-mode typing. Destroy-driven auto-drop below is the real leak guard.
local _live: { [Instance]: boolean } = {}
local _destroyConns: { [Instance]: RBXScriptConnection? } = {}

function InstanceTracker.Track(inst: Instance): RuntimeTypes.TrackHandle
	assert(typeof(inst) == "Instance", "[Dr.InstanceTracker] Track expects an Instance")
	if _live[inst] ~= true then
		_live[inst] = true
		-- Auto-drop on Destroy: Destroying fires before the instance is torn down.
		_destroyConns[inst] = inst.Destroying:Connect(function()
			_live[inst] = nil
			_destroyConns[inst] = nil
		end)
	end
	return table.freeze({ Instance = inst })
end

-- [P0] one lookup, then removal.
function InstanceTracker.Release(handle: RuntimeTypes.TrackHandle): boolean
	local inst = handle.Instance
	if _live[inst] ~= true then
		return false
	end
	_live[inst] = nil
	local conn = _destroyConns[inst]
	if conn ~= nil then
		conn:Disconnect()
		_destroyConns[inst] = nil
	end
	return true
end

function InstanceTracker.IsTracked(inst: Instance): boolean
	return _live[inst] == true
end

function InstanceTracker.Count(): number
	local n = 0
	for _ in _live do
		n += 1
	end
	return n
end

-- Safety net: bulk-release everything still alive (used by ShutdownManager later).
function InstanceTracker.ReleaseAll(): number
	local n = 0
	for inst, conn in _destroyConns do
		if conn ~= nil then
			conn:Disconnect()
		end
		_live[inst] = nil
		_destroyConns[inst] = nil
		n += 1
	end
	return n
end

return table.freeze(InstanceTracker)
