--!strict
-- Neon 自检 —— 判据来自 `.plan/PHASES.md` 的 P2.W1 / P2.W2，逐例对应一条判据。
--
-- 跑法：`tests/run.luau` 的 `Dr.Neon` 套件在 Lune 里执行（`Loader.chain` + `RunAll()`）。
-- 刻意保持 headless：结果只走 `print` / `warn`，不 require 引擎 —— 「用日志系统测日志
-- 系统」是循环依赖，而 L0 一旦碰 `game` 就再也进不了 CI。
--
-- 每例前 `Neon.Reset()`：上一例注册的输出端留下来，「一条记录投递了几次」这类断言
-- 就失去意义了。这类夹具污染最难查，因为单独跑每例都对。
local Level = require(script.Parent.Level)
local Record = require(script.Parent.Record)
local Sink = require(script.Parent.Sink)
local RingSink = require(script.Parent.RingSink)
local Format = require(script.Parent.Format)
local Filter = require(script.Parent.Filter)
local Command = require(script.Parent.Command)
local Neon = require(script.Parent.Neon)

local SelfTest = {}

local function expect(condition: boolean, what: string): ()
	assert(condition, what)
end

-- `pcall` 的第二个返回值要能接住：直接 `pcall(run)` 而 `run` 不返回值时，类型系统把
-- 结果收窄成只有一个 boolean，多接一个 err 就是类型错误（`types` 门禁实测）。
-- 统一走这个包装，别在每处各写一遍闭包 —— 漏一处的症状是「错误文本变成 nil」。
local function protect(run: () -> ()): (boolean, any)
	local ok, err = pcall(function(): any
		run()
		return nil
	end)
	return ok, err
end

local function expectFails(run: () -> (), what: string, needle: string?): ()
	local ok, err = protect(run)
	expect(not ok, `{what}（期望抛错，实际正常返回）`)
	if needle ~= nil then
		local text = tostring(err)
		expect(
			string.find(text, needle, 1, true) ~= nil,
			`{what}：错误信息里没有 {needle}，实际是 {string.sub(text, 1, 120)}`
		)
	end
end

-- 只看字节结构的 UTF-8 完整性检查。本模块与 `Format` 都不依赖 `utf8.*`（vendor 的窄类型
-- 定义里不一定声明了它），而「截断没切半个字符」这件事必须能被断言，否则等于没测。
local function utf8Complete(text: string): boolean
	local index = 1
	local length = #text
	while index <= length do
		local byte = string.byte(text, index) :: number
		local width: number
		if byte >= 0xF0 then
			width = 4
		elseif byte >= 0xE0 then
			width = 3
		elseif byte >= 0xC0 then
			width = 2
		else
			width = 1
		end
		if index + width - 1 > length then
			return false
		end
		for offset = 1, width - 1 do
			local cont = string.byte(text, index + offset) :: number
			if cont < 0x80 or cont >= 0xC0 then
				return false
			end
		end
		index += width
	end
	return true
end

-- 收集型输出端：断言「记录到了哪里、到了几个」全靠它。
-- `Collector` 结构上已满足 `Sink.Sink`（有 name 与 Write），所以能直接注册；
-- 不套 metatable —— 伪装出来的表在 `Sink.Add` 的字段校验里行为更难推理。
type Collector = {
	name: string,
	Write: (Record.Record) -> (),
	Got: () -> { Record.Record },
}

local function collector(name: string): Collector
	local got: { Record.Record } = {}
	return {
		name = name,
		Write = function(record: Record.Record)
			table.insert(got, record)
		end,
		Got = function(): { Record.Record }
			return got
		end,
	}
end

