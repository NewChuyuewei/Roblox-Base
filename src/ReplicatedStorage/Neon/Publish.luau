--!strict
-- Neon.Publish —— 唯一的发射路径：校验级别 → 构造记录 → 投递（`.plan/PHASES.md` P2.W1）。
--
-- 为什么要单独一个模块，而不是把这三步写在入口 `Neon.luau` 里：
-- `Neon.Log(...)` 与 `Channel` 记录器必须走同一条发射路径。写成两份的结局是可以预见的
-- —— 入口有换行校验而记录器没有，或反之以另一条为准，然后同一个调用点因为选了不同入口
-- 而有不同行为。发射路径只能有一个 owner，`Neon` 与 `Channel` 都是它的调用方。过滤器也挂在这里
-- （W4）：挂在别处就会出现「入口有过滤、记录器没有」，而记录器正是别人抄的那一份。
--
-- L0 约束：不碰引擎（`.plan/CARBON.md` §3.1）。

local Level = require(script.Parent.Level)
local Record = require(script.Parent.Record)
local Sink = require(script.Parent.Sink)
local Filter = require(script.Parent.Filter)

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
	-- 判定在构造**之前**：过滤器要能在记录还只是一组参数时把话说完，而计数字段必须在
	-- 构造时合进去（记录是冻结的快照，造完再改就是撒谎）。但**被挡掉的记录照样构造并返回**：
	-- `Neon.Info` 的返回物不能取决于配置，否则调用方得写 `if record then` —— 那等于让
	-- 「改一行日志配置」变成一次全工程搜索替换。
	local admitted, note = Filter.Judge(candidate :: Level.Level, channel, message)
	local record: Record.Record
	if note == nil then
		record = Record.New(candidate :: Level.Level, channel, message, fields)
	else
		-- `MergeFields` 返回新表，不动调用方传进来的 `fields`：把「本模块攒的账」塞进
		-- 别人的表是不可想象的。
		record = Record.New(candidate :: Level.Level, channel, message, Record.MergeFields(fields, note))
	end
	if admitted then
		Sink.Broadcast(record)
		logged += 1
	end
	return record
end

--[=[
	自上次 `Reset` 以来**投递过**的记录数（含没有输出端可投递的那些，不含被过滤器挡掉的）。
	被挡掉的条数在 `Filter.Stats()` 里按原因分开计 —— 合成一个数就没法回答
	「日志变少是我关掉的，还是它自己没打」。
]=]
function Publish.Logged(): number
	return logged
end

--[=[ 只清本模块的计数；注册表由 `Sink.Reset()` 负责，时钟由 `Record.SetClock(nil)` 负责。]=]
function Publish.Reset(): ()
	logged = 0
end

return Publish
