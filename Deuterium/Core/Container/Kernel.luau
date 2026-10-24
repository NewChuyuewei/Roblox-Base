--!strict
-- Dr.Core.Container.Kernel
-- The microkernel orchestrator. Lifecycle: Collecting → Constructed → Initialized → Started.
--   Construct: resolve the dependency graph ONCE (topological) and freeze everything.
--   Init:      run every provider's Init in computed order, one pcall each (Bulkhead-style
--              isolation arrives in W1.5+; a failing provider is recorded, never fatal).
-- After Init, dependencies sit resolved and frozen on each context — the runtime hot
-- path never performs a name lookup again.

local Debug = require(game:GetService("ReplicatedStorage"):WaitForChild("Debug"))

local Types = require(script.Parent.Types)
local ServiceRegistry = require(script.Parent.ServiceRegistry)
local ServiceContainer = require(script.Parent.ServiceContainer)
local DependencyInjector = require(script.Parent.DependencyInjector)

local Kernel = {}

local _state: Types.KernelState = "Collecting"
local _order: { string } = {}
local _failed: { [string]: string } = {}

local function contexts(name: string): Types.KernelContext
	local provider = ServiceRegistry.GetRaw(name)
	local deps: { [string]: any } = {}
	local declared = provider.Dependencies
	if declared ~= nil then
		for _, dep in declared do
			deps[dep] = ServiceContainer.Get(dep)
		end
	end
	return table.freeze({
		Name = name,
		Dependencies = table.freeze(deps),
		Get = function(depName: string): any
			return ServiceContainer.Get(depName)
		end,
	}) :: Types.KernelContext
end

-- Collecting phase entry.
function Kernel.Register(provider: Types.Provider): ()
	assert(_state == "Collecting", "[Dr.Kernel] Register outside Collecting phase")
	ServiceRegistry.Add(provider)
	Debug.print("[Dr.Kernel] registered:", provider.Name)
end

function Kernel.GetState(): Types.KernelState
	return _state
end

-- Construct: resolve graph, freeze registry, materialize container. Fatal on error.
function Kernel.Construct(): boolean
	assert(_state == "Collecting", "[Dr.Kernel] Construct requires Collecting")
	local providers = ServiceRegistry.All()
	local result = DependencyInjector.ResolveOrder(providers)
	if result.error ~= nil then
		Debug.warn("[Dr.Kernel] Construct failed:", result.error)
		return false
	end
	_order = result.order :: { string }

	ServiceRegistry.Lock()
	for _, name in _order do
		local provider = ServiceRegistry.GetRaw(name)
		ServiceContainer.Set(name, provider)
	end
	ServiceContainer.Freeze()

	_state = "Constructed"
	Debug.print(("[Dr.Kernel] Constructed: %d providers, order: %s"):format(#_order, table.concat(_order, ", ")))
	return true
end

-- Init: per-provider xpcall isolation. A failed provider is marked; everyone else boots.
function Kernel.Init(): boolean
	assert(_state == "Constructed", "[Dr.Kernel] Init requires Constructed")
	for _, name in _order do
		local provider = ServiceRegistry.GetRaw(name)
		local ctx = contexts(name)
		local err: unknown = nil
		local ok = xpcall(function()
			provider.Init(provider, ctx)
		end, function(e)
			err = e
		end)
		if ok then
			Debug.print("[Dr.Kernel] Init ok:", name)
		else
			_failed[name] = tostring(err)
			Debug.warn("[Dr.Kernel] Init FAILED (isolated):", name, "->", tostring(err))
		end
	end
	_state = "Initialized"
	local failedCount = 0
	for _ in _failed do
		failedCount += 1
	end
	if failedCount > 0 then
		Debug.warn(`[Dr.Kernel] Init done with {failedCount} failed provider(s)`)
	else
		Debug.print("[Dr.Kernel] Init done, all healthy")
	end
	return failedCount == 0
end

-- Start: only providers that inited cleanly get Start().
function Kernel.Start(): boolean
	assert(_state == "Initialized", "[Dr.Kernel] Start requires Initialized")
	for _, name in _order do
		if _failed[name] ~= nil then
			continue
		end
		local provider = ServiceRegistry.GetRaw(name)
		if provider.Start == nil then
			continue
		end
		local err: unknown = nil
		local ok = xpcall(function()
			(provider.Start :: (self: any) -> ())(provider)
		end, function(e)
			err = e
		end)
		if ok then
			Debug.print("[Dr.Kernel] Started:", name)
		else
			_failed[name] = tostring(err)
			Debug.warn("[Dr.Kernel] Start FAILED (isolated):", name, "->", tostring(err))
		end
	end
	_state = "Started"
	return true
end

-- [P0] one hash read through the container.
function Kernel.Get(name: string): any
	assert(_state == "Initialized" or _state == "Started", "[Dr.Kernel] Get before Init")
	return ServiceContainer.Get(name)
end

function Kernel.IsProviderFailed(name: string): boolean
	return _failed[name] ~= nil
end

function Kernel.GetFailed(): { [string]: string }
	local out = {}
	for name, err in _failed do
		out[name] = err
	end
	return table.freeze(out)
end

function Kernel.GetOrder(): { string }
	local out = table.clone(_order)
	return table.freeze(out)
end

-- Test-only escape hatch (SelfTest). Studio-only by contract — production can never wipe the kernel.
function Kernel.Reset(): ()
	local RunContext = require(game:GetService("ReplicatedStorage").Deuterium.Runtime.Environment.RunContext)
	assert(RunContext.IsStudio(), "[Dr.Kernel] Reset is Studio-only")
	ServiceRegistry.Reset()
	ServiceContainer.Reset()
	_order = {}
	_failed = {}
	_state = "Collecting"
end

return table.freeze(Kernel)
