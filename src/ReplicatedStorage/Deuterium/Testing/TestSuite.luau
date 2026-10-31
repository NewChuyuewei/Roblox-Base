--!strict
-- Dr.Testing.TestSuite — declarative suite definition.
-- A suite is a name + a builder. Building is a cold-path Construct-time operation;
-- the runner gets a frozen list of (name, fn) pairs.

local ErrorHandler = require(script.Parent.Parent.Core.Foundation.ErrorHandler)

export type TestBody = (ctx: any) -> ()
export type TestCase = {
	name: string,
	fn: TestBody,
}

export type Suite = {
	name: string,
	cases: { TestCase },
}

local TestSuite = {}

-- Define("Name", function(t) t.Test("does X", function() ... end) end)
function TestSuite.Define(suiteName: string, builder: (t: any) -> ()): Suite
	if type(suiteName) ~= "string" or #suiteName == 0 then
		ErrorHandler.Raise("DR.TEST.SUITE.NAME", "suite name required", "Dr.TestSuite")
	end
	if type(builder) ~= "function" then
		ErrorHandler.Raise("DR.TEST.SUITE.BUILDER", "builder must be a function", "Dr.TestSuite")
	end

	local cases: { TestCase } = {}
	local builderApi = table.freeze({
		-- 注意：调用方是**点调用** `t.Test("name", fn)`（见文件头示例与唯一调用点
		-- Testing/SelfTest.luau）。以前这里写了一个多余的 `_self` 首参，于是 caseName 收到
		-- 的是函数、fn 是 nil，`Suite.Define` **永远抛错**，整套 TestKit 无法注册任何用例。
		-- 独立复审（subagent，support lane）在 2026-10-25 报出并命中。
		Test = function(caseName: string, fn: TestBody)
			if type(caseName) ~= "string" or #caseName == 0 then
				ErrorHandler.Raise("DR.TEST.CASE.NAME", "case name required", `Dr.TestSuite:{suiteName}`)
			end
			if type(fn) ~= "function" then
				ErrorHandler.Raise(
					"DR.TEST.CASE.FN",
					"case fn must be a function",
					`Dr.TestSuite:{suiteName}`
				)
			end
			table.insert(cases, table.freeze({ name = caseName, fn = fn }))
		end,
	})

	-- 注意：不能简化为 `pcall(builder, builderApi)` —— builder 的签名是 `-> ()`（零返回值），
	-- 于是 pcall 被推断为**只返回 1 个值**，`local ok, err = ...` 在 --!strict 下报
	-- “Function only returns 1 value, but 2 are required here”。
	-- （子代理提的这条简化建议已实测不可用；改用带返回值的闭包。）
	local ok, err = pcall(function(): boolean
		builder(builderApi)
		return true
	end)
	if not ok then
		ErrorHandler.Raise("DR.TEST.SUITE.BUILD", tostring(err), `Dr.TestSuite:{suiteName}`)
	end
	return table.freeze({
		name = suiteName,
		cases = table.freeze(cases),
	}) :: any
end

return table.freeze(TestSuite)
