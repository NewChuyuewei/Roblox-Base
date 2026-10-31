--!strict
-- Dr.Runtime.Interop.ExternalBridge
-- Contract facade for third-party integrations (anti-cheat SaaS, analytics, Discord...).
-- Idea: define a contract once; every call through the facade is protected and
-- reported, so a misbehaving vendor module can never crash or silently corrupt the game.

local Debug = require(script.Parent.Parent.Parent.Parent.Debug)

local LegacyBridge = require(script.Parent.LegacyBridge)

local ExternalBridge = {}

export type Surface = { [string]: (...any) -> ...any }
export type Facade = { [string]: (...any) -> (boolean, any) }

local NAME_PATTERN = "^[%a][%w_%.]*$"

-- Build a facade: same method names, each call returns (ok, resultOrError).
function ExternalBridge.Define(contractName: string, surface: Surface): Facade
	assert(contractName:match(NAME_PATTERN) ~= nil, "[Dr.ExternalBridge] invalid contract name")
	assert(type(surface) == "table", "[Dr.ExternalBridge] surface must be a table")
	assert(next(surface) ~= nil, "[Dr.ExternalBridge] surface must not be empty")

	local facade: Facade = {}
	for methodName, fn in surface do
		assert(
			type(methodName) == "string" and type(fn) == "function",
			"[Dr.ExternalBridge] surface must map string -> function"
		)
		-- 复用 LegacyBridge.TryCall，而不是再写一遍 table.pack(pcall(...)) 包装
		-- （独立复审 subagent, runtime lane 指出两处重复）。行为等价：都只透传第一个返回值。
		facade[methodName] = function(...: any): (boolean, any)
			local ok, value = LegacyBridge.TryCall(fn, ...)
			if not ok then
				Debug.warn(`[Dr.ExternalBridge:{contractName}] {methodName} failed:`, value)
			end
			return ok, value
		end
	end
	return table.freeze(facade)
end

return table.freeze(ExternalBridge)
