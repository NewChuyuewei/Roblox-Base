--!strict
-- Neon —— 集成式控制台打印系统 · 组件门面（`.plan/PHASES.md` P2.W1 / P2.W2）。
--
-- 入口：`require(ReplicatedStorage.Neon.Neon)`（`.plan/CARBON.md` §3.1：入口是 `<root>/<组件名>.luau`）。
--
-- 门面上只放两类东西：**发射**（`Log` + 五个级别简写 + `Channel`）与**接线**
-- （`AddSink` / `RemoveSink` / `SetClock` / `Stats` / `Reset`）。级别定义、记录结构、
-- 环形缓冲各自住在邻居模块；这里转出的 `Neon.Level` 等字段是**同一张表的引用**而不是副本
-- —— 抄一份出来就有了第二套真相，改一处忘另一处，两边就开始漂移。
--
-- 状态（截至本 Wave）：核心不碰引擎，能在 Lune 里跑完全部自检；`Host/`（W6）之后才有
-- 标准输出端，现在注册了输出端才有东西会显示出来 —— 「未注册输出端时不报错」是 W1
-- 判据的一部分，不是待补的空洞。
--
-- L0 约束：不碰引擎（`.plan/CARBON.md` §3.1）。

local Level = require(script.Parent.Level)
local Record = require(script.Parent.Record)
local Sink = require(script.Parent.Sink)
local RingSink = require(script.Parent.RingSink)
local Channel = require(script.Parent.Channel)
local Publish = require(script.Parent.Publish)

local Neon = {}

Neon.Level = Level
Neon.Record = Record
Neon.Sink = Sink
Neon.RingSink = RingSink

--[=[
	打印入口。`level` 可以是级别名或可规范化的字符串（`"INFO"` 可用，`"notice"` 抛错）。
	返回构造好的记录，方便调用方与测试直接断言；没有输出端时也返回。
]=]
function Neon.Log(level: any, channel: string, message: string, fields: Record.Fields?): Record.Record
	return Publish.Emit(level, channel, message, fields)
end

-- 五个简写：频道是第一参数（级别已经写在函数名里了，调用点少一个易错的字符串）。
function Neon.Trace(channel: string, message: string, fields: Record.Fields?): Record.Record
	return Publish.Emit(Level.Trace, channel, message, fields)
end

function Neon.Debug(channel: string, message: string, fields: Record.Fields?): Record.Record
	return Publish.Emit(Level.Debug, channel, message, fields)
end

function Neon.Info(channel: string, message: string, fields: Record.Fields?): Record.Record
	return Publish.Emit(Level.Info, channel, message, fields)
end

function Neon.Warn(channel: string, message: string, fields: Record.Fields?): Record.Record
	return Publish.Emit(Level.Warn, channel, message, fields)
end

function Neon.Error(channel: string, message: string, fields: Record.Fields?): Record.Record
	return Publish.Emit(Level.Error, channel, message, fields)
end

--[=[
	绑定频道的记录器：`Neon.Channel("combat", { world = "w1" })`。
	用法见 `Neon/Channel.luau`（`.` 调用、`With` 派生不改父记录器）。
]=]
function Neon.Channel(name: string, fields: Record.Fields?): Channel.Recorder
	return Channel.New(name, fields)
end

--[=[ 注册输出端（`Sink.New(name, write)` 或 `RingSink.New(capacity)` 造的表）。]=]
function Neon.AddSink(sink: Sink.Sink): ()
	Sink.Add(sink)
end

--[=[ 摘掉输出端：传输出端本身或它的 `name`，返回是否真的摘掉了。]=]
function Neon.RemoveSink(target: Sink.Sink | string): boolean
	return Sink.Remove(target)
end

--[=[ 当前注册数与名字，按注册顺序。]=]
function Neon.SinkNames(): { string }
	return Sink.Names()
end

--[=[ 换时间来源（测试注入假时钟、宿主绑定注入高精度时间）；传 `nil` 复原默认。]=]
function Neon.SetClock(source: (() -> number)?): ()
	Record.SetClock(source)
end

--[=[
	发射与投递的累计计数。给自检与「日志自己有没有在工作」这类运行时检查用。

	`logged` 与 `delivered + failed` 不一定相等：前者是「发了几条」，后两者是
	「几条 × 几个输出端」。把它们放一起返回而不做相等断言，是因为输出端数量由宿主决定，
	核心不能假设有几个。
]=]
function Neon.Stats(): { logged: number, sinks: number, delivered: number, failed: number }
	local sinkStats = Sink.Stats()
	return {
		logged = Publish.Logged(),
		sinks = Sink.Count(),
		delivered = sinkStats.delivered,
		failed = sinkStats.failed,
	}
end

--[=[
	全量清场：摘掉所有输出端、把时钟换回默认、计数归零。
	测试夹具之间必须是干净的起点 —— 上一例注册的输出端留在下一例里，
	「一条记录投递了几次」这种断言就失去意义了。
]=]
function Neon.Reset(): ()
	Sink.Reset()
	Publish.Reset()
	Record.SetClock(nil)
end

return Neon
