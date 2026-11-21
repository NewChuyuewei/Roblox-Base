--!strict
-- Neon.Filter —— 级别门槛、每频道限速、连续重复折叠（`.plan/PHASES.md` P2.W4）。
--
-- 为什么单独一个模块，而不是把三个开关塞进 `Sink` 或入口：过滤决定的是「这条记录到底
-- 存不存在于投递路径里」，而输出端只该决定「收到了怎么写」。这条边界在 W1/W2 就用例钉住
-- 过（`Sink.Write` 只有 `name` 与 `Write`），W4 若把门槛塞进输出端，就会变成「三个 sink
-- 三套级别语义」。发射路径只有一个 owner（`Publish`），过滤是它前面的一个闸门。
--
-- 四条语义是这一页的全部内容，写在实现上面是因为它们各自挡掉一类真实事故：
--
--   1. **过滤只改投递，不改 API 形状。** 被挡掉的记录照样构造、照样返回，调用方永远拿到
--      一条记录，不需要写 `if record then`。代价是被挡掉的那条也付一次表分配 —— 换来的是
--      「改一行配置就把调用点全炸了」不会发生。真想省这次分配，用 `Neon.Enabled()` 守卫。
--   2. **被折叠/被限速的条数不新造记录，也不改冻结记录**（记录是快照，改它就是撒谎），
--      而是**随同频道下一条真正投递的记录**带出去：字段 `repeated` / `rateDropped`。
--      如果那个频道从此再没有下一条，这些数就在 `Filter.Stats()` 里 —— 控制台（W7）读它。
--   3. **折叠优先于限速。** 一条「和第上一条一模一样」的记录既不该算重复次数、也不该吃
--      配额：两个都记就会同一件事出现两个数，读的人得自己做加法。
--   4. **时钟只从 `Record.Now()` 取**（W1 留的注入点）。限速与折叠都是「相对于时间」的
--      判断，读真实时间就等于把判据写成偶发失败 —— 测试里必须能拨表。
--
-- 一处容量护栏：每频道状态最多跟踪 `MAX_TRACKED_CHANNELS` 个。频道名可以是
-- `player:78` 这种按人现造的，不设上限就是「日志内容决定内存占用」；超出的频道退回
-- 只走全局门槛（少的是每频道精度，不是日志本身），并在 `Stats()` 里如实报出来。
--
-- L0 约束：不碰引擎（`.plan/CARBON.md` §3.1）。

local Level = require(script.Parent.Level)
local Record = require(script.Parent.Record)

local Filter = {}

-- 每频道状态的条数上限。256 是拍脑袋的吗：一半是「一个工程里真正长期存在的频道」的量级，
-- 另一半留给临时频道；再大就纯属把风险留给自己。
local MAX_TRACKED_CHANNELS = 256

export type Options = {
	minLevel: Level.Level,
	rate: number,
	repeatWindow: number,
}

export type Stats = {
	admitted: number,
	levelSuppressed: number,
	rateSuppressed: number,
	repeatSuppressed: number,
	trackedChannels: number,
	untrackedChannels: number,
}

type State = {
	second: number, -- 限速窗口的起点（日历秒）
	emitted: number, -- 本窗口内已投递几条
	at: number, -- 上一条**投递**记录的时刻
	level: string?, -- 上一条投递记录的级别
	message: string?, -- 上一条投递记录的正文
	repeated: number, -- 攒着待交出去的折叠次数
	rateDropped: number, -- 攒着待交出去的限速丢弃数
}

local TRACE_RANK = Level.Rank(Level.Trace)

-- 三项配置。`minLevel` 同时存名字与序值：名字给 `Options()` 读，序值给每次比较用
-- —— 每条日志都现查一遍 `RANK` 是白付的哈希查找。
local minLevel: Level.Level = Level.Trace
local minRank = TRACE_RANK
local rate = 0 -- 每频道每秒条数，0 = 不限
local repeatWindow = 0 -- 折叠窗口（秒），0 = 关

local channelMinRank: { [string]: number } = {}
local channelRate: { [string]: number } = {}
local states: { [string]: State } = {}

local tracked = 0
local untracked = 0
local admittedTotal = 0
local levelSuppressedTotal = 0
local rateSuppressedTotal = 0
local repeatSuppressedTotal = 0

-- 「全关」快路径。默认配置下过滤器必须几乎不花钱：它是每条日志都要过的一层，
-- 一个 `false` 判断换掉整段状态机 —— 而且这份省是**可验证**的（`Options()` 三项都是默认值时
-- 走的就是这条路）。
local active = false

local function refreshActive(): ()
	active = minRank ~= TRACE_RANK
		or rate > 0
		or repeatWindow > 0
		or next(channelMinRank) ~= nil
		or next(channelRate) ~= nil
end

