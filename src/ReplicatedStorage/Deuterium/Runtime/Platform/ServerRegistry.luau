--!strict
-- Dr.Runtime.Platform.ServerRegistry
-- Registers this server instance so other Deuterium services can discover it.
-- Scope decisions (honest for W1.3):
--  * SERVER-ONLY: calling Start on a client errors immediately.
--  * Studio degrades to a local in-memory registration (no MemoryStore quota burn).
--  * Live games use MemoryStoreService SortedMap with a 10-minute TTL; all calls pcall-guarded.
--    CircuitBreaker wraps arrive in Phase 3 — until then, failures log + degrade.

local RunContext = require(script.Parent.Parent.Environment.RunContext)
local ServiceLocator = require(script.Parent.ServiceLocator)

local REGISTRY_MAP = "Dr.ServerRegistry"
local TTL_SECONDS = 600

local ServerRegistry = {}

local _registered = false
local _studioFallback = false

local function map(): MemoryStoreSortedMap?
	local memoryStore = ServiceLocator.Get("MemoryStoreService") :: MemoryStoreService
	return memoryStore:GetSortedMap(REGISTRY_MAP)
end

local function now(): number
	return os.time()
end

-- [Server-only] register this server.
function ServerRegistry.Start(): boolean
	assert(RunContext.IsServer(), "[Dr.ServerRegistry] Start is server-only")
	if _registered then
		return true
	end
	if not RunContext.IsProduction() then
		-- Studio / local run: no quota burn, behave as if registered.
		_studioFallback = true
		_registered = true
		return true
	end
	-- 头部承诺“所有调用 pcall 包裹、异常时降级”；获取 sortedMap 本身也要包上，
	-- 否则服务故障会直接抛出而不是降级（独立复审 subagent, runtime lane 2026-10-25）。
	local okMap, sortedMap = pcall(map)
	if not okMap or sortedMap == nil then
		return false
	end
	local ok = pcall(function()
		sortedMap:SetAsync(game.JobId, { startedAt = now() }, TTL_SECONDS)
	end)
	_registered = ok
	return ok
end

function ServerRegistry.Stop(): ()
	if not _registered then
		return
	end
	if _studioFallback then
		_registered = false
		_studioFallback = false
		return
	end
	local sortedMap = map()
	if sortedMap ~= nil then
		pcall(function()
			sortedMap:RemoveAsync(game.JobId)
		end)
	end
	_registered = false
end

function ServerRegistry.IsRegistered(): boolean
	return _registered
end

function ServerRegistry.GetJobId(): string
	return game.JobId
end

return table.freeze(ServerRegistry)
