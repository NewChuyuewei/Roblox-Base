--!strict
-- Dr.Core.Container.ServiceRegistry
-- The registrar: stores providers by name, in registration order.
-- Register-time validation is the contract: bad shapes fail loud and early.

local Types = require(script.Parent.Types)

local NAME_PATTERN = "^[%a][%w_%.]*$"

local ServiceRegistry = {}

local _byName: { [string]: Types.Provider } = {}
local _order: { string } = {}
local _locked = false

local function validate(provider: any): Types.Provider
	assert(type(provider) == "table", "[Dr.ServiceRegistry] provider must be a table")
	assert(type(provider.Name) == "string", "[Dr.ServiceRegistry] provider.Name must be a string")
	assert(
		provider.Name:match(NAME_PATTERN) ~= nil,
		"[Dr.ServiceRegistry] invalid provider name: " .. tostring(provider.Name)
	)
	assert(type(provider.Init) == "function", `[Dr.ServiceRegistry] {provider.Name}: Init must be a function`)
	if provider.Start ~= nil then
		assert(type(provider.Start) == "function", `[Dr.ServiceRegistry] {provider.Name}: Start must be function?`)
	end
	if provider.Stop ~= nil then
		assert(type(provider.Stop) == "function", `[Dr.ServiceRegistry] {provider.Name}: Stop must be function?`)
	end
	if provider.Dependencies ~= nil then
		assert(
			type(provider.Dependencies) == "table",
			`[Dr.ServiceRegistry] {provider.Name}: Dependencies must be a list`
		)
		for index, dep in provider.Dependencies do
			assert(type(index) == "number", `[Dr.ServiceRegistry] {provider.Name}: Dependencies must be an array`)
			assert(
				type(dep) == "string",
				`[Dr.ServiceRegistry] {provider.Name}: Dependencies[{index}] must be a string`
			)
		end
	end
	return provider :: Types.Provider
end

function ServiceRegistry.Add(provider: any): ()
	assert(not _locked, "[Dr.ServiceRegistry] Add called after Construct")
	local checked = validate(provider)
	assert(_byName[checked.Name] == nil, "[Dr.ServiceRegistry] duplicate provider: " .. checked.Name)
	_byName[checked.Name] = checked
	table.insert(_order, checked.Name)
end

function ServiceRegistry.Has(name: string): boolean
	return _byName[name] ~= nil
end

function ServiceRegistry.GetRaw(name: string): Types.Provider
	local p = _byName[name]
	if p == nil then
		error("[Dr.ServiceRegistry] unknown provider: " .. name, 2)
	end
	return p
end

-- Registration-ordered snapshot for the injector.
function ServiceRegistry.All(): { Types.Provider }
	local out = table.create(#_order)
	for index, name in _order do
		out[index] = _byName[name] :: Types.Provider
	end
	return out
end

function ServiceRegistry.Count(): number
	return #_order
end

function ServiceRegistry.Lock(): ()
	if not _locked then
		table.freeze(_byName)
		table.freeze(_order)
		_locked = true
	end
end

function ServiceRegistry.IsLocked(): boolean
	return _locked
end

-- Test-only escape hatch. Studio-only: production must never lose the registry.
function ServiceRegistry.Reset(): ()
	local RunContext = require(game:GetService("ReplicatedStorage").Deuterium.Runtime.Environment.RunContext)
	assert(RunContext.IsStudio(), "[Dr.ServiceRegistry] Reset is Studio-only")
	_byName = {}
	_order = {}
	_locked = false
end

return table.freeze(ServiceRegistry)
