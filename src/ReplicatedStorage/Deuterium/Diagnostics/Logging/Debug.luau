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

-- Logger methods take self, so these are COLON calls. Dot calls here would leak the
-- facade table into the message (see the note in Logger.luau).
return table.freeze({
	print = function(...: any): ()
		facade:info(...)
	end,
	warn = function(...: any): ()
		facade:warn(...)
	end,
})
-- `err` 已删除（2026-10-25）：全仓库零调用方（18 个遗留调用点只用 print/warn），
-- 按“删优于加”不保留未使用的门面。需要错误级别时用 Logger 的 :error()。
