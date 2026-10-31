--!strict
-- Dr.Extensions.Demo — a minimal provider that exercises the entire W1.x stack:
--   Kernel.Register + topo Init/Start + Bulkhead isolation + Configuration + FeatureFlags
-- It carries its own fault injection: Demo.BadActor registers and throws on Init;
-- the kernel must isolate it while Demo boots clean.

local Debug = require(script.Parent.Parent.Parent.Debug)

local Types = require(script.Parent.Parent.Core.Container.Types)

local Demo = {}

local state = { started = false }

Demo.Provider = table.freeze({
	Name = "W17.Demo",
	Dependencies = {} :: { string },
	Init = function(_self: any, _ctx: Types.KernelContext)
		Debug.print("[Dr.Demo] Init")
	end,
	Start = function(_self: any)
		state.started = true
		Debug.print("[Dr.Demo] Started")
	end,
	Stop = function(_self: any)
		state.started = false
	end,
}) :: any

-- Intentionally broken provider for bulkhead verification.
Demo.BadActor = table.freeze({
	Name = "W17.DemoBadActor",
	Init = function(_self: any, _ctx: Types.KernelContext)
		error("[Dr.Demo.BadActor] deliberately exploding", 0)
	end,
}) :: any

function Demo.WasStarted(): boolean
	return state.started
end

return table.freeze(Demo)
