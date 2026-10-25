--!strict
-- Dr.Core.Container types. Pure type module.

export type Provider = {
	Name: string, -- unique identifier; names must match "^[A-Za-z][%w_%.]*$"
	Dependencies: { string }?, -- static list of provider names, resolved at Construct
	Init: (self: any, ctx: KernelContext) -> (), -- called once, in topological order
	Start: (self: any) -> ()?, -- called after all Init calls succeeded or were isolated
	Stop: (self: any) -> ()?, -- Bulkhead unload point
}

export type KernelContext = {
	Name: string, -- this provider's own name
	Dependencies: { [string]: any }, -- fully resolved, frozen at Construct
	Get: (name: string) -> any, -- container lookup (any provider; static world after Construct)
}

export type KernelState = "Collecting" | "Constructed" | "Initialized" | "Started"

return table.freeze({})