local cases: { { name: string, run: () -> () } } = {
	-- ---------- P2.W1：打印入口 ----------
	{
		name = "W1·一条 Info 产生字段齐全的记录并交给已注册的输出端",
		run = function()
			local sink = collector("cap")
			Neon.AddSink(sink)
			Neon.SetClock(function()
				return 1234
			end)
			local record = Neon.Info("combat", "hit", { skill = 7 })
			local got = sink.Got()
			expect(#got == 1, "输出端应恰好收到一条")
			expect(got[1] == record, "输出端收到的必须是同一个记录引用")
			expect(record.time == 1234, "time 取自注入时钟")
			expect(record.level == "info", "level 是 info")
			expect(record.channel == "combat", "channel 是 combat")
			expect(record.message == "hit", "message 原样")
			expect(record.fields.skill == 7, "fields 带上了上下文字段")
		end,
	},
	{
		name = "W1·未注册输出端时不报错",
		run = function()
			local record = Neon.Info("combat", "no sink")
			expect(record ~= nil, "没有输出端也必须返回记录")
			local stats = Neon.Stats()
			expect(stats.logged == 1 and stats.sinks == 0, "logged 计入、sinks 为零")
			expect(stats.delivered == 0 and stats.failed == 0, "没有投递对象时两个计数都是零")
		end,
	},
	{
		name = "W1·五个简写各自产生对应级别，且序递增",
		run = function()
			local sink = collector("cap")
			Neon.AddSink(sink)
			Neon.Trace("c", "t")
			Neon.Debug("c", "d")
			Neon.Info("c", "i")
			Neon.Warn("c", "w")
			Neon.Error("c", "e")
			local got = sink.Got()
			local want: { Level.Level } = { "trace", "debug", "info", "warn", "error" }
			expect(#got == 5, "五条都到了输出端")
			for index = 1, 5 do
				expect(got[index].level == want[index], `第 {index} 条级别应为 {want[index]}`)
			end
			local names = Level.Names()
			expect(#names == 5, "级别表就是这五个")
			for index = 2, #names do
				expect(
					Level.Rank(names[index]) > Level.Rank(names[index - 1]),
					`序必须递增：{names[index - 1]} -> {names[index]}`
				)
			end
		end,
	},
	{
		name = "W1·大小写无关，未知级别当场抛错（不静默降级成 info）",
		run = function()
			local record = Neon.Log("INFO", "c", "shout")
			expect(record.level == "info", '"INFO" 规范化为 info')
			expectFails(function()
				Neon.Log("notice", "c", "x")
			end, "未登记的级别必须抛错", "未登记的级别")
			expectFails(function()
				Neon.Log({ "table" }, "c", "x")
			end, "级别位上塞表必须抛错")
			expect(
				Neon.Stats().logged == 1,
				"抛掉的记录不计数：猜出来的级别不该出现在日志里"
			)
		end,
	},
	{
		name = "W1·记录是调用时刻的快照，且不可就地改",
		run = function()
			local sink = collector("cap")
			Neon.AddSink(sink)
			local fields = { hp = 100 }
			local record = Neon.Info("c", "before", fields)
			fields.hp = 1 -- 打印之后调用方继续用自己的表
			expect(
				record.fields.hp == 100,
				"记录里的字段必须停留在调用时刻，否则同一轮里两个输出端会读到两套值"
			)
			expectFails(function()
				(record :: any).message = "tampered"
			end, "记录被冻结")
			expectFails(function()
				record.fields.hp = 2
			end, "fields 也被浅冻结")
		end,
	},
	{
		name = "W1·输入校验：channel 换行 / message 非串 / fields 键非法",
		run = function()
			expectFails(function()
				Neon.Info("bad\nchannel", "x")
			end, "频道名带换行必须抛错（W3 的单行格式前提）", "channel")
			expectFails(function()
				Neon.Info("", "x")
			end, "空频道名必须抛错")
			expectFails(function()
				Neon.Info("c", 42 :: any)
			end, "message 非字符串必须抛错", "message")
			expectFails(function()
				Neon.Info("c", "x", { [1] = "number key" } :: any)
			end, "fields 的键必须是字符串", "键")
		end,
	},
	{
		name = "W1·时钟可注入且复位回默认",
		run = function()
			local defaultClock = Record.GetClock()
			local fake = function()
				return 99
			end
			Neon.SetClock(fake)
			expect(Record.GetClock() == fake, "注入后 GetClock 就是那个函数")
			expect(Record.Now() == 99, "Now 走注入值")
			Neon.SetClock(nil)
			expect(Record.GetClock() == defaultClock, "传 nil 必须复原默认时钟")
			expectFails(function()
				Neon.SetClock(1 :: any)
			end, "SetClock 只收函数")
			expectFails(function()
				Neon.SetClock(function()
					return nil :: any
				end)
				Neon.Info("c", "x")
			end, "时钟返回非有限数要当场炸", "时钟")
		end,
	},
	{
		name = "W1·Channel 记录器：固定频道与上下文字段，With 派生不污染父记录器",
		run = function()
			local sink = collector("cap")
			Neon.AddSink(sink)
			local combat = Neon.Channel("combat", { world = "w1" })
			combat.Info("hit", { skill = 7 })
			local raid = combat.With({ raid = true })
			raid.Warn("boss")
			combat.Info("after")
			local got = sink.Got()
			expect(#got == 3, "三条都到了输出端")
			expect(
				got[1].channel == "combat" and got[1].fields.world == "w1",
				"父记录器带上固定频道与上下文"
			)
			expect(got[2].fields.raid == true and got[2].fields.world == "w1", "派生记录器合并字段")
			expect(got[2].level == "warn", "级别简写在记录器上同样有效")
			expect(
				got[3].fields.raid == nil,
				"派生不得污染父记录器：第三条不该看到 raid 字段"
			)
			expect(combat.channel == "combat" and raid.channel == "combat", "频道沿用父名")
			-- `recorder:Info()` 把记录器本身当成 message 传进来；`recorder:Info(x)` 则把 x
			-- 塞进 extra（fields）。两种都要抛错，但抛出点不同，分开判：
			-- 混成一条断言时，我原先「一定是 message 校验挡住」的猜测就是错的（实测先撞 fields）。
			expectFails(function()
				(combat :: any):Info()
			end, "用 : 调用记录器必须当场抛错（记录器被当成 message）", "message")
			expectFails(function()
				(combat :: any):Info("colon call")
			end, "用 : 调用且带参数时也必须抛错（参数落到 fields）")
			expectFails(function()
				Neon.Channel("c\n")
			end, "建记录器时就校验频道名")
		end,
	},

	-- ---------- P2.W2：输出端与环形缓冲 ----------
	{
		name = "W2·容量 3 写 5 条：读回最后 3 条且顺序由旧到新",
		run = function()
			local ring = RingSink.New(3)
			Neon.AddSink(ring)
			for index = 1, 5 do
				Neon.Info("c", `m{index}`)
			end
			local records = ring.Records()
			expect(#records == 3, "只留最后 3 条")
			expect(records[1].message == "m3", "最旧的是 m3")
			expect(records[2].message == "m4", "接着 m4")
			expect(records[3].message == "m5", "最新的是 m5")
			expect(
				ring.Count() == 3 and ring.Written() == 5 and ring.Dropped() == 2,
				"计数：存 3 / 收 5 / 覆盖 2"
			)
			expect(ring.Capacity() == 3, "容量读得回来")
		end,
	},
	{
		name = "W2·一个输出端抛错，其余仍收到，且投递顺序 = 注册顺序",
		run = function()
			local orderSeen: { string } = {}
			local first = Sink.New("first", function()
				table.insert(orderSeen, "first")
			end)
			local bomb = Sink.New("bomb", function()
				error("输出端自己坏了")
			end)
			local last = Sink.New("last", function()
				table.insert(orderSeen, "last")
			end)
			Neon.AddSink(first)
			Neon.AddSink(bomb)
			Neon.AddSink(last)
			Neon.Info("c", "isolation")
			expect(
				#orderSeen == 2 and orderSeen[1] == "first" and orderSeen[2] == "last",
				"坏掉的没挡住后面的，顺序仍是注册顺序"
			)
			local stats = Neon.Stats()
			expect(
				stats.logged == 1 and stats.sinks == 3 and stats.delivered == 2 and stats.failed == 1,
				"统计口径：一次发射、三个 sink、两成一把失败"
			)
		end,
	},
	{
		name = "W2·Broadcast 的返回值点名是哪个输出端坏了",
		run = function()
			-- 直接调 Broadcast，不经发射路径：本例只验返回结构，不该动 `logged`。
			Neon.AddSink(Sink.New("good", function() end))
			Neon.AddSink(Sink.New("bomb", function()
				error("输出端自己坏了")
			end))
			local result = Sink.Broadcast(Record.New(Level.Info, "c", "x", nil))
			expect(result.delivered == 1 and result.failed == 1, "一成一把失败")
			expect(
				#result.errors == 1 and string.find(result.errors[1], "bomb:", 1, true) == 1,
				"错误里带输出端名"
			)
			expect(Neon.Stats().logged == 0, "没走发射路径就不该计入 logged")
		end,
	},
	{
		name = "W2·重复注册同一个输出端被拒（症状是每条日志双份）",
		run = function()
			local sink = collector("dup")
			Neon.AddSink(sink)
			expectFails(function()
				Neon.AddSink(sink)
			end, "同一实例重复注册", "重复注册")
			expectFails(function()
				Neon.AddSink(Sink.New("dup", function() end))
			end, "同名不同实例也要拒", "名字撞了")
			expect(Neon.Stats().sinks == 1, "被拒的注册没有留下半个")
		end,
	},
	{
		name = "W2·RemoveSink 按实例与按名字都摘得掉，摘不到返回 false",
		run = function()
			local a = Sink.New("a", function() end)
			local b = Sink.New("b", function() end)
			Neon.AddSink(a)
			Neon.AddSink(b)
			expect(Neon.RemoveSink(a) == true, "按实例摘掉")
			expect(Neon.RemoveSink("b") == true, "按名字摘掉")
			expect(Neon.RemoveSink(a) == false, "重复摘返回 false")
			expect(Neon.RemoveSink("missing") == false, "没注册过的名字返回 false")
			expect(Neon.Stats().sinks == 0, "注册表空了")
		end,
	},
	{
		name = "W2·Reset 就地清空：Snapshot 仍是同一张表",
		run = function()
			local snapshot = Sink.Snapshot()
			Neon.AddSink(Sink.New("x", function() end))
			Neon.AddSink(Sink.New("y", function() end))
			expect(#snapshot == 2, "活引用看得见注册")
			Neon.Reset()
			expect(Sink.Snapshot() == snapshot, "Reset 不得换表：换了引用比较就静默失效")
			expect(#snapshot == 0, "同一张表已被清空")
			expect(Neon.Stats().delivered == 0 and Neon.Stats().failed == 0, "计数一起归零")
		end,
	},
	{
		name = "W2·环形缓冲 Reset 后可继续写，Written 是累计口径",
		run = function()
			local ring = RingSink.New(2)
			Neon.AddSink(ring)
			Neon.Info("c", "m1")
			Neon.Info("c", "m2")
			expect(ring.Reset() == 2, "Reset 返回被清掉的条数")
			expect(#ring.Records() == 0 and ring.Count() == 0, "清空后什么都不剩")
			Neon.Info("c", "m3")
			local records = ring.Records()
			expect(#records == 1 and records[1].message == "m3", "清完还能继续用")
			expect(
				ring.Written() == 3 and ring.Dropped() == 0,
				"Written 是累计收到过几条，不随 Reset 回退"
			)
		end,
	},
	{
		name = "W2·capacity 0 只计数不存；非法容量抛错",
		run = function()
			local ring = RingSink.New(0)
			Neon.AddSink(ring)
			Neon.Info("c", "m1")
			Neon.Info("c", "m2")
			expect(#ring.Records() == 0, "容量 0 不存记录")
			expect(ring.Count() == 0 and ring.Written() == 2 and ring.Dropped() == 2, "但仍计数")
			expectFails(
				function()
					RingSink.New(3.5)
				end,
				"小数容量必须抛错（不是四舍五入的小事，是调用方对容量的理解不一样）"
			)
			expectFails(function()
				RingSink.New(-1)
			end, "负容量必须抛错")
			expectFails(function()
				RingSink.New("3" :: any)
			end, "字符串容量必须抛错")
			-- 顺带记一笔：原先这里想用 `for _, bad in { 3.5, -1, "3", nil }` 一批测完，
			-- 但 nil 在数组字面量里等于「没有这一项」，那一例会静默消失；混合类型还会被
			-- 推断成 {number}。逐条写的成本是 6 行，换掉的是「少测一例而无人知晓」。
			expectFails(function()
				RingSink.New(nil :: any)
			end, "缺容量必须抛错")
		end,
	},
	{
		name = "W2·Sink 构造与注册的形状校验",
		run = function()
			expectFails(function()
				Sink.New("", function() end)
			end, "空名字必须抛错")
			expectFails(function()
				Sink.New("bad\nname", function() end)
			end, "名字带换行必须抛错（它会出现在错误信息与广播顺序里）")
			expectFails(function()
				Sink.New("s", "not a function" :: any)
			end, "Write 不是函数必须抛错", "Write")
			expectFails(function()
				Neon.AddSink(function() end :: any)
			end, "裸函数不能直接当输出端（要先 Sink.New）", "Sink.New")
			local ring = RingSink.New(1)
			expect(string.sub(ring.name, 1, 4) == "ring", `自动名字可读：{ring.name}`)
			local other = RingSink.New(1)
			expect(
				other.name ~= ring.name,
				"两个匿名环形的自动编号必须不同，否则第二次注册撞名"
			)
			Neon.AddSink(ring)
			Neon.AddSink(other)
			expect(Neon.Stats().sinks == 2, "自动编号互不撞名，两个都能挂上")
		end,
	},
	{
		name = "W2·广播途中新注册的不是不参与本轮",
		run = function()
			local late = collector("late")
			local wired = false
			local hook = Sink.New("hook", function()
				if not wired then
					wired = true
					Neon.AddSink(late)
				end
			end)
			Neon.AddSink(hook)
			Neon.Info("c", "first")
			expect(#late.Got() == 0, "本轮不叫上新来的：否则谁被叫到取决于副作用")
			Neon.Info("c", "second")
			expect(#late.Got() == 1, "下一轮才收到")
		end,
	},
	{
		name = "W1/W2 交界·级别过滤属于 Filter，不属于 Sink（这条钉住职责边界）",
		run = function()
			-- 输出端收到的记录不做任何级别筛选：W4 的过滤器在发射之前决定收不收。
			-- 现在没有过滤，所以 trace 也必须原样到达 —— 提前在这里筛一次，W4 的
			-- 「低于最低级别的记录不到达输出端」就会有两个 owner，测试也就失去意义。
			local sink = collector("cap")
			Neon.AddSink(sink)
			Neon.Trace("c", "still delivered")
			expect(#sink.Got() == 1, "trace 不被任何环节丢掉")
			expect(sink.Got()[1].level == Level.Trace, "级别名与常量表是同一个值")
		end,
	},

	-- ---------- P2.W3：格式化 ----------
	{
		name = "W3·同一条记录渲染两次完全相同，且与字段插入顺序无关",
		run = function()
			local first = Neon.Info("c", "m", { z = 1, a = 2 })
			local second = Neon.Info("c", "m", { a = 2, z = 1 })
			local textA = Format.Line(first)
			expect(textA == Format.Line(first), "同一条记录两次渲染必须逐字节相同")
			expect(
				textA == Format.Line(second),
				"渲染不该取决于表的插入顺序（next 不保证顺序）"
			)
			expect(string.find(textA, "a=2, z=1", 1, true) ~= nil, "键按字典序排列")
			expect(
				string.find(textA, "] INFO  c: m", 1, true) ~= nil,
				"级别右对齐到 5 宽 + 频道 + 正文"
			)
		end,
	},
	{
		name = "W3·控制字符折叠成可见转义（单行是硬要求）",
		run = function()
			local line = Format.Line(Neon.Info("c", "first\nsecond\tthird\rfourth"))
			expect(string.find(line, "\n", 1, true) == nil, "渲染结果里不许出现裸换行")
			expect(string.find(line, "\r", 1, true) == nil, "也不许出现裸回车")
			expect(
				string.find(line, "\\n", 1, true) ~= nil
					and string.find(line, "\\t", 1, true) ~= nil
					and string.find(line, "\\r", 1, true) ~= nil,
				"三种控制字符都要转成可见形式"
			)
			-- 没有控制字符时不该被 gsub 动过（一次多余的字符串构造在每条日志上都要付）
			local plain = Format.Line(Neon.Info("c", "no control chars here"))
			expect(string.find(plain, "no control chars here", 1, true) ~= nil, "正文原样出现")
		end,
	},
	{
		name = "W3·截断标出被丢掉的字节数，省略号计入上限",
		run = function()
			Format.SetLimits({ maxMessageLength = 12 })
			local line = Format.Line(Neon.Info("c", string.rep("x", 20)))
			-- 12 的上限里省略号占 3 字节 → 正文 9 个 x，丢掉 11 个，并且把这个数说出来
			expect(string.find(line, "xxxxxxxxx…(+11)", 1, true) ~= nil, `实际渲染：{line}`)
			Format.SetLimits({ maxMessageLength = 2000 })
			local short = Format.Line(Neon.Info("c", "short"))
			expect(string.find(short, "(+", 1, true) == nil, "没截就不许标截断")
		end,
	},
	{
		name = "W3·截断必须落在 UTF-8 字符边界（中文日志不能变半个字）",
		run = function()
			local chinese = "中文中文中文中文中文"
			for limit = 4, 14 do
				Format.SetLimits({ maxValueLength = limit })
				local text = Format.Value({ s = chinese })
				expect(
					utf8Complete(text),
					`上限 {limit} 时截出了半个字符：{string.format("%q", text)}`
				)
			end
		end,
	},
	{
		name = "W3·自引用的表标 <cycle> 而不是死循环；兄弟重复不算循环",
		run = function()
			local loop = { name = "loop" }
			loop.self = loop
			local text = Format.Value(loop)
			expect(string.find(text, "<cycle>", 1, true) ~= nil, `实际：{text}`)
			expect(string.find(text, 'name="loop"', 1, true) ~= nil, "循环之外的键照常渲染")
			local shared = { n = 1 }
			local twin = Format.Value({ a = shared, b = shared })
			expect(
				string.find(twin, "<cycle>", 1, true) == nil,
				"同一表出现在两个兄弟位置是常见形状，不该被当成循环"
			)
			expect(
				string.find(twin, "a={n=1}", 1, true) ~= nil and string.find(twin, "b={n=1}", 1, true) ~= nil,
				"两处都展开"
			)
		end,
	},
	{
		name = "W3·超过深度上限就折叠，并带上元素数",
		run = function()
			local deep = { l1 = { l2 = { l3 = "x" } } }
			local text = Format.Value(deep)
			expect(
				string.find(text, "<table:1>", 1, true) ~= nil,
				`超深部分折叠成 <table:元素数>，实际：{text}`
			)
			expect(string.find(text, "l3", 1, true) == nil, "超深的键不再展开")
		end,
	},
	{
		name = "W3·函数与 userdata 只印类型，绝不带地址",
		run = function()
			local text = Format.Value(print)
			expect(text == "<function>", `函数渲染成 <function>，实际：{text}`)
			expect(
				string.find(text, "0x", 1, true) == nil,
				"地址每次运行都不同：带上它，「两次渲染相同」这条判据永远失败"
			)
			local mixed = Format.Value({ f = print, n = 1 })
			expect(
				string.find(mixed, "f=<function>", 1, true) ~= nil,
				`表里的函数同样处理，实际：{mixed}`
			)
		end,
	},
	{
		name = "W3·整行也有硬上限（64 个键拼起来足以挤爆控制台）",
		run = function()
			Format.SetLimits({ maxLineLength = 20 })
			local fields: { [string]: any } = {}
			for index = 1, 40 do
				fields[`k{index}`] = index
			end
			local line = Format.Line(Neon.Info("c", "wide", fields))
			expect(
				string.sub(line, 18, 20) == "…",
				`正文截到上限处，实际前 24 字节：{string.sub(line, 1, 24)}`
			)
			expect(
				#line > 20 and string.find(line, "(+", 1, true) ~= nil,
				"省略号之后的 (+N) 是附加说明，允许超出上限几个字节"
			)
			expect(Format.Limits().maxLineLength == 20, "上限读得回来")
		end,
	},
	{
		name = "W3·SetLimits 校验非法值，且失败时不留半套新配置",
		run = function()
			local before = Format.Limits()
			expectFails(function()
				Format.SetLimits({ maxDepth = 3.5 })
			end, "小数上限必须抛错", "maxDepth")
			expectFails(function()
				Format.SetLimits({ maxValueLength = 3 })
			end, "比省略号还短的上限必须抛错")
			expectFails(function()
				Format.SetLimits("nope" :: any)
			end, "SetLimits 只收表")
			-- 关键一例：前一项合法、后一项非法。逐项赋值的写法会在这里留下 maxDepth=1。
			expectFails(function()
				Format.SetLimits({ maxDepth = 1, maxValueLength = 0 })
			end, "混合合法与非法时必须整体抛错")
			local now = Format.Limits()
			expect(
				now.maxDepth == before.maxDepth
					and now.maxValueLength == before.maxValueLength
					and now.maxMessageLength == before.maxMessageLength
					and now.maxLineLength == before.maxLineLength,
				"抛错的调用一项都不许生效"
			)
		end,
	},
	{
		name = "W3·Limits 快照是冻结的，改不动模块配置",
		run = function()
			local snapshot = Format.Limits()
			expectFails(function()
				(snapshot :: any).maxDepth = 99
			end, "快照必须冻结：能被随手改的快照就是第二套配置")
			expect(Format.Limits().maxDepth ~= 99, "模块配置不受影响")
		end,
	},
	{
		name = "W3·坏输入降级而不是抛错：缺 fields 的裸记录、非有限时间戳",
		run = function()
			local raw: any = { time = 0 / 0, level = "info", channel = "c", message = "m" }
			local line = Format.Line(raw)
			expect(string.find(line, "<time?>", 1, true) ~= nil, "时间戳坏了就标记它，正文照打")
			expect(string.find(line, ": m", 1, true) ~= nil, "正文没丢")
			expect(string.find(line, "{}", 1, true) == nil, "没有字段时不打空花括号")
			expectFails(function()
				Format.Line(nil :: any)
			end, "传进来的根本不是记录时必须抛错", "Line")
			expect(Format.Time(math.huge) == "<time?>", "±inf 同样降级")
			expect(
				Format.Time(86400) == "00:00:00",
				"渲染走 UTC：同一条记录在两台机器上必须印出同一段文本"
			)
		end,
	},
	{
		name = "W3·零输出端时广播返回共享的冻结空结果（热路径不分配）",
		run = function()
			local record = Neon.Info("c", "nobody listening")
			local result = Sink.Broadcast(record)
			expect(
				result.delivered == 0 and result.failed == 0 and #result.errors == 0,
				"空结果内容正确"
			)
			expect(result == Sink.Broadcast(record), "同一个共享表：省掉每条日志一次的分配")
			-- 只断言「抛错」，不断言错误文本：冻结表的报错措辞归运行时（Lune 与 Studio
			-- 就不一样），把它钉进用例会变成「升级运行时先炸测试」。
			expectFails(function()
				(result :: any).delivered = 7
			end, "共享结果必须冻结，否则一个调用方能改坏别人的读数")
		end,
	},

	-- ---------- P2.W3 加固：控制字符与「能被关掉的上限」 ----------
	{
		name = "W3 加固·渲染结果里不残留任何裸控制字符（NUL / DEL / ANSI 都算）",
		run = function()
			local samples = {
				"a\0b", -- NUL：一个就够让 grep 把整份日志判成二进制并停止打印匹配行
				"\027[31mred\027[0m", -- ANSI：原样交出去就被宿主终端执行
				"\a\b\v\f", -- 其余空白类：控制台列表就此错位
				"del\127end",
				"tab\there",
			}
			for index = 1, #samples do
				local sample = samples[index]
				local rendered = Format.Value(sample)
				expect(
					string.find(rendered, "%c", 1) == nil,
					`样本 {index} 渲染后仍有裸控制字符：{string.format("%q", rendered)}`
				)
				local line = Format.Line(Neon.Info("c", sample))
				expect(
					string.find(line, "%c", 1) == nil,
					`样本 {index} 的整行仍有裸控制字符：{string.format("%q", line)}`
				)
				expect(
					string.find(line, sample, 1, true) == nil,
					`样本 {index} 原文照抄进行里了，转义没生效`
				)
			end
		end,
	},
	{
		name = "W3 加固·ESC 变可见形式；(+N) 按渲染后的字节计",
		run = function()
			local text = Format.Value("\027[31m")
			expect(
				string.find(text, "\\x1b[31m", 1, true) ~= nil,
				`ESC 要印成 \\x1b，实际：{string.format("%q", text)}`
			)
			-- 转义会放大正文，所以 `(+N)` 数的是「渲染后」被丢掉的字节数。这条规则钉在这里，
			-- 免得日后被「顺手改成按原文计」—— 那样上限就管不住实际输出宽度了。
			-- 4 个换行 → 8 字节渲染；上限 6 含省略号 3 字节 → 留 3 字节 → 丢 5。
			Format.SetLimits({ maxMessageLength = 6 })
			local line = Format.Line(Neon.Info("c", "\n\n\n\n"))
			expect(
				string.find(line, "(+5)", 1, true) ~= nil,
				`要标出丢了 5 个渲染字节，实际：{line}`
			)
		end,
	},
	{
		name = "W1/W3 交界·会被印出来的标识符拒绝一切控制字符",
		run = function()
			expectFails(function()
				Neon.Info("a\0b", "x")
			end, "频道名含 NUL 必须抛错", "channel")
			expectFails(function()
				Neon.Info("a\027b", "x")
			end, "频道名含 ESC 必须抛错")
			expectFails(function()
				Neon.Info("a\tb", "x")
			end, "制表符也挡：它会把定宽级别与正文之间的那点错位放大成整列错位")
			expectFails(function()
				Sink.New("na\0me", function(_record: Record.Record) end)
			end, "输出端名归同一份判定管")
			expectFails(function()
				Neon.Channel("a\vb")
			end, "记录器名也归同一份判定管")
		end,
	},
	{
		name = "W3 加固·maxDepth 不能被配成「没有上限」",
		run = function()
			-- `math.floor(math.huge) == math.huge` 成立，只查「整数 + 下界」会把 +inf 放进来，
			-- 而 +inf 深度 = 折叠被关掉。折叠是这个模块唯一的递归保护。
			expectFails(function()
				Format.SetLimits({ maxDepth = math.huge })
			end, "上限不能设成无穷", "maxDepth")
			expectFails(function()
				Format.SetLimits({ maxDepth = 0 / 0 })
			end, "nan 也不行")
			expectFails(function()
				Format.SetLimits({ maxDepth = 1000 })
			end, "深度上限本身必须有上界", "maxDepth")
			expect(Format.Limits().maxDepth == 2, "抛错的调用一项都不许生效")
			Format.SetLimits({ maxDepth = 8 })
			expect(Format.Limits().maxDepth == 8, "合法范围内的放宽要真的生效")
			-- 200 层链式表：折叠在就只是「看不深」，折叠被关掉就是栈溢出 —— 那种失败连报告
			-- 都留不下，所以这一例断言的是「不炸 + 被折叠 + 长度受控」，不是具体文本。
			local deep: any = { leaf = 1 }
			for _ = 1, 200 do
				deep = { next = deep }
			end
			local text = Format.Value(deep)
			expect(string.find(text, "<table:", 1, true) ~= nil, "深结构必须被折叠")
			expect(#text < 2000, `渲染长度必须受控，实际 {#text}`)
		end,
	},
	{
		name = "W2 加固·Records() 是快照：之后的写入不动已交出去的那份",
		run = function()
			local ring = RingSink.New(3)
			ring.Write(Record.New("info", "c", "one"))
			ring.Write(Record.New("info", "c", "two"))
			local snapshot = ring.Records()
			expect(#snapshot == 2, "先读到两条")
			ring.Write(Record.New("info", "c", "three"))
			ring.Write(Record.New("info", "c", "four"))
			expect(
				#snapshot == 2 and snapshot[1].message == "one" and snapshot[2].message == "two",
				"W7 的控制台会把它攥在手里跨帧渲染，那份数组不能自己变"
			)
			local now = ring.Records()
			expect(#now == 3, "写满后仍只留容量那么多条")
			expect(
				now[1].message == "two" and now[2].message == "three" and now[3].message == "four",
				"由旧到新，覆盖掉的是最旧那条"
			)
		end,
	},

	-- ---------- P2.W4：过滤与限速 ----------
	{
		name = "W4·低于全局门槛的记录不到达输出端（但调用方照样拿到记录）",
		run = function()
			Filter.SetMinimumLevel("warn")
			local sink = collector("cap")
			Neon.AddSink(sink)
			local dropped = Neon.Info("c", "hidden")
			expect(
				dropped ~= nil,
				"被挡掉的记录仍要返回：API 的形状不能取决于日志配置"
			)
			expect(#sink.Got() == 0, "低于门槛的一条也不许到输出端")
			Neon.Warn("c", "kept")
			expect(#sink.Got() == 1, "达到门槛的正常投递")
			local stats = Filter.Stats()
			expect(stats.levelSuppressed == 1, `门槛计数要单列，实际 {stats.levelSuppressed}`)
			expect(stats.rateSuppressed == 0 and stats.repeatSuppressed == 0, "没开的开关不该记账")
			expect(Neon.Stats().logged == 1, "投递数只数真投递的")
		end,
	},
	{
		name = "W4·每频道门槛盖过全局",
		run = function()
			Filter.SetMinimumLevel("warn")
			Filter.SetChannelMinimum("chat", "error")
			local sink = collector("cap")
			Neon.AddSink(sink)
			Neon.Warn("chat", " muted")
			expect(#sink.Got() == 0, "chat 的门槛是 error，warn 进不来")
			Neon.Error("chat", "loud")
			expect(#sink.Got() == 1, "error 过")
			Neon.Info("c", "x")
			Neon.Warn("c", "y")
			expect(#sink.Got() == 2, "别的频道仍走全局门槛")
			expect(Filter.MinimumFor("chat") == "error", "读回来的覆盖值")
			expect(Filter.MinimumFor("c") == "warn", "没覆盖的频道读回全局")
			Filter.SetChannelMinimum("chat", nil)
			expect(Filter.MinimumFor("chat") == "warn", "传 nil 取消覆盖")
		end,
	},
	{
		name = "W4·限速按注入时钟的日历秒走，丢弃数落在下一条",
		run = function()
			local now = 100
			Neon.SetClock(function()
				return now
			end)
			Filter.SetChannelRate("spam", 3)
			local sink = collector("cap")
			Neon.AddSink(sink)
			for index = 1, 5 do
				Neon.Info("spam", ("m%d"):format(index))
			end
			expect(#sink.Got() == 3, "同一秒内只放行配额那么多条")
			now = 100.9
			Neon.Info("spam", "still same second")
			expect(#sink.Got() == 3, "窗口是日历秒，0.9 之后仍是同一秒")
			now = 101
			Neon.Info("spam", "next second")
			expect(#sink.Got() == 4, "换秒就恢复配额")
			local got = sink.Got()
			expect(
				got[4].fields.rateDropped == 3,
				`被限速丢掉的条数要随下一条说出来，实际 {tostring(
					got[4].fields.rateDropped
				)}`
			)
			expect(Filter.Stats().rateSuppressed == 3, "累计账目一致")
			Neon.Info("spam", "clean")
			expect(sink.Got()[5].fields.rateDropped == nil, "消费过就清零，不许重复计")
		end,
	},
	{
		name = "W4·一秒内 1000 条相同消息只输出 1 条并带次数",
		run = function()
			Neon.SetClock(function()
				return 500
			end)
			Filter.SetRepeatWindow(1)
			local sink = collector("cap")
			Neon.AddSink(sink)
			for _ = 1, 1000 do
				Neon.Info("spam", "boom")
			end
			expect(#sink.Got() == 1, `折叠后只该投递一条，实际 {#sink.Got()}`)
			expect(Filter.Stats().repeatSuppressed == 999, "折叠次数单列")
			Neon.Info("spam", "boom 2")
			local got = sink.Got()
			expect(#got == 2, "换一句才把次数随它带出去")
			expect(
				got[2].fields.repeated == 999,
				`下一条要带 repeated=999，实际 {tostring(got[2].fields.repeated)}`
			)
			expect(Filter.Stats().repeatSuppressed == 999, "次数消费掉之后不再重复计")
		end,
	},
	{
		name = "W4·折叠只认同频道 + 同级别 + 同正文，别的记录一来就把链打断",
		run = function()
			Neon.SetClock(function()
				return 700
			end)
			Filter.SetRepeatWindow(5)
			local sink = collector("cap")
			Neon.AddSink(sink)
			Neon.Info("a", "same")
			Neon.Info("b", "same")
			Neon.Warn("a", "same")
			Neon.Info("a", "other")
			Neon.Info("a", "other")
			expect(#sink.Got() == 4, "换了频道/级别/正文的都不算重复")
			expect(Filter.Stats().repeatSuppressed == 1, "只有最后一次与上一条完全相同")
		end,
	},
	{
		name = "W4·折叠优先于限速：一条不许被计两次",
		run = function()
			Neon.SetClock(function()
				return 800
			end)
			Filter.SetRepeatWindow(1)
			Filter.SetRate(1)
			local sink = collector("cap")
			Neon.AddSink(sink)
			for _ = 1, 5 do
				Neon.Info("c", "x")
			end
			local stats = Filter.Stats()
			expect(#sink.Got() == 1, "投递一条")
			expect(
				stats.repeatSuppressed == 4 and stats.rateSuppressed == 0,
				`四条都记在折叠名下，实际 repeat={stats.repeatSuppressed} rate={stats.rateSuppressed}`
			)
		end,
	},
	{
		name = "W4·Neon.Enabled 与实际投递一致，且不消费配额",
		run = function()
			Filter.SetMinimumLevel("warn")
			Filter.SetChannelRate("c", 1)
			local passes = 0
			for _ = 1, 50 do
				if Neon.Enabled("warn", "c") then
					passes += 1
				end
			end
			expect(passes == 50, "守卫的判断要发射路径一致")
			expect(Neon.Enabled("info", "c") == false, "低于门槛的一律 false")
			local sink = collector("cap")
			Neon.AddSink(sink)
			Neon.Warn("c", "one")
			expect(#sink.Got() == 1, "50 次探测没吃掉配额")
			expect(Filter.Stats().rateSuppressed == 0, "守卫不许动限速的账")
		end,
	},
	{
		name = "W4·配置校验：非法值抛错，且抛错的调用一项都不生效",
		run = function()
			local before = Filter.Options()
			expectFails(function()
				Filter.SetMinimumLevel("notice")
			end, "未登记的级别必须抛错", "未登记的级别")
			expectFails(function()
				Filter.SetRate(-1)
			end, "负数上限")
			expectFails(function()
				Filter.SetRate(2.5)
			end, "小数上限")
			expectFails(function()
				Filter.SetRate(math.huge)
			end, "+inf 不是合法上限")
			expectFails(function()
				Filter.SetRepeatWindow(0 / 0)
			end, "nan 不是合法窗口")
			expectFails(function()
				Filter.SetChannelRate("a\nb", 3)
			end, "频道名归同一份判定管", "频道名")
			expectFails(function()
				Filter.SetChannelMinimum("c", "fatal")
			end, "每频道门槛也要校验")
			local after = Filter.Options()
			expect(
				after.minLevel == before.minLevel
					and after.rate == before.rate
					and after.repeatWindow == before.repeatWindow,
				"七次抛错不能留下半套新配置"
			)
		end,
	},
	{
		name = "W4·Options 与 Stats 的快照都是冻结的",
		run = function()
			expectFails(function()
				(Filter.Options() :: any).rate = 9
			end, "配置快照必须冻结：能被随手改的快照就是第二套配置")
			expectFails(function()
				(Filter.Stats() :: any).admitted = 9
			end, "账目快照也要冻结")
		end,
	},
	{
		name = "W4·频道多过跟踪上限时退化成只走全局门槛：日志不许丢",
		run = function()
			Neon.SetClock(function()
				return 900
			end)
			Filter.SetChannelRate("first", 1) -- 让过滤器开着，且不落到全局快路径
			local sink = collector("cap")
			Neon.AddSink(sink)
			for index = 1, 260 do
				Neon.Info("ch" .. index, "x")
			end
			local stats = Filter.Stats()
			expect(
				#sink.Got() == 260,
				`一条都不该因为「频道太多」而消失，实际 {#sink.Got()}`
			)
			expect(
				stats.trackedChannels > 0 and stats.untrackedChannels > 0,
				"退化要在账目里看得见"
			)
		end,
	},
	{
		name = "W4·Filter.Reset 复位配置与账目，但不碰输出端注册表",
		run = function()
			Filter.SetMinimumLevel("error")
			Filter.SetRepeatWindow(2)
			Filter.SetRate(5)
			local sink = collector("cap")
			Neon.AddSink(sink)
			Filter.Reset()
			local options = Filter.Options()
			expect(
				options.minLevel == "trace" and options.rate == 0 and options.repeatWindow == 0,
				"三项都回默认"
			)
			expect(Sink.Count() == 1, "注册表是 Sink.Reset() 的活，Filter.Reset 不许越界")
			expect(Filter.Stats().admitted == 0, "账目归零")
			Neon.Info("c", "passes again")
			expect(#sink.Got() == 1, "复位后一切照打")
		end,
	},

	-- ---------- P2.W5：命令系统 ----------
	{
		name = "W5·注册后能跑，handler 拿到按名字绑定好的参数",
		run = function()
			local seen: { [string]: any }? = nil
			Command.Register("sethp", {
				help = "改血量",
				args = {
					{ name = "target", kind = "string" },
					{ name = "value", kind = "number" },
				},
			}, function(context: Command.Context): string?
				seen = context.args
				return `已把 {context.args.target} 设为 {tostring(context.args.value)}`
			end)
			local result = Command.Run("sethp player1 42")
			expect(result.ok == true, `应当跑通，实际 error = {tostring(result.error)}`)
			expect(result.name == "sethp", "结果里要带上跑的是哪条命令")
			local args = seen
			expect(args ~= nil and args.target == "player1", "字符串参数原样交出去")
			expect(args ~= nil and args.value == 42, 'number 参数必须真的转成了数（不是 "42"）')
			expect(
				result.output == "已把 player1 设为 42",
				`handler 的返回要当输出交出，实际 {tostring(result.output)}`
			)
			expect(Command.Stats().succeeded == 1, "成功单独记一笔")
		end,
	},
	{
		name = "W5·引号不闭合返回错误文本而不是抛错，并给出血位置",
		run = function()
			Command.Register(
				"echo",
				{ help = "回显", args = { { name = "text", kind = "string" } } },
				function(context: Command.Context): string?
					return tostring(context.args.text)
				end
			)
			local result = Command.Run([[echo "abc]])
			expect(result.ok == false, "敲错引号必须被拒，而不是把调用栈甩在人脸上")
			local text = tostring(result.error)
			expect(
				string.find(text, "引号没有闭合", 1, true) ~= nil,
				`要说是引号问题，实际 {text}`
			)
			expect(string.find(text, "第 6 字节", 1, true) ~= nil, `位置要给出来，实际 {text}`)
		end,
	},
	{
		name = "W5·缺参数与类型不符都点名到具体是哪一项",
		run = function()
			Command.Register("greet", {
				help = "打招呼",
				args = {
					{ name = "who", kind = "string" },
					{ name = "times", kind = "number", optional = true, default = 1 },
				},
			}, function(context: Command.Context): string?
				return ("hi "):rep(tonumber(context.args.times) or 1) .. tostring(context.args.who)
			end)
			local missing = Command.Run("greet")
			expect(
				missing.ok == false and string.find(tostring(missing.error), "who", 1, true) ~= nil,
				"缺的必填项要点名"
			)
			local bad = Command.Run("greet bob lots")
			expect(string.find(tostring(bad.error), "times", 1, true) ~= nil, "类型不符要点名参数")
			expect(
				string.find(tostring(bad.error), "需要一个数", 1, true) ~= nil,
				"要说清要什么类型"
			)
			local defaulted = Command.Run("greet bob")
			expect(
				defaulted.ok == true and defaulted.output == "hi bob",
				`可选项要吃默认值，实际 {tostring(defaulted.output)}`
			)
			local tooMany = Command.Run("greet bob 2 3")
			expect(
				tooMany.ok == false and string.find(tostring(tooMany.error), "参数过多", 1, true) ~= nil,
				"多出来的参数不能静默丢掉"
			)
		end,
	},
	{
		name = "W5·nan / inf 不许当数字用（tonumber 认它们，控制台不该放行）",
		run = function()
			Command.Register(
				"num",
				{ help = "收一个数", args = { { name = "v", kind = "number" } } },
				function(): string?
					return "ok"
				end
			)
			local badInputs = { "nan", "inf", "-inf", "1e999" }
			for index = 1, #badInputs do
				local result = Command.Run("num " .. badInputs[index])
				expect(result.ok == false, `{badInputs[index]} 不能当数字用，它却通过了`)
			end
			expect(Command.Run("num 1e3").ok == true, "正常的科学计数法要过")
			expect(Command.Run("num -0.5").ok == true, "负小数要过")
		end,
	},
	{
		name = "W5·引号里的空格留着，反斜杠只用来塞引号本身",
		run = function()
			Command.Register(
				"echo",
				{ help = "回显", args = { { name = "text", kind = "string" } } },
				function(context: Command.Context): string?
					return tostring(context.args.text)
				end
			)
			expect(Command.Run([[echo "a  b"]]).output == "a  b", "引号内的两个空格要留着")
			expect(
				Command.Run([[echo "say \"hi\""]]).output == 'say "hi"',
				"反斜杠要能塞进引号本身"
			)
			expect(
				Command.Run([[echo ""]]).output == "",
				"空引号是一个空字符串参数，不是少一个参数"
			)
			expect(
				Command.Run([[echo a"b c"]]).output == "ab c",
				"引号段可以和裸片段拼在同一个词里"
			)
		end,
	},
	{
		name = "W5·未知命令不抛错，还把前缀候选给出来",
		run = function()
			Command.Register("tp", "传送", function(): string?
				return nil
			end)
			local result = Command.Run("t")
			local text = tostring(result.error)
			expect(
				result.ok == false and string.find(text, "未知命令 t", 1, true) ~= nil,
				"要说清哪条没找到"
			)
			expect(
				string.find(text, "tp", 1, true) ~= nil,
				`前缀对得上的候选要顺手列出来，实际 {text}`
			)
			local empty = Command.Run("   ")
			expect(
				empty.ok == false and string.find(tostring(empty.error), "空输入", 1, true) ~= nil,
				"只有空格也算空输入，不许当成空命令名去查表"
			)
		end,
	},
	{
		name = "W5·handler 抛错被包成错误文本，其余命令照样能跑",
		run = function()
			Command.Register("ping", "探活", function(): string?
				return "pong"
			end)
			Command.Register("boom", "会抛错的命令", function(): string?
				error("内部炸了")
			end)
			local result = Command.Run("boom")
			expect(result.ok == false and result.error ~= nil, "抛错不能带走调用方")
			expect(
				string.find(tostring(result.error), "内部炸了", 1, true) ~= nil,
				"原始错误文本要留着，别只说「失败了」"
			)
			expect(Command.Run("ping").output == "pong", "一条坏命令不许把注册表带坏")
			local stats = Command.Stats()
			expect(
				stats.errored == 1 and stats.succeeded == 1,
				`三类失败要分开记账：errored={stats.errored} succeeded={stats.succeeded}`
			)
		end,
	},
	{
		name = "W5·权限钩子拒绝时 handler 一次都不许被叫到",
		run = function()
			local calls = 0
			Command.Register("wipe", "危险操作", function(): string?
				calls += 1
				return "done"
			end)
			Command.SetPermissionHook(function(caller: any, name: string): (boolean, string?)
				if caller == "console" then
					return true, nil
				end
				return false, `不能执行 {name}`
			end)
			local denied = Command.Run("wipe", "student")
			expect(
				denied.ok == false and string.find(tostring(denied.error), "未授权", 1, true) ~= nil,
				"越权要挡住"
			)
			expect(
				string.find(tostring(denied.error), "不能执行 wipe", 1, true) ~= nil,
				"钩子给的理由要原样交出去，别被咽下去"
			)
			expect(calls == 0, "被拒绝的命令不能已经跑过了")
			expect(Command.Stats().denied == 1, "越权单独记一笔")
			expect(Command.Run("wipe", "console").ok == true and calls == 1, "放行时要真的跑")
			Command.SetPermissionHook(nil)
			expect(Command.Run("wipe", "anyone").ok == true, "传 nil 复原成一律允许")
		end,
	},
	{
		name = "W5·钩子自己抛错按拒绝处理（fail closed）",
		run = function()
			local calls = 0
			Command.Register("danger", "钩子会炸的命令", function(): string?
				calls += 1
				return nil
			end)
			Command.SetPermissionHook(function(_caller: any, _name: string): (boolean, string?)
				error("钩子起不来")
				-- 到不了这里。`error` 在类型层不算返回值，所以标注了多返回值的函数仍要留一条
				-- return，否则 types 门禁会说「函数必须返回 (boolean, string?)」。
				return false, nil
			end)
			local result = Command.Run("danger")
			expect(result.ok == false, "钩子坏了必须拒绝，不能放行")
			expect(calls == 0, "「安全检查起不来就当通过」是反过来的默认值")
			expect(
				string.find(tostring(result.error), "按拒绝处理", 1, true) ~= nil,
				"错误文本要说清为什么被拒"
			)
		end,
	},
	{
		name = "W5·重复注册抛错；Remove 如实返回布尔；Reset 之后内置 help 还在",
		run = function()
			Command.Register("dup", "一", function(): string?
				return nil
			end)
			expectFails(
				function()
					Command.Register("dup", "二", function(): string?
						return nil
					end)
				end,
				"同名命令必须抛错：静默覆盖会让「两处都注册了」完全没有痕迹",
				"已注册"
			)
			expectFails(function()
				Command.Register("DUP", "三", function(): string?
					return nil
				end)
			end, "大小写撞车也算撞车", "大小写不敏感")
			expect(Command.Remove("nope") == false, "摘不掉要如实返回 false")
			expect(Command.Remove("dup") == true, "摘掉返回 true")
			expect(Command.Run("dup").ok == false, "摘掉之后就该是未知命令")
			expect(
				Command.Run("help").ok == true,
				"内置 help 是注册进去的，不是硬编码的第二份"
			)
			Command.Reset()
			expect(Command.Count() == 1, `复位后只剩内置 help，实际 {Command.Count()}`)
			expect(Command.Run("help").ok == true, "复位不能把 help 一起清掉")
		end,
	},
	{
		name = "W5·坏 spec 在注册期就挡下，不留到 Run 才发现",
		run = function()
			expectFails(function()
				Command.Register(
					"badkind",
					{ args = { { name = "v", kind = "int" :: any } } },
					function(): string?
						return nil
					end
				)
			end, "kind 只能是三种之一", "kind")
			expectFails(function()
				Command.Register("order", {
					args = {
						{ name = "a", kind = "string", optional = true },
						{ name = "b", kind = "string" },
					},
				}, function(): string?
					return nil
				end)
			end, "必填排在可选之后，按位置绑定时是无解的", "必填")
			expectFails(function()
				Command.Register("nohandler", "说明", 1 :: any)
			end, "handler 必须是函数")
			expectFails(function()
				Command.Register("na\0me", "说明", function(): string?
					return nil
				end)
			end, "命令名归同一份判定管", "命令名")
			expectFails(function()
				Command.Register("repeat", {
					args = {
						{ name = "v", kind = "string" },
						{ name = "v", kind = "number" },
					},
				}, function(): string?
					return nil
				end)
			end, "参数名不能重复", "重复")
			expectFails(function()
				Command.SetPermissionHook(1 :: any)
			end, "钩子只收函数")
			expect(Command.Count() == 1, "六次抛错不能留下半条新命令")
		end,
	},
	{
		name = "W5·补全候选与注册顺序无关，两次调用逐字节相同",
		run = function()
			Command.Register("zeta", "z", function(): string?
				return nil
			end)
			Command.Register("alpha", "a", function(): string?
				return nil
			end)
			Command.Register("mid", "m", function(): string?
				return nil
			end)
			local first = table.concat(Command.Complete(""), ",")
			expect(first == "alpha,help,mid,zeta", `候选要按字典序排，实际 {first}`)
			expect(
				table.concat(Command.Complete(""), ",") == first,
				"补全列表是给人 Tab 用的，顺序必须稳"
			)
			expect(table.concat(Command.Complete("M"), ",") == "mid", "前缀匹配大小写不敏感")
			expect(#Command.Complete("zzz") == 0, "没有候选就返回空表，不要猜一个")
		end,
	},
	{
		name = "W5·help 文本从注册表生成，并把参数形状带出来",
		run = function()
			Command.Register("alpha", {
				help = "甲命令",
				args = { { name = "n", kind = "number", optional = true, default = 1 } },
			}, function(): string?
				return nil
			end)
			local all = Command.Run("help")
			local text = tostring(all.output)
			expect(all.ok == true, "内置 help 要能跑")
			expect(
				string.find(text, "alpha", 1, true) ~= nil and string.find(text, "甲命令", 1, true) ~= nil,
				"名字与说明都要在"
			)
			expect(string.find(text, "help", 1, true) ~= nil, "help 自己也在表里")
			expect(
				string.find(text, "<1 个参数>", 1, true) ~= nil,
				`有参数的要标出形状，实际 {text}`
			)
			local detail = tostring(Command.Run("help alpha").output)
			expect(
				string.find(detail, "n: number", 1, true) ~= nil,
				`单条说明要给参数类型，实际 {detail}`
			)
			expect(
				string.find(detail, "可选", 1, true) ~= nil
					and string.find(detail, "默认 1", 1, true) ~= nil,
				"可选项与默认值都要说"
			)
			expect(
				string.find(tostring(Command.Run("help nothing").output), "未知命令", 1, true) ~= nil,
				"help 查不到也要说清楚"
			)
		end,
	},
	{
		name = "W5·Neon.Reset 不清命令注册表（复位边界要有人守着）",
		run = function()
			Command.Register("hostonly", "宿主注册一次、全程有效", function(): string?
				return "ok"
			end)
			Neon.Reset()
			expect(
				Command.Count() == 2,
				"复位日志状态不该把命令一起端走：那会让服务器上的命令凭空消失"
			)
			expect(Command.Run("hostonly").ok == true, "复位后命令仍可调用")
			expect(
				Neon.SinkNames()[1] == nil,
				"输出端确实被 Neon.Reset 清了（对照：命令是刻意不清的）"
			)
		end,
	},
	{
		name = "W5·解析器是纯函数：同一行文本两次切分结果相同",
		run = function()
			-- 跑 `Run` 也能验解析，但那会把账记进计数里；解析单独有一个入口，
			-- 「两次切分相同」这条判据才只属于解析这一件事。
			local line = [[  sethp "a  b" 42  ]]
			local first = Command.Parse(line)
			local second = Command.Parse(line)
			expect(
				table.concat(first.tokens, "|") == table.concat(second.tokens, "|"),
				"两次切分必须逐字节相同"
			)
			expect(#first.tokens == 3, `前后空白不该产生空词，实际 {#first.tokens} 个`)
			expect(
				first.tokens[1] == "sethp" and first.tokens[2] == "a  b" and first.tokens[3] == "42",
				"词的内容"
			)
			expect(first.error == nil, "这行没有错误")
			expect(Command.Parse('a " b').error ~= nil, "没闭合的引号要报错")
		end,
	},
}

--[=[ 跑全部用例，返回是否全过。CI 的 `test` 阶段按返回值定成败。]=]
function SelfTest.RunAll(): boolean
	local failures = 0
	for _, case in cases do
		Neon.Reset()
		-- 上限是模块级配置，用例改过就必须复位：否则「同一记录两次渲染相同」这类断言会读到
		-- 上一个用例留下的截断位，症状是偶发失败、单跑又都对 —— 最难查的那一类。
		Format.Reset()
		-- 命令注册表同样是模块级状态：上一例注册的命令留在这一例里，「未知命令」这类断言就失去
		-- 意义了。（`Neon.Reset()` 刻意不清它 —— 那条边界由 `W5·Neon.Reset` 这一例守着。）
		Command.Reset()
		local ok, err = protect(case.run)
		if ok then
			print(`  [Neon] PASS  {case.name}`)
		else
			failures += 1
			warn(`  [Neon] FAIL  {case.name} —— {string.sub(tostring(err), 1, 200)}`)
		end
	end
	Neon.Reset()
	print(`  [Neon] {#cases - failures}/{#cases} 例通过`)
	return failures == 0
end

return SelfTest
