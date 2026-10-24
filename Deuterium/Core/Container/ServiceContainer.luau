--!strict
-- Dr.Core.Container.ServiceContainer
-- The single-responsibility store for provider instances after Construct.
-- Zero dynamic lookup after Construct: every entry is written exactly once,
-- then the whole table is frozen. [P0] Get = one hash read.

local ServiceContainer = {}

local _instances: { [string]: any } = {}

-- Kernel-internal: only Construct writes here.
function ServiceContainer.Set(name: string, instance: any): ()
	assert(not table.isfrozen(_instances), "[Dr.ServiceContainer] Set after Construct")
	_instances[name] = instance
end

-- [P0] one hash read. Unknown names are programming errors: fail loud.
function ServiceContainer.Get(name: string): any
	local value = _instances[name]
	if value == nil then
		error("[Dr.ServiceContainer] unknown provider: " .. tostring(name), 2)
	end
	return value
end

function ServiceContainer.Has(name: string): boolean
	return _instances[name] ~= nil
end

function ServiceContainer.Freeze(): ()
	if not table.isfrozen(_instances) then
		table.freeze(_instances)
	end
end

-- Test-only escape hatch. Studio-only.
function ServiceContainer.Reset(): ()
	local RunContext = require(game:GetService("ReplicatedStorage").Deuterium.Runtime.Environment.RunContext)
	assert(RunContext.IsStudio(), "[Dr.ServiceContainer] Reset is Studio-only")
	local fresh: { [string]: any } = {}
	_instances = fresh
end

return table.freeze(ServiceContainer)
