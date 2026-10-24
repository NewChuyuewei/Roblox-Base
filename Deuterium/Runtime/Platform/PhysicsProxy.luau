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

local Workspace = ServiceLocator.Get("Workspace") :: Workspace

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
function PhysicsProxy.Raycast(origin: Vector3, direction: Vector3, params: RaycastParams?): (boolean, RaycastResult?)
	local result = Workspace:Raycast(origin, direction, params)
	return result ~= nil, result
end

-- Convenience: server-side "can A see B" line-of-sight with optional ignore list.
function PhysicsProxy.LineOfSight(from: Vector3, to: Vector3, ignoreInstances: { Instance }?): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	if ignoreInstances ~= nil then
		params.FilterDescendantsInstances = ignoreInstances
	end
	local hit = Workspace:Raycast(from, to - from, params)
	return hit == nil
end

return table.freeze(PhysicsProxy)
