--!strict
-- Dr.Testing.Assert — assertions are structured errors (DrError), never bare strings.
-- Every failure has a code so CI/debugging can grep exactly what broke.

local ErrorHandler = require(script.Parent.Parent.Core.Foundation.ErrorHandler)

local Assert = {}

function Assert.IsTrue(cond: boolean, what: string)
	if not cond then
		ErrorHandler.Raise("DR.TEST.ASSERT", what, "Assert.IsTrue")
	end
end

function Assert.Equal(actual: any, expected: any, what: string)
	if actual ~= expected then
		ErrorHandler.Raise(
			"DR.TEST.EQUAL",
			`{what} (expected {tostring(expected)}, got {tostring(actual)})`,
			"Assert.Equal"
		)
	end
end

-- Demand that fn throws; optionally demand the message contains `needle`.
function Assert.Throws(fn: () -> (), needle: string?, what: string)
	local err: unknown = nil
	local ok = xpcall(fn, function(e)
		err = e
	end)
	Assert.IsTrue(not ok, what .. " (expected it to throw)")
	if needle ~= nil then
		-- single execution: fn ran once above; side-effectful fns must not run twice
		local rendered = ErrorHandler.Render(err)
		Assert.IsTrue(
			rendered:find(needle, 1, true) ~= nil,
			`{what} (error should contain "{needle}", got: {rendered})`
		)
	end
end

return table.freeze(Assert)
