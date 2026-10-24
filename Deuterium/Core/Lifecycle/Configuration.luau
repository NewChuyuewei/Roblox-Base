--!strict
-- Dr.Core.Lifecycle.Configuration
-- Single interface for config section access. Backed by ReplicatedStorage/Configs/Deuterium
-- (manifest module `init.luau`). Read-only, frozen, loud-on-missing.

local ErrorHandler = require(script.Parent.Parent.Foundation.ErrorHandler)

local Configuration = {}

local _manifest: { [string]: any }? = nil
local _locked = false

-- Boot-time load. Manifest must return a table of sections; each section must be a table.
function Configuration.Load(): ()
	assert(not _locked, "[Dr.Configuration] Load after manifest frozen")
	local configs = game:GetService("ReplicatedStorage"):WaitForChild("Configs", 5)
	local deuterium = configs and configs:WaitForChild("Deuterium", 5)
	assert(
		deuterium ~= nil and deuterium:IsA("ModuleScript"),
		"[Dr.Configuration] Configs/Deuterium manifest module missing"
	)

	local ok, manifest = pcall(require, deuterium)
	assert(ok, `[Dr.Configuration] manifest require failed: {tostring(manifest)}`)
	assert(type(manifest) == "table", "[Dr.Configuration] manifest must return a table")

	local clean: { [string]: any } = {}
	for name, section in manifest :: { [string]: any } do
		assert(type(name) == "string", "[Dr.Configuration] manifest key must be a string")
		assert(type(section) == "table", `[Dr.Configuration] section {name} must be a table`)
		clean[name] = table.freeze(section)
	end
	_manifest = table.freeze(clean)
	_locked = true
end

-- Section read. Unknown section = programmer error, not runtime jitter.
function Configuration.Section(name: string): any
	assert(_manifest ~= nil, "[Dr.Configuration] Section() before Load()")
	local section = _manifest[name]
	if section == nil then
		ErrorHandler.Raise("DR.CONFIG.MISSING", `unknown config section: {name}`, "Dr.Configuration")
	end
	return section
end

function Configuration.IsLoaded(): boolean
	return _locked
end

function Configuration.SectionNames(): { string }
	assert(_manifest ~= nil, "[Dr.Configuration] SectionNames() before Load()")
	local out = {}
	for name in _manifest :: { [string]: any } do
		table.insert(out, name)
	end
	table.sort(out)
	return table.freeze(out)
end

return table.freeze(Configuration)
