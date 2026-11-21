--!strict
-- Neon.Level —— 五个级别的定义、序与规范化（`.plan/PHASES.md` P2.W1）。
--
-- 为什么单独一个模块：级别同时出现在入口（`Neon.Log` 的第一个参数）、过滤器
-- （W4 的最低级别）与格式化（W3 要把它渲染成定宽文本）。三处必须共用同一份序，
-- 否则「warn 到底算不算高于 info」这种问题会在三个文件里各答一次。
--
-- 与既有实现的关系（W8 迁移会踩到）：`Deuterium/Diagnostics/Logging/StructuredLog.luau`
-- 只有四级（`debug|info|warn|error`），这里多了 `trace`。因此 `Normalize` 不提供
-- 默认级别 —— 认不出就返回 `nil`，由调用方当场报错。静默降级成 `info` 的代价是：
-- 一条被降级的 warn 记录看起来完全正常，没人能把它找出来。
--
-- L0 约束：本文件不 require 任何模块、不碰引擎（`.plan/CARBON.md` §3.1）。

local Level = {}

export type Level = "trace" | "debug" | "info" | "warn" | "error"

-- 序值间隔 10：W4 的门槛比较要用它，日后插入中间级别（如 `fatal`）也不必重排全局。
-- 键类型写 `string` 而不是 `Level`：字典按联合类型索引时，类型系统会把结果标成可选，
-- 于是每次查表都要配一次收窄。`Deuterium` 的同类表也是这么写的（保持一致）。
local RANK: { [string]: number } = {
	trace = 10,
	debug = 20,
	info = 30,
	warn = 40,
	error = 50,
}

-- 渲染顺序 = 严重程度递增。`Level.Names()` 是这份顺序的唯一出口：顺序被抄第二遍之后，
-- 「哪个级别最低」就有了两个答案，而两个答案都可能是对的。
local NAMES: { Level } = { "trace", "debug", "info", "warn", "error" }

-- 常量出口，免得调用方到处写裸字符串（裸字符串打错一个字母是静默的，常量不是）。
--
-- 注意一个实测到的类型行为：这些字段在**调用点**的类型是 `string`，不是 `Level` 联合 ——
-- 可变表字段上的字面量类型会被推断放大，落到带标注的局部再摊平也一样（`types` 门禁两轮都
-- 报在同一条 `Record.New(Level.Info, ...)` 上）。所以不要指望签名上的联合类型替你看住这里，
-- 真正的大门是 `Level.Rank`：不在表里的名字当场抛错。`Record.New` 因此收 `any` 再校验。
--
-- 同一个坑还有下半截（`P2.W4` 的 types 门禁抓的）：`local TRACE = Level.Trace :: Level.Level`
-- **也**不行 —— 没有类型标注的 local 会把 cast 的结果再摊平一次，下一行 `Level.Rank(TRACE)`
-- 照样红。标注与收窄要同时占住：`local TRACE: Level.Level = Level.Trace :: Level.Level`，
-- 之后各处直接用 `TRACE`，不必每处重复写 cast（重复的那份迟早有一处漏掉）。
-- 与上面那句区分开：那句说的是「把带标注的局部**写进表字段**」会被摊平，这句说的是
-- 「把表字段**读进无标注的 local**」同样被摊平 —— 两半合起来才是完整规则：只有显式标注
-- 的那个名字（`local x: Level.Level = …`）保得住联合类型。
local levelTrace: Level = "trace"
local levelDebug: Level = "debug"
local levelInfo: Level = "info"
local levelWarn: Level = "warn"
local levelError: Level = "error"

Level.Trace = levelTrace
Level.Debug = levelDebug
Level.Info = levelInfo
Level.Warn = levelWarn
Level.Error = levelError

--[=[
	级别名 → 序值。未登记的级别直接抛错。

	为什么不返回 0/-1：那会让它「低于一切」，于是最低级别过滤把它静默吃掉，
	调用方看到的症状是「这条日志根本没打出来」，而真实原因是级别名写错了。
]=]
function Level.Rank(candidate: Level): number
	local rank = RANK[candidate]
	assert(
		rank ~= nil,
		`Neon.Level.Rank：未登记的级别 {Level.Describe(candidate)}（可用：trace debug info warn error）`
	)
	return rank :: number
end

--[=[
	`candidate` 是否达到 `minimum` 的门槛。W4 的最低级别过滤只用这一个比较。
]=]
function Level.AtLeast(candidate: Level, minimum: Level): boolean
	return Level.Rank(candidate) >= Level.Rank(minimum)
end

--[=[	是否是本组件登记的级别名。入口校验与 `Normalize` 共用。]=]
function Level.Is(value: any): boolean
	return type(value) == "string" and RANK[value :: string] ~= nil
end

--[=[
	把外部来的值规范成 `Level`；认不出返回 `nil`（**不猜**）。

	只接受大小写不敏感的精确名（`"INFO"` → `info`）。`Notice` / `Fatal` / `Warning`
	这种「看着像」的一律拒绝：猜一次就要为这个猜测写一辈子的注释。
]=]
function Level.Normalize(value: any): Level?
	if type(value) ~= "string" then
		return nil
	end
	local lowered = string.lower(value :: string)
	if RANK[lowered] ~= nil then
		return lowered :: Level
	end
	return nil
end

--[=[
	级别名列表（严重程度递增）。返回副本：直接把内部数组交出去，调用方排一次序就改了全局顺序。
]=]
function Level.Names(): { Level }
	local out: { Level } = {}
	for index = 1, #NAMES do
		out[index] = NAMES[index]
	end
	return out
end

--[=[
	把任意值渲染成可诊断的片段，供报错信息使用。截到 40 字符：
	级别位上塞进来的经常是一整个表，不截断会把错误信息挤开。
]=]
function Level.Describe(value: any): string
	local text = tostring(value)
	if #text > 40 then
		return string.sub(text, 1, 40) .. "…"
	end
	return text
end

return Level
