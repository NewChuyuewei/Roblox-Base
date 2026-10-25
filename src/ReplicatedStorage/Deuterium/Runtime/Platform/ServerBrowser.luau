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
	local sortedMap = memoryStore:GetSortedMap(REGISTRY_MAP)
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
