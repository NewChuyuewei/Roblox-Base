--!strict
-- Dr.Runtime.Environment.FeatureFlags
-- Framework-level feature flags (NOT Roblox FFlags).
-- Lifecycle: Define/LoadFromConfig during Construct → Lock() at Init → pure reads.
-- Hardening:
--  * definitions are table.freeze'd on registration (no post-hoc tampering)
--  * every config entry is shape-validated on load (bad config fails loudly, never silently)
--  * reads are exactly one table lookup on the success path ([P0])

local RuntimeTypes = require(script.Parent.Parent.RuntimeTypes)
local RunContext = require(script.Parent.RunContext)

local NAME_PATTERN = "^[%a][%w_%.]*$"
local CONFIG_PATH_TIMEOUT = 5 -- seconds; WaitForChild must never hang Init

local _defs: { [string]: RuntimeTypes.FeatureFlagDef } = {}
-- Flattened effective values (resolved at Define time; RunContext is static per session).
local _effective: { [string]: boolean } = {}
local _locked: boolean = false

local FeatureFlags = {}

local function validateEntry(def: any, index: number): RuntimeTypes.FeatureFlagDef
	assert(type(def) == "table", `[Dr.FeatureFlags] config entry #{index} is not a table`)
	assert(type(def.name) == "string", `[Dr.FeatureFlags] config entry #{index}.name must be a string`)
	assert(
		type(def.default) == "boolean",
		`[Dr.FeatureFlags] config entry #{def.name}.default must be a boolean`
	)
	assert(
		def.studioOverride == nil or type(def.studioOverride) == "boolean",
		`[Dr.FeatureFlags] config entry #{def.name}.studioOverride must be boolean?`
	)
	return table.freeze({
		name = def.name :: string,
		default = def.default :: boolean,
		studioOverride = def.studioOverride,
	})
end

function FeatureFlags.Define(name: string, default: boolean, studioOverride: boolean?): ()
	assert(not _locked, "[Dr.FeatureFlags] Define called after Lock")
	assert(name:match(NAME_PATTERN) ~= nil, "[Dr.FeatureFlags] invalid flag name: " .. tostring(name))
	assert(_defs[name] == nil, "[Dr.FeatureFlags] duplicate flag: " .. name)
	_defs[name] = table.freeze({
		name = name,
		default = default,
		studioOverride = studioOverride,
	})
	-- Resolve the effective value oncc and flatten it: Get() stays one hash read.
	local effective = default
	if RunContext.IsStudio() and studioOverride ~= nil then
		effective = studioOverride
	end
	_effective[name] = effective
end

-- Construct-time entry: bulk-load flag definitions from
-- ReplicatedStorage/Configs/Deuterium/FeatureFlags (per project config layout).
function FeatureFlags.LoadFromConfig(): ()
	assert(not _locked, "[Dr.FeatureFlags] LoadFromConfig called after Lock")
	local configs = game:GetService("ReplicatedStorage"):WaitForChild("Configs", CONFIG_PATH_TIMEOUT)
	local deuterium = configs and configs:WaitForChild("Deuterium", CONFIG_PATH_TIMEOUT)
	local flagsModule = deuterium and deuterium:WaitForChild("FeatureFlags", CONFIG_PATH_TIMEOUT)
	assert(
		flagsModule ~= nil and flagsModule:IsA("ModuleScript"),
		"[Dr.FeatureFlags] config module Configs/Deuterium/FeatureFlags not found"
	)
	-- Static require path: luau-lsp only resolves requires whose argument is an
	-- instance path expression; the WaitForChild chain above still guards runtime.
	local defs =
		require(game:GetService("ReplicatedStorage").Configs.Deuterium.FeatureFlags) :: { RuntimeTypes.FeatureFlagConfigEntry }
	assert(type(defs) == "table", "[Dr.FeatureFlags] config module must return a table")
	for index, def in defs do
		local checked = validateEntry(def, index)
		FeatureFlags.Define(checked.name, checked.default, checked.studioOverride)
	end
end

-- Called once during Kernel init. After this, the flag set is immutable.
function FeatureFlags.Lock(): ()
	if _locked then
		return
	end
	table.freeze(_defs)
	table.freeze(_effective)
	_locked = true
end

function FeatureFlags.IsLocked(): boolean
	return _locked
end

-- [P0] one hash read on the success path; error path allocates only on failure.
function FeatureFlags.Get(name: string): boolean
	local value = _effective[name]
	if value == nil then
		error("[Dr.FeatureFlags] unknown flag: " .. name, 2)
	end
	return value
end

function FeatureFlags.Snapshot(): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for name, value in _effective do
		out[name] = value
	end
	return table.freeze(out)
end

return table.freeze(FeatureFlags)
