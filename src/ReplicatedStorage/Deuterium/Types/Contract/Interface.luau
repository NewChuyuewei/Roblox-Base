--!strict
-- Dr.Types.Contract.Interface
-- Assert a value CONFORMS to a structural spec: { fieldName = expectedKind }.
-- The shape contract runs where boundaries cross: provider registration, config load,
-- adapter entry points.
--
-- Kind names come from `typeof` (not `type`): typeof returns "Part"/"Instance"/"Vector3"
-- for host-defined userdata, while type returns "userdata". Both agree on "nil".
-- NOTE: only the fields listed in `spec` are checked — **extra fields are not rejected**
-- (asserted as known behaviour in tests/run.luau). The earlier header claimed otherwise.
--
-- CERTIFIED (DAL C) — 需求基线：docs/cert/req/INTERFACE.md。

local ErrorHandler = require(script.Parent.Parent.Parent.Core.Foundation.ErrorHandler)

local Interface = {}

-- spec example: { Name = "string", Init = "function" }
-- LLR-INTERFACE-001
function Interface.Conform(label: string, value: any, spec: { [string]: string }): boolean
	assert(type(label) == "string" and #label > 0, "[Dr.Interface] label required")
	assert(type(value) == "table", `[Dr.Interface] {label}: value must be a table`)
	for field, expectedKind in spec do
		-- typeof(nil) 就是 "nil"，所以不需要再写一个 nil 分支（Luau 官方文档已核实）。
		local actualKind = typeof(value[field])
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
