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
}

--[=[ 跑全部用例，返回是否全过。CI 的 `test` 阶段按返回值定成败。]=]
function SelfTest.RunAll(): boolean
	local failures = 0
	for _, case in cases do
		Neon.Reset()
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
