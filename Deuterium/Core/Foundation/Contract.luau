--!strict
-- Dr.Core.Foundation.Contract
-- Declarative contract enforcement: call sites document intent (Precondition vs Invariant),
-- ErrorHandler gives the failure a stable code.

local ErrorHandler = require(script.Parent.ErrorHandler)

local Contract = {}

-- Caller-side contract (precondition of the API you are calling).
function Contract.Precondition(cond: boolean, code: string, message: string)
	if not cond then
		ErrorHandler.Raise("DR.CONTRACT.PRECONDITION." .. code, message)
	end
end

-- Internal truth (invariant of our own code).
function Contract.Invariant(cond: boolean, code: string, message: string)
	if not cond then
		ErrorHandler.Raise("DR.CONTRACT.INVARIANT." .. code, message)
	end
end

-- Shape assertion for values crossing module boundaries.
function Contract.IsA(value: any, kind: string, code: string, message: string?)
	if type(value) ~= kind then
		ErrorHandler.Raise(
			"DR.CONTRACT.TYPE." .. code,
			(message or "type mismatch") .. ` (expected {kind}, got {type(value)})`
		)
	end
end

return table.freeze(Contract)
