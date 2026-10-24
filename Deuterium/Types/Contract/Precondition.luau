--!strict
-- Dr.Types.Contract.Precondition
-- Re-export of Core.Foundation.Contract.Precondition under the plan's Types.Contract domain.

local Contract = require(script.Parent.Parent.Parent.Core.Foundation.Contract)

return table.freeze({
	Check = Contract.Precondition,
})