-- 与 `Format.SetLimits` 同一套纪律：非法值抛错而不是夹紧（clamp），`nil` 表示「该项复位到
-- 默认」。夹紧会把「我以为是 100」变成「实际是 0」，而这种偏差只在日志莫名其妙少了的时候
-- 才暴露 —— 那时没人会怀疑是自己昨天配错了。
local function checkRate(value: any, name: string): number?
	if value == nil then
		return nil
	end
	assert(
		type(value) == "number"
			and math.floor(value :: number) == (value :: number)
			and value >= 0
			and value < math.huge,
		`[Neon.Filter] {name} 必须是 ≥ 0 的有限整数，收到 {Level.Describe(value)}`
	)
	return value :: number
end

local function checkWindow(value: any, name: string): number?
	if value == nil then
		return nil
	end
	assert(
		type(value) == "number" and value >= 0 and value == value and value < math.huge,
		`[Neon.Filter] {name} 必须是 ≥ 0 的有限数（允许小数），收到 {Level.Describe(value)}`
	)
	return value :: number
end

-- 频道名要过 `Record.IsOneLine`：这些名字会被拼进错误信息、也会被控制台拿去筛日志，
-- 判据只该有一份。
local function checkChannel(name: any): string
	assert(
		Record.IsOneLine(name :: string),
		`[Neon.Filter] 频道名必须是不含控制字符的非空字符串，收到 {Level.Describe(name)}`
	)
	return name :: string
end

--[=[
\t全局最低级别。低于它的记录不进投递路径。`nil` 复原成 `trace`（即不过滤）。
\t
\t为什么不静默认不出来的名字：`"notice"` 被当成 `info` 的代价是「日志看起来少了」而没人
\t知道为什么 —— 抛错只是想把这件事留在原地。
]=]
function Filter.SetMinimumLevel(level: any): ()
	if level == nil then
		minLevel = Level.Trace
		minRank = TRACE_RANK
	else
		local normalized = Level.Normalize(level)
		assert(
			normalized ~= nil,
			`[Neon.Filter] 未登记的级别 {Level.Describe(level)}（可用：trace debug info warn error，大小写不限）`
		)
		minLevel = normalized :: Level.Level
		minRank = Level.Rank(minLevel)
	end
	refreshActive()
end

--[=[ 某个频道的最低级别；`nil` 取消覆盖（回到全局）。]=]
function Filter.SetChannelMinimum(channel: string, level: any): ()
	local name = checkChannel(channel)
	if level == nil then
		channelMinRank[name] = nil
	else
		local normalized = Level.Normalize(level)
		assert(
			normalized ~= nil,
			`[Neon.Filter] 未登记的级别 {Level.Describe(level)}（可用：trace debug info warn error，大小写不限）`
		)
		channelMinRank[name] = Level.Rank(normalized :: Level.Level)
	end
	refreshActive()
end

--[=[ 全局每频道每秒条数上限；`nil` 或 `0` = 不限。]=]
function Filter.SetRate(limit: number?): ()
	local checked = checkRate(limit, "rate")
	rate = if checked == nil then 0 else checked
	refreshActive()
end

--[=[ 某个频道的每秒条数上限；`nil` 取消覆盖。]=]
function Filter.SetChannelRate(channel: string, limit: number?): ()
	local name = checkChannel(channel)
	local checked = checkRate(limit, "rate")
	if checked == nil or checked == 0 then
		channelRate[name] = nil
	else
		channelRate[name] = checked
	end
	refreshActive()
end

--[=[
\t连续重复折叠窗口（秒）。同一频道内「级别 + 正文」都与上一条**已投递**的记录相同、且间隔
\t不超过这个窗口的，记数不投递。`nil` 或 `0` = 关掉。
]=]
function Filter.SetRepeatWindow(seconds: number?): ()
	local checked = checkWindow(seconds, "repeatWindow")
	repeatWindow = if checked == nil then 0 else checked
	refreshActive()
end

--[=[ 生效中的全局配置快照，**冻结**（和 `Format.Limits()` 同一形状）。]=]
function Filter.Options(): Options
	return table.freeze({ minLevel = minLevel, rate = rate, repeatWindow = repeatWindow })
end

--[=[ 该频道实际生效的最低级别（覆盖优先）。]=]
function Filter.MinimumFor(channel: string): Level.Level
	local override = channelMinRank[channel]
	if override == nil or override == minRank then
		return minLevel
	end
	-- 序值 → 名字：只为「读回来给人看」，所以直接扫这五个（顺序来自 `Level.Names()`，
	-- 不在这里另立一份级别表）。
	local names = Level.Names()
	for index = 1, #names do
		if Level.Rank(names[index]) == override then
			return names[index]
		end
	end
	return minLevel
end

--[=[ 该频道实际生效的每秒条数上限（0 = 不限）。]=]
function Filter.RateFor(channel: string): number
	return channelRate[channel] or rate
end

