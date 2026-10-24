--!strict
-- Dr.Testing.TestSuite — declarative suite definition.
-- A suite is a name + a builder. Building is a cold-path Construct-time operation;
-- the runner gets a frozen list of (name, fn) pairs.

local ErrorHandler = require(game:GetService("ReplicatedStorage").Deuterium.Core.Foundation.ErrorHandler)

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
		Test = function(_self: any, caseName: string, fn: TestBody)
			if type(caseName) ~= "string" or #caseName == 0 then
				ErrorHandler.Raise("DR.TEST.CASE.NAME", "case name required", `Dr.TestSuite:{suiteName}`)
			end
			if type(fn) ~= "function" then
				ErrorHandler.Raise("DR.TEST.CASE.FN", "case fn must be a function", `Dr.TestSuite:{suiteName}`)
			end
			table.insert(cases, table.freeze({ name = caseName, fn = fn }))
		end,
	})

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
