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
-- 类型名取自 `typeof`，不用 `type`（官方语义，已核实）：
--   type(part)  == "userdata"   /  typeof(part)  == "Folder"/"Part"（ClassName）
--   type(nil)   == "nil"        /  typeof(nil)   == "nil"
-- 旧实现用 `type`，于是 `Contract.IsA(folder, "Instance")` **永远失败**——而 ModuleLoader
-- 与 HotReload 正是这么调的（它们的加载路径因此直接抛错）。修复见 R26（2026-10-25）。
--
-- 伪类型 `"Instance"` 表示“任意 Roblox 实例”：typeof 对实例给出的是 ClassName 而不是
-- "Instance"，所以这个伪名需要单独判定。
function Contract.IsA(value: any, kind: string, code: string, message: string?)
	local valueKind = typeof(value)
	local actualKind = valueKind
	if kind == "Instance" then
		-- Roblox 实例：type 为 "userdata"（官方文档）；兼容地把带 ClassName 的表也认下
		local t = type(value)
		if valueKind ~= "nil" and (t == "userdata" or (t == "table" and (value :: any).ClassName ~= nil)) then
			actualKind = "Instance"
		end
	end
	if actualKind ~= kind then
		ErrorHandler.Raise(
			"DR.CONTRACT.TYPE." .. code,
			(message or "type mismatch") .. ` (expected {kind}, got {actualKind})`
		)
	end
end

return table.freeze(Contract)
