--!strict
-- Dr.Core.Foundation.ErrorHandler
-- Central, structured error plumbing for the whole framework.
-- Every cross-module failure in Deuterium surfaces as a DrError (CoreTypes),
-- never as a naked thrown string — callers can match on `code`.
--
-- CERTIFIED (DAL C, docs/cert/scope.txt) — this file is deliberately PURE: no engine
-- access, no logging, no other dependency. That is what invariant I16 requires of the
-- certified core, and it makes the whole module runnable headlessly (like StructuredLog).
--
-- `Report` was removed for exactly that reason (2026-10-25): it pulled in
-- ReplicatedStorage.Debug, i.e. `game` plus the non-certified Dr.Diagnostics layer. It
-- had zero callers, so reporting is now the non-certified layer's job:
--   local Logger = require(...Diagnostics.Logging.Logger)
--   Logger.New("Dr.<Tag>"):warn(ErrorHandler.Render(err))
-- See docs/cert/HAZARD.md §5.1.

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

-- NOTE: no logging here on purpose — see the file header. `Render` produces the
-- one-line string; a Logger (non-certified layer) is what writes it.

return table.freeze(ErrorHandler)
