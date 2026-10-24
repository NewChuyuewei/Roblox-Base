--!strict
-- Dr.Core.Foundation.ErrorHandler
-- Central, structured error plumbing for the whole framework.
-- Every cross-module failure in Deuterium surfaces as a DrError (CoreTypes),
-- never as a naked thrown string — callers can match on `code`.

local Debug = require(game:GetService("ReplicatedStorage"):WaitForChild("Debug"))

local CoreTypes = require(script.Parent.CoreTypes)

local ErrorHandler = {}

-- Build (not throw) a structured error.
function ErrorHandler.New(code: string, message: string, source: string?): CoreTypes.DrError
	assert(type(code) == "string" and #code > 0, "[Dr.ErrorHandler] code required")
	assert(type(message) == "string" and #message > 0, "[Dr.ErrorHandler] message required")
	return table.freeze({
		code = code,
		message = message,
		source = source,
	})
end

-- Is the thrown value one of ours?
function ErrorHandler.IsDrError(value: any): boolean
	return type(value) == "table" and type(value.code) == "string" and type(value.message) == "string"
end

-- Convert anything thrown into a DrError (foreign errors get a synthetic code).
function ErrorHandler.Normalize(err: unknown, fallbackCode: string, source: string?): CoreTypes.DrError
	if ErrorHandler.IsDrError(err) then
		return err :: CoreTypes.DrError
	end
	return ErrorHandler.New(fallbackCode, tostring(err), source)
end

-- Render any thrown value into a one-line greppable string (test harnesses use this).
-- DrError tables keep their code; strings pass through; anything else gets tostring'd.
function ErrorHandler.Render(err: unknown): string
	if type(err) == "string" then
		return err
	end
	if ErrorHandler.IsDrError(err) then
		local e = err :: CoreTypes.DrError
		return `[{e.code}] {e.message} @ {e.source or "?"}`
	end
	return tostring(err)
end

-- Throw a structured error (typed `never`-ish; intentionally returns any for assert-style use).
function ErrorHandler.Raise(code: string, message: string, source: string?): any
	error(ErrorHandler.New(code, message, source) :: any, 2)
end

-- try/catch with structured results.
function ErrorHandler.Try(fn: () -> (), code: string, source: string?): CoreTypes.Result
	local err: unknown = nil
	local ok = xpcall(fn, function(e)
		err = if ErrorHandler.IsDrError(e) then e else ErrorHandler.Normalize(e, code, source)
	end)
	if ok then
		return table.freeze({ ok = true, err = nil })
	end
	return table.freeze({ ok = false, err = err :: CoreTypes.DrError })
end

-- Log through the Debug pipeline with a stable tag; never throws.
function ErrorHandler.Report(tag: string, err: unknown): ()
	local normalized = ErrorHandler.Normalize(err, "DR.UNKNOWN", tag)
	Debug.warn(`[Dr.{tag}] {normalized.code}: {normalized.message} @ {normalized.source or "?"}`)
end

return table.freeze(ErrorHandler)
