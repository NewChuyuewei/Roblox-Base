--!strict
-- Dr.Runtime.Platform.PhysicsProxy
-- The only framework surface allowed to touch workspace physics.
-- Deliberate choices:
--  * WithinDistance uses squared magnitude (no sqrt) — hot-path safe.
--  * Raycast returns boolean-first so callers can branch without unpacking nil results.
--  * WithinDistance/Raycast/DistanceSquared are allocation-free ([P0] safe);
--    LineOfSight allocates one RaycastParams per call — per-interaction path, never per-frame.

local Platform = script.Parent
local ServiceLocator = require(Platform.ServiceLocator)

-- 懒取 Workspace：加载期不碰引擎。原来在这一行直接取服务，使本模块（以及任何 require 它
-- 的模块）在 headless 下无法装载；这是全量装载巡检里最后一个卡在 ServiceLocator.Get 的点。
local _workspace: Workspace? = nil
local function workspace(): Workspace
	if _workspace == nil then
		_workspace = ServiceLocator.Get("Workspace") :: Workspace
	end
	return _workspace :: Workspace
end

local PhysicsProxy = {}

-- Squared distance is enough for threshold checks ([P0]).
function PhysicsProxy.WithinDistance(a: Vector3, b: Vector3, maxDistance: number): boolean
	assert(maxDistance >= 0, "[Dr.PhysicsProxy] maxDistance must be >= 0")
	local dx = a.X - b.X
	local dy = a.Y - b.Y
	local dz = a.Z - b.Z
	return (dx * dx + dy * dy + dz * dz) <= maxDistance * maxDistance
end

function PhysicsProxy.DistanceSquared(a: Vector3, b: Vector3): number
	local dx = a.X - b.X
	local dy = a.Y - b.Y
	local dz = a.Z - b.Z
	return dx * dx + dy * dy + dz * dz
end

-- Returns (hit: boolean, result: RaycastResult?). Callers that only need the bool
-- never pay for the result table unpack.
function PhysicsProxy.Raycast(
	origin: Vector3,
	direction: Vector3,
	params: RaycastParams?
): (boolean, RaycastResult?)
	local result = workspace():Raycast(origin, direction, params)
	return result ~= nil, result
end

-- Convenience: server-side "can A see B" line-of-sight with optional ignore list.
function PhysicsProxy.LineOfSight(from: Vector3, to: Vector3, ignoreInstances: { Instance }?): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	if ignoreInstances ~= nil then
		params.FilterDescendantsInstances = ignoreInstances
	end
	local hit = workspace():Raycast(from, to - from, params)
	return hit == nil
end

return table.freeze(PhysicsProxy)
