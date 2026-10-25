--!strict
-- Dr.Types.Contract.Interface
-- Assert a value CONFORMS to a structural spec: { fieldName = expectedKind }.
-- The shape contract runs where boundaries cross: provider registration, config load,
-- adapter entry points. Missing/extra fields both surface.

local ErrorHandler = require(script.Parent.Parent.Parent.Core.Foundation.ErrorHandler)

local Interface = {}

-- spec example: { Name = "string", Init = "function" }
function Interface.Conform(label: string, value: any, spec: { [string]: string }): boolean
	assert(type(label) == "string" and #label > 0, "[Dr.Interface] label required")
	assert(type(value) == "table", `[Dr.Interface] {label}: value must be a table`)
	for field, expectedKind in spec do
		local actual = value[field]
		local actualKind = if actual == nil then "nil" else typeof(actual)
		if actualKind ~= expectedKind then
			ErrorHandler.Raise(
				"DR.CONTRACT.INTERFACE.FIELD",
				`{label}.{field} expected {expectedKind}, got {actualKind}`,
				label
			)
		end
	end
	return true
end

return table.freeze(Interface)
