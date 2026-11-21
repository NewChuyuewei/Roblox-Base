--!strict
-- Neon.Channel —— 绑定频道与固定上下文字段的记录器（`.plan/PHASES.md` P2.W1）。
--
-- 为什么要记录器而不是让每处调用都写 `Neon.Info("combat", ...)`：同一个模块里几十条
-- 打印的频道是一样的，而上下文字段（`service`、`world`、`player`）也一样。把它们绑一次，
-- 调用点就只剩「发生了什么」这件事 —— 也少了一个「频道名打错」的入口。
--
-- 两条必须写下来的语义：
--   · 记录器上的函数是**闭包**，用 `.` 调用。写成 `recorder:Info("x")` 不会静默错位：
--     记录器会被当成 message 传进去，`Record` 的「message 必须是字符串」当场抛。
--   · `With` 返回**新记录器**，原记录器不变。就地合并会让「在某个玩家的处理函数里
--     临时加个字段」污染所有别的调用点，而这种污染只会以「日志里偶尔多/少字段」出现。
--
-- L0 约束：不碰引擎（`.plan/CARBON.md` §3.1）。

local Level = require(script.Parent.Level)
local Record = require(script.Parent.Record)
local Publish = require(script.Parent.Publish)

local Channel = {}

export type Recorder = {
	channel: string,
	fields: Record.Fields,
	Log: (level: any, message: string, extra: Record.Fields?) -> Record.Record?,
	Trace: (message: string, extra: Record.Fields?) -> Record.Record?,
	Debug: (message: string, extra: Record.Fields?) -> Record.Record?,
	Info: (message: string, extra: Record.Fields?) -> Record.Record?,
	Warn: (message: string, extra: Record.Fields?) -> Record.Record?,
	Error: (message: string, extra: Record.Fields?) -> Record.Record?,
	With: (extra: Record.Fields?) -> Recorder,
}

local function make(channelName: string, fields: Record.Fields): Recorder
	local function emit(level: any, message: string, extra: Record.Fields?): Record.Record
		return Publish.Emit(level, channelName, message, Record.MergeFields(fields, extra))
	end

	return {
		channel = channelName,
		fields = fields,
		Log = function(level: any, message: string, extra: Record.Fields?)
			return emit(level, message, extra)
		end,
		Trace = function(message: string, extra: Record.Fields?)
			return emit(Level.Trace, message, extra)
		end,
		Debug = function(message: string, extra: Record.Fields?)
			return emit(Level.Debug, message, extra)
		end,
		Info = function(message: string, extra: Record.Fields?)
			return emit(Level.Info, message, extra)
		end,
		Warn = function(message: string, extra: Record.Fields?)
			return emit(Level.Warn, message, extra)
		end,
		Error = function(message: string, extra: Record.Fields?)
			return emit(Level.Error, message, extra)
		end,
		With = function(extra: Record.Fields?): Recorder
			return make(channelName, Record.MergeFields(fields, extra))
		end,
	}
end

--[=[
	建一个绑定频道的记录器。`fields` 是这个记录器的固定上下文。

	频道名在这里就校验一次（`Record` 也会再校验）：早报到能把错误定位到「建记录器的那行」，
	而不是晚到「第一次打印的那行」—— 后者往往是启动很久之后的某条偶发路径。
]=]
function Channel.New(name: string, fields: Record.Fields?): Recorder
	assert(
		Record.IsOneLine(name),
		`[Neon.Channel] 频道名必须是不含换行的非空字符串，收到 {Level.Describe(name)}`
	)
	return make(name, Record.MergeFields(fields, nil))
end

return Channel
