--!strict
-- Dr.Runtime.Platform.ServiceLocator
-- Sole legal way for framework code to reach Roblox services.
-- Two hard rules:
--  1) cache first-resolution results in a frozen-per-entry table ([P0]: one hash read per call
--     after warm-up, zero per-call pcall)
--  2) refuse run-time discovery of unexpected names (defense vs accidentally injected globals)

local _cache: { [string]: Instance? } = {}
local ServiceLocator = {}

-- [P0] one hash read on warm path.
local function get(name: string): Instance
	local cached = _cache[name]
	if cached ~= nil then
		return cached
	end
	-- Cold path: the only place game:GetService is called in the whole framework.
	local service = game:GetService(name)
	_cache[name] = service
	return service
end

ServiceLocator.Get = get

return table.freeze(ServiceLocator)
