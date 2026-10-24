--!strict
-- Dr.Runtime.Environment.RunContext
-- Snapshot of "where am I running" taken once at require time.
-- Engine state cannot change mid-session, so caching is the philosophy:
-- callers get zero per-call cost ([P0] safe getters), never re-query RunService.
-- All probes are pcall-guarded: RunService APIs must never crash module init.

local RunService = game:GetService("RunService")

local RuntimeTypes = require(script.Parent.Parent.RuntimeTypes)

local function probe(fn: () -> boolean): boolean
	local ok, result = pcall(fn)
	return ok and result == true
end

local isServer: boolean = probe(function()
	return RunService:IsServer()
end)
local isStudio: boolean = probe(function()
	return RunService:IsStudio()
end)
local isRunMode: boolean = probe(function()
	return RunService:IsRunMode()
end)

local side: RuntimeTypes.Side = if isServer then "Server" else "Client"
local runKind: RuntimeTypes.RunKind = if not isStudio
	then "Production"
	elseif isRunMode then "StudioPlay"
	else "StudioEdit"

local RunContext = {}

-- [P0] pure read of cached value
function RunContext.IsServer(): boolean
	return isServer
end

function RunContext.IsClient(): boolean
	return not isServer
end

function RunContext.IsStudio(): boolean
	return isStudio
end

function RunContext.GetSide(): RuntimeTypes.Side
	return side
end

function RunContext.GetRunKind(): RuntimeTypes.RunKind
	return runKind
end

function RunContext.IsProduction(): boolean
	return runKind == "Production"
end

return table.freeze(RunContext)
