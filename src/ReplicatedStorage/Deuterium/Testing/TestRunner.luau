--!strict
-- Dr.Testing.TestRunner — executes suites, isolates failures, reports a frozen summary.
-- Studio-only by policy: Prod boot never runs tests.

local Debug = require(script.Parent.Parent.Parent.Debug)
local ErrorHandler = require(script.Parent.Parent.Core.Foundation.ErrorHandler)

local Suite = require(script.Parent.TestSuite)
local TestContext = require(script.Parent.TestContext)
local RunContext = require(script.Parent.Parent.Runtime.Environment.RunContext)

export type CaseResult = {
	name: string,
	ok: boolean,
	err: string?,
	notes: { string },
}

export type RunSummary = {
	suite: string,
	passed: number,
	failed: number,
	results: { CaseResult },
}

local TestRunner = {}

function TestRunner.Run(suite: Suite.Suite): RunSummary
	if not RunContext.IsStudio() then
		Debug.warn("[Dr.TestRunner] refused: production")
		return table.freeze({ suite = suite.name, passed = 0, failed = 0, results = table.freeze({}) }) :: any
	end

	local results: { CaseResult } = {}
	local passed, failed = 0, 0
	for _, case in suite.cases do
		local notes: { string } = {}
		local ctx = TestContext.New(suite.name, case.name, true, notes)
		local err: unknown = nil
		local ok = xpcall(function()
			case.fn(ctx)
		end, function(e)
			err = ErrorHandler.Render(e)
		end)

		if ok then
			passed += 1
			Debug.print(`[Dr.TestRunner:{suite.name}] PASS {case.name}`)
		else
			failed += 1
			Debug.warn(`[Dr.TestRunner:{suite.name}] FAIL {case.name} -> {tostring(err)}`)
		end
		table.insert(
			results,
			table.freeze({
				name = case.name,
				ok = ok,
				err = if ok then nil else tostring(err),
				notes = table.freeze(notes),
			})
		)
	end

	Debug.print(`[Dr.TestRunner:{suite.name}] {passed}/{passed + failed} passed`)
	return table.freeze({
		suite = suite.name,
		passed = passed,
		failed = failed,
		results = table.freeze(results),
	}) :: any
end

function TestRunner.RunAll(suites: { Suite.Suite }): { RunSummary }
	local out: { RunSummary } = {}
	for _, suite in suites do
		table.insert(out, TestRunner.Run(suite))
	end
	return table.freeze(out)
end

return table.freeze(TestRunner)
