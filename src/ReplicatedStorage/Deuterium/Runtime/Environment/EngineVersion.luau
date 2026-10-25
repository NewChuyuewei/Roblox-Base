--!strict
--!nolint DeprecatedApi
-- Dr.Runtime.Environment.EngineVersion
-- Thin read-only facade over the engine version + optional engine features.
-- - `version()` has no modern equivalent; it is the canonical engine build string.
-- - HasEngineFeature results are cached: a feature flag never flips mid-session.
-- No writes, no logging.

local RunContext = require(script.Parent.RunContext)
local RuntimeTypes = require(script.Parent.Parent.RuntimeTypes)

local ok, engineVersion: unknown = pcall(version)
local cachedVersion: string = if ok and type(engineVersion) == "string" then engineVersion else "unknown"

local featureCache: { [string]: boolean } = {}

-- Info is session-static; one frozen singleton instead of per-call allocation.
local engineInfo: RuntimeTypes.EngineInfo = table.freeze({
	version = cachedVersion,
	studio = RunContext.IsStudio(),
})

local EngineVersion = {}

function EngineVersion.Get(): string
	return cachedVersion
end

function EngineVersion.GetInfo(): RuntimeTypes.EngineInfo
	return engineInfo
end

-- Read-only probe; unknown or absent names return false instead of throwing.
-- Results are memoized so repeated probes stay allocation-free.
function EngineVersion.HasEngineFeature(name: string): boolean
	if type(name) ~= "string" or name == "" then
		return false
	end
	local cached = featureCache[name]
	if cached ~= nil then
		return cached
	end
	local probeOk, result = pcall(function()
		return game:GetEngineFeature(name)
	end)
	local has: boolean = probeOk and result == true
	featureCache[name] = has
	return has
end

return table.freeze(EngineVersion)
