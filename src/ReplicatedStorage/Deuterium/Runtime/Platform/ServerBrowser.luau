--!strict
-- Dr.Runtime.Platform.ServerBrowser
-- Read-only view over the ServerRegistry map.
-- Scope decisions (honest for W1.3):
--  * Studio: returns this server as the only entry — you only have one server there anyway.
--  * Live: GetRangeAsync, defensive — any shape anomaly drops that entry instead of throwing.

local ServerRegistry = require(script.Parent.ServerRegistry)
local ServiceLocator = require(script.Parent.ServiceLocator)
local RunContext = require(script.Parent.Parent.Environment.RunContext)

local REGISTRY_MAP = "Dr.ServerRegistry"

local ServerBrowser = {}

export type ServerEntry = {
	jobId: string,
	startedAt: number,
}

-- Read-only; safe to call anywhere (server-side reads only make sense in production).
function ServerBrowser.ListServers(): { ServerEntry }
	if not RunContext.IsProduction() then
		return { { jobId = ServerRegistry.GetJobId(), startedAt = os.time() } }
	end
	local memoryStore = ServiceLocator.Get("MemoryStoreService") :: MemoryStoreService
	-- 同上：获取 sortedMap 也要 pcall 包裹，否则服务故障会抛出而非降级为空列表。
	-- 写成“先声明为 any 再赋值”：若用 `local ok, map = pcall(...)`，Luau 会把 map 推断为
	-- MemoryStoreSortedMap（非空），于是 `map == nil` 在 --!strict 下报
	-- “MemoryStoreSortedMap and nil cannot be compared”。
	local sortedMap: any = nil
	local okMap = pcall(function()
		sortedMap = memoryStore:GetSortedMap(REGISTRY_MAP)
	end)
	if not okMap or sortedMap == nil then
		return {}
	end
	local ok, items = pcall(function()
		return sortedMap:GetRangeAsync(Enum.SortDirection.Ascending, 100)
	end)
	if not ok or type(items) ~= "table" then
		return {}
	end
	local out: { ServerEntry } = {}
	for _, item in items do
		local entry = item :: { key: unknown, value: unknown }
		local key = entry.key
		local value = entry.value
		if type(key) == "string" and type(value) == "table" then
			local startedAt = (value :: { startedAt: unknown }).startedAt
			if type(startedAt) == "number" then
				table.insert(out, { jobId = key, startedAt = startedAt })
			end
		end
	end
	return out
end

function ServerBrowser.Count(): number
	return #ServerBrowser.ListServers()
end

return table.freeze(ServerBrowser)