--[=[
\t这条记录现在能不能打出来。**只读门槛，不消费配额** —— 给热路径守卫用的：
\t`if Neon.Enabled("debug", "net") then ... end` 里拼那串昂贵的正文不该改变限速器的账。
\t
\t级别名照样要过 `Level.Rank`：守卫这里放过一个拼错的级别名，症状是「整块日志从此不打」，
\t和发射路径一样该当场抛。
]=]
function Filter.Allows(level: any, channel: string?): boolean
	local floorRank = if channel == nil then minRank else (channelMinRank[channel :: string] or minRank)
	return Level.Rank(level) >= floorRank
end

--[=[
\t发射路径的唯一闸门：给出「投不投」，以及要随本条记录一起交出去的计数。

\t返回的第二个值是 `fields` 的增量（`{ repeated = N }` / `{ rateDropped = M }`），由
\t`Publish` 在构造记录**之前**合进去 —— 记录是冻结的快照，构造完再想加字段就得改契约了。
\t被挡掉时一律返回 `nil`：计数得留给下一条真正投递的记录，不然会被无声吃掉。
]=]
function Filter.Judge(level: any, channel: string, message: string): (boolean, Record.Fields?)
	if not active then
		admittedTotal += 1
		return true, nil
	end

	local floorRank = channelMinRank[channel] or minRank
	if Level.Rank(level) < floorRank then
		levelSuppressedTotal += 1
		return false, nil
	end

	local existing = states[channel]
	local state: State
	if existing == nil then
		if tracked >= MAX_TRACKED_CHANNELS then
			-- 超出跟踪上限：退回全局门槛之后直接投递，并如实计数。少的是每频道精度，
			-- 不是日志本身 —— 「内存吃紧就把日志丢掉」是反过来的做法。
			untracked += 1
			admittedTotal += 1
			return true, nil
		end
		state = {
			second = 0,
			emitted = 0,
			at = -math.huge,
			level = nil,
			message = nil,
			repeated = 0,
			rateDropped = 0,
		}
		states[channel] = state
		tracked += 1
	else
		state = existing
	end

	local now = Record.Now()

	-- 折叠：与上一条**投递**的记录一模一样，且还在窗口内。判等用 `==`（Luau 先比长度与
	-- 内部表示，绝大多数不等的情形一次指针比较就返回），不拼 key —— 每条日志拼一个
	-- `level .. "\1" .. message` 是白付的一次分配。
	if repeatWindow > 0 and state.level == level and state.message == message then
		if now - state.at <= repeatWindow then
			state.repeated += 1
			repeatSuppressedTotal += 1
			return false, nil
		end
	end

	local limit = channelRate[channel] or rate
	if limit > 0 then
		local second = math.floor(now)
		if second ~= state.second then
			state.second = second
			state.emitted = 0
		end
		if state.emitted >= limit then
			state.rateDropped += 1
			rateSuppressedTotal += 1
			return false, nil
		end
		state.emitted += 1
	end

	-- 投递：把攒下的计数随这条一起交出去，然后清零。
	local repeated = state.repeated
	local droppedByRate = state.rateDropped
	state.repeated = 0
	state.rateDropped = 0
	state.at = now
	state.level = tostring(level)
	state.message = message

	local note: Record.Fields? = nil
	if repeated > 0 and droppedByRate > 0 then
		note = { repeated = repeated, rateDropped = droppedByRate }
	elseif repeated > 0 then
		note = { repeated = repeated }
	elseif droppedByRate > 0 then
		note = { rateDropped = droppedByRate }
	end

	admittedTotal += 1
	return true, note
end

--[=[ 累计账目，**冻结**。给 W7 的控制台与「日志自己有没有在工作」这类运行时检查用。]=]
function Filter.Stats(): Stats
	return table.freeze({
		admitted = admittedTotal,
		levelSuppressed = levelSuppressedTotal,
		rateSuppressed = rateSuppressedTotal,
		repeatSuppressed = repeatSuppressedTotal,
		trackedChannels = tracked,
		untrackedChannels = untracked,
	})
end

--[=[
\t清场：配置回默认、每频道状态与账目归零。**不动输出端注册表** —— 那是 `Sink.Reset()` 的活。
\t两件事分开是因为测试夹具常常只想复位一个（比如「配置漏到下一例」和「上一例的 sink 还在」
\t是两类不同的污染，合在一起就没法只复现其中一类）。
]=]
function Filter.Reset(): ()
	minLevel = Level.Trace
	minRank = TRACE_RANK
	rate = 0
	repeatWindow = 0
	for name in channelMinRank do
		channelMinRank[name] = nil
	end
	for name in channelRate do
		channelRate[name] = nil
	end
	for name in states do
		states[name] = nil
	end
	tracked = 0
	untracked = 0
	admittedTotal = 0
	levelSuppressedTotal = 0
	rateSuppressedTotal = 0
	repeatSuppressedTotal = 0
	refreshActive()
end

return Filter
