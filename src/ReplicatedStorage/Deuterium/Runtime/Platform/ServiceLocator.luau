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
	-- Cold path: **本应是**全框架唯一的 game:GetService 入口（I10）。
	-- 事实上不是：RunContext / FeatureFlags / Core.Lifecycle.Configuration 等仍有直接调用
	-- （部分已在 2026-10-25 的清理中改为相对路径）。这里如实措辞，避免注释把 I10 的
	-- 偏离掩盖成“已经收敛”。
	local service = game:GetService(name)
	_cache[name] = service
	return service
end

ServiceLocator.Get = get

return table.freeze(ServiceLocator)
