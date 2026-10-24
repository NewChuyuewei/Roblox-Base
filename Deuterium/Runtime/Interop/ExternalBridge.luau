--!strict
-- Dr.Runtime.Interop.ExternalBridge
-- Contract facade for third-party integrations (anti-cheat SaaS, analytics, Discord...).
-- Idea: define a contract once; every call through the facade is protected and
-- reported, so a misbehaving vendor module can never crash or silently corrupt the game.

local Debug = require(game:GetService("ReplicatedStorage"):WaitForChild("Debug"))

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
		facade[methodName] = function(...: any): (boolean, any)
			local results = table.pack(pcall(fn, ...))
			local ok = results[1] == true
			if not ok then
				Debug.warn(`[Dr.ExternalBridge:{contractName}] {methodName} failed:`, results[2])
			end
			return ok, results[2]
		end
	end
	return table.freeze(facade)
end

return table.freeze(ExternalBridge)
