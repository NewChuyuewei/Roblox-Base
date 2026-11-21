--!strict
-- Neon.Record —— 一条日志记录的结构与构造（`.plan/PHASES.md` P2.W1）。
--
-- 记录结构是 Core 与所有输出端之间唯一的契约：`{ time, level, channel, message, fields }`。
-- 两条设计决定要写明白，因为它们各自挡掉一类真实事故：
--
-- 1. **记录是调用时刻的快照**（`fields` 做浅拷贝）。不拷贝的话，「先打印、后改表」会让
--    日志显示的内容取决于哪个输出端先跑 —— 环形缓冲读到的是改过的值，标准输出读到的
--    可能是原值，两者都对不上现场。
-- 2. **记录与 `fields` 都被冻结**。输出端拿到的是同一份记录（不复制），省内存也保证
--    「同一个 sink 收两次是同一个东西」这种断言写得出来；代价是输出端不许就地改，
--    要改就自己构造一份。深冻结不做：嵌套表冻结会把调用方自己的数据结构一起废掉。
--
-- `time` 的来源是可注入的时钟（见 `Record.SetClock`）。放这里而不是放入口，是因为
-- 时间是**记录**的属性而不是打印动作的属性：`Channel` 与 `Neon.Log` 都从这里取，
-- 两处各拿一次时钟就会出现「同一条记录的两个时间字段不一致」。测试注入假时钟，
-- 于是断言不依赖真实时间（W4 的限速判据也依赖这个注入点）。
--
-- L0 约束：不碰引擎（`.plan/CARBON.md` §3.1）。

local Level = require(script.Parent.Level)

local Record = {}

export type Fields = { [string]: any }

export type Record = {
	time: number,
	level: Level.Level,
	channel: string,
	message: string,
	fields: Fields,
}

-- 默认时钟取 Luau 标准库的 `os.time()`（秒），**不碰 `game`**：L0 只要 require 一次
-- 引擎服务，整个组件就再也无法在 Lune 里跑，而「能在 Lune 里跑」是本组件全部测试的
-- 前提（AGENTS.md 硬规则 7）。需要更高精度或服务器真实时间，由宿主绑定（W6 的 `Host/`）
-- 注入实现，核心只认 `() -> number` 这个形状。
local DEFAULT_CLOCK = os.time

local clock = DEFAULT_CLOCK

--[=[ 换掉时间来源；传 `nil` 复原默认。测试与宿主绑定共用这一个接缝。]=]
function Record.SetClock(source: (() -> number)?): ()
	if source == nil then
		clock = DEFAULT_CLOCK
		return
	end
	assert(type(source) == "function", "[Neon.Record] SetClock 需要一个函数")
	clock = source
end

--[=[ 当前时钟函数本身。给「换过没换过」这种断言用，免得测试去猜默认值。]=]
function Record.GetClock(): () -> number
	return clock
end

--[=[	现在时刻。]=]
function Record.Now(): number
	return clock()
end

-- 共享的空表：冻结过，所以「读不到字段」与「不许写」同时成立，
-- 也不必为每条无字段记录分配一个新表。（`copyFields` 直接用它，不绕道访问器 ——
-- 上一版写成 `return Record.EmptyFields`，把函数本身当成了表：类型门禁当场抓住。）
local EMPTY: Fields = table.freeze({}) :: Fields

-- 时钟坏了要在构造记录时就炸，不要让一个 `nil` 时间戳漂到格式化那一层去。
local function currentTime(): number
	local time = clock()
	assert(
		type(time) == "number" and time == time and time ~= math.huge and time ~= -math.huge,
		`[Neon.Record] 时钟返回了不是有限数的值：{Level.Describe(time)}`
	)
	return time
end

local function copyFields(fields: any): Fields
	if fields == nil then
		return EMPTY
	end
	assert(type(fields) == "table", `[Neon.Record] fields 必须是表，收到 {Level.Describe(fields)}`)
	local out: Fields = {}
	for key, value in fields do
		assert(
			type(key) == "string" and #key > 0,
			`[Neon.Record] fields 的键必须是非空字符串，收到 {Level.Describe(key)}`
		)
		out[key] = value
	end
	return table.freeze(out) :: Fields
end

--[=[
	频道名 / 输出端名这类「会被印出来的标识符」是否安全：非空、且不含换行。

	用两次 plain find 而不是一个 `"[\r\n]"` 模式：这个判定在**每条记录**上都要跑，
	而模式匹配要走一遍 pattern VM，两条定长查找明显便宜。含换行为什么必须挡 ——
	`Format.Line` 与宿主控制台都按行处理，一条记录裂成两行之后，按行 grep 的规则会漏掉
	半条，而人看到的症状是「这条日志没打出来」。
]=]
function Record.IsOneLine(text: string): boolean
	if type(text) ~= "string" or #text == 0 then
		return false
	end
	return string.find(text, "\n", 1, true) == nil and string.find(text, "\r", 1, true) == nil
end

--[=[
	构造一条记录。四个参数全部当场校验，不做「宽容接受 + 悄悄修正」：
	日志系统是最后那道防线，它自己把输入猜错了就没人发现了。
]=]
-- `level` 收 `any` 而不是 `Level.Level`：入口 `Neon.Log` 本来就接字符串，而 `Level.Trace`
-- 这类**常量字段**在调用点的类型会被 Luau 放大成 `string`（可变表字段上的字面量不收窄，
-- `:: Level` 也挡不住）—— 结果「用自家常量」反而过不了类型门禁，两轮 CI 都报在同一行。
-- 真正的大门是下面的 `Level.Rank`：不在表里的名字当场抛。记录里的字段仍标注成
-- `Level.Level`（见 `level :: Level.Level`），下游拿到的是收窄过的联合，没被放宽。
function Record.New(level: any, channel: string, message: string, fields: Fields?): Record
	-- Rank 会校验级别名；channel/message 各挡一类下游爆炸：
	-- 频道里带换行会撕开 W3 的单行格式，message 非字符串通常是把表塞错了位置。
	Level.Rank(level)
	assert(
		Record.IsOneLine(channel :: string),
		`[Neon.Record] channel 必须是不含换行的非空字符串，收到 {Level.Describe(channel)}`
	)
	assert(
		type(message) == "string",
		`[Neon.Record] message 必须是字符串，收到 {Level.Describe(message)}`
	)
	return table.freeze({
		time = currentTime(),
		level = level :: Level.Level,
		channel = channel,
		message = message,
		fields = copyFields(fields),
	}) :: Record
end

--[=[
	合并上下文字段：`extra` 覆盖 `base`。返回新表，两个入参都不动 ——
	`Channel` 的派生记录器要靠这条保证「派生不影响父记录器」。
]=]
function Record.MergeFields(base: Fields?, extra: any): Fields
	if extra == nil then
		return copyFields(base)
	end
	if base == nil then
		return copyFields(extra)
	end
	assert(type(base) == "table", `[Neon.Record] fields 必须是表，收到 {Level.Describe(base)}`)
	assert(type(extra) == "table", `[Neon.Record] fields 必须是表，收到 {Level.Describe(extra)}`)
	local merged: Fields = {}
	for key, value in base do
		merged[key] = value
	end
	for key, value in extra do
		assert(
			type(key) == "string" and #key > 0,
			`[Neon.Record] fields 的键必须是非空字符串，收到 {Level.Describe(key)}`
		)
		merged[key] = value
	end
	return table.freeze(merged) :: Fields
end

return Record
