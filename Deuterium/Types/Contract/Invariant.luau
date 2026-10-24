--!strict
-- Dr.Types.Contract.Invariant
-- Re-export of Core.Foundation.Contract.Invariant under the plan's Types.Contract domain.

local Contract = require(script.Parent.Parent.Parent.Core.Foundation.Contract)

return table.freeze({
	Check = Contract.Invariant,
})
