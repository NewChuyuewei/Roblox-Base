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
--
-- ⚠ 已知不一致（2026-10-25 代码优化时发现，尚未修）：本函数用 `type`，而
-- `Types/Contract/Interface.Conform` 用 `typeof`。两者对宿主定义的类型给出**不同名字**：
--   type(part)   == "userdata"   /  typeof(part) == "Part"
--   type(nil)    == "nil"        /  typeof(nil)  == "nil"
-- 所以 `Contract.IsA(part, "Part")` 会**误报失败**，而同样的值在 `Conform` 里会通过。
-- 修复方向是改用 typeof（会改变行为，故按“重构与修 bug 分开”的规则单独立项）。
-- 当前零调用方，所以尚未造成实际故障。记录在 .plan/README.md 的风险 R26。
function Contract.IsA(value: any, kind: string, code: string, message: string?)
	if type(value) ~= kind then
		ErrorHandler.Raise(
			"DR.CONTRACT.TYPE." .. code,
			(message or "type mismatch") .. ` (expected {kind}, got {type(value)})`
		)
	end
end

return table.freeze(Contract)
