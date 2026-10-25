--!strict
-- Dr.Core.Reflection.Proxy
-- Read-through proxy over an existing module surface: forwards reads, blocks writes.
-- Use case: hand a third-party extension a handle it literally cannot damage.
-- Known limitation: rawset() bypasses __newindex. Anything truly untrusted must run in
-- an Isolate (W5+), not a Proxy; this is a polite wall, not a sandbox.

local Proxy = {}

local function blockWrite(field: any): never
	error(`[Dr.Proxy] write blocked: {tostring(field)}`, 2)
end

-- Wrap `target` so callers can read but never mutate. The proxy itself is unfrozen
-- on purpose (freezing would kill __newindex).
function Proxy.Watch(target: any): any
	assert(type(target) == "table", "[Dr.Proxy] target must be a table")
	local proxy = setmetatable({}, {
		__index = target,
		__newindex = function(_t, field)
			blockWrite(field)
		end,
		__metatable = "locked",
	})
	return proxy
end

return table.freeze(Proxy)
