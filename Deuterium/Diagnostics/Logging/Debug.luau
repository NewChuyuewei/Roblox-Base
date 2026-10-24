--!strict
-- Legacy logging facade.
--
-- 18 existing modules require `ReplicatedStorage.Debug` (default.project.json maps that
-- name to this file) and call only print/warn. They keep working unchanged; new code
-- should hold a Dr.Diagnostics.Logging.Logger instead.
--
-- MUST NOT require ReplicatedStorage.Debug — that is this file. Sibling requires only,
-- otherwise requiring it from inside the framework closes a load cycle.

local Logger = require(script.Parent.Logger)

local facade = Logger.New("Dr")

return table.freeze({
	print = function(...: any): ()
		facade.info(...)
	end,
	warn = function(...: any): ()
		facade.warn(...)
	end,
	err = function(...: any): ()
		facade.error(...)
	end,
})
