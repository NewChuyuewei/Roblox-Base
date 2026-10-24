--!strict
-- Dr.Testing.TestContext — per-test metadata passed to each test body.
-- Tests get: their own name, suite name, an IsStudio flag, and a note() to attach detail.
-- Intentionally tiny: TestKit stays boring; execution policy lives in TestRunner.

export type TestContext = {
	suite: string,
	test: string,
	studio: boolean,
	note: (self: TestContext, line: string) -> (),
}

local TestContext = {}

function TestContext.New(suite: string, test: string, studio: boolean, sink: { string }): TestContext
	return table.freeze({
		suite = suite,
		test = test,
		studio = studio,
		note = function(_self: TestContext, line: string)
			table.insert(sink, `[${suite}/${test}] ${line}`)
		end,
	}) :: any
end

return table.freeze(TestContext)
