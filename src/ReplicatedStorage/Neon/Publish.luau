--!strict
-- Neon.Publish —— 唯一的发射路径：校验级别 → 构造记录 → 投递（`.plan/PHASES.md` P2.W1）。
--
-- 为什么要单独一个模块，而不是把这三步写在入口 `Neon.luau` 里：
-- `Neon.Log(...)` 与 `Channel` 记录器必须走同一条发射路径。写成两份的结局是可以预见的
-- —— 入口有换行校验而记录器没有，或反之以另一条为准，然后同一个调用点因为选了不同入口
-- 而有不同行为。发射路径只能有一个 owner，`Neon` 与 `Channel` 都是它的调用方。
--
-- L0 约束：不碰引擎（`.plan/CARBON.md` §3.1）。

local Level = require(script.Parent.Level)
local Record = require(script.Parent.Record)
local Sink = require(script.Parent.Sink)

local Publish = {}

local logged = 0

--[=[
	发射一条记录，返回构造好的记录。

	`level` 故意收 `any`：Studio 控制台（W7）与配置文件里来的级别本来就是字符串，
	所以这里接受两种写法 —— 已登记的级别名原样通过，字符串先规范化（`"INFO"` 可用），
	认不出的**当场抛错**。不静默降级成 `info`：那条记录之后看起来完全正常，
	没人能发现它其实是被猜出来的。
]=]
function Publish.Emit(level: any, channel: string, message: string, fields: Record.Fields?): Record.Record
	local candidate = level
	if type(level) == "string" and not Level.Is(level) then
		candidate = Level.Normalize(level)
		assert(
			candidate ~= nil,
			`[Neon] 未登记的级别 {Level.Describe(level)}（可用：trace debug info warn error，大小写不限）`
		)
	end
	local record = Record.New(candidate :: Level.Level, channel, message, fields)
	Sink.Broadcast(record)
	logged += 1
	return record
end

--[=[ 自上次 `Reset` 以来发射过的记录数（含没有输出端可投递的那些）。]=]
function Publish.Logged(): number
	return logged
end

--[=[ 只清本模块的计数；注册表由 `Sink.Reset()` 负责，时钟由 `Record.SetClock(nil)` 负责。]=]
function Publish.Reset(): ()
	logged = 0
end

return Publish
