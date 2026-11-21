--!strict
-- Neon.Sink —— 输出端契约与注册表（`.plan/PHASES.md` P2.W2）。
--
-- 契约只有两个字段：`name` 与 `Write`。为什么不再多给（比如 `Flush`、`Close`、
-- `SetLevel`）：`Sink` 是 Core 与输出端之间唯一的接缝，每多一个必选方法，第三方写的
-- 输出端就多一处会漏实现的地方。级别过滤属于 W4 的过滤器，不属于输出端 —— 让 sink
-- 自己决定收不收，结果是「三个 sink 三套级别语义」。
--
-- 投递语义（W2 判据直接依赖，别在别处另立一套）：
--   · 顺序 = 注册顺序，逐个投递；
--   · 一个输出端抛错不影响其余输出端（错误隔离），错误本身被计数并随返回值交回调用方；
--   · 记录不复制：所有输出端拿到同一个（已冻结的）引用。
--
-- L0 约束：不碰引擎；`Host/` 里才允许 `print` / `warn`（`.plan/CARBON.md` §3.2，规则 H1–H2）。

local Level = require(script.Parent.Level)
local Record = require(script.Parent.Record)

local Sink = {}

export type Sink = {
	name: string,
	Write: (Record.Record) -> (),
}

-- 注册表是活引用（`Sink.Snapshot()` 交出去的就是它），这样测试能断言
-- 「清的是同一张表」而不是「内容碰巧一样」——命名沿用 `Deuterium` 已定的约定（H2）。
local registry: { Sink } = {}

local deliveredTotal = 0
local failedTotal = 0

-- 冻结的「什么都没有」：可以被多个调用方同时持有，改动它会当场抛错，
-- 而不是把一份结果改坏之后影响下一个读到它的人。
local EMPTY_ERRORS: { string } = table.freeze({}) :: { string }
local EMPTY_RESULT = table.freeze({ delivered = 0, failed = 0, errors = EMPTY_ERRORS })

--[=[	构造一个输出端。`name` 参与重复注册检查与错误信息，所以不许为空、不许带换行。]=]
function Sink.New(name: string, write: (Record.Record) -> ()): Sink
	assert(
		Record.IsOneLine(name),
		`[Neon.Sink] name 必须是不含换行的非空字符串，收到 {Level.Describe(name)}`
	)
	assert(
		type(write) == "function",
		`[Neon.Sink] {name} 的 Write 必须是函数，收到 {Level.Describe(write)}`
	)
	return { name = name, Write = write }
end

--[=[
	注册。重复注册同一个实例或同名输出端**直接抛错**，不静默去重：
	「每条日志打两遍」的根因几乎总是某处又挂了一次，静默去重会把这条线索抹掉。
]=]
function Sink.Add(sink: Sink): ()
	assert(
		type(sink) == "table",
		`[Neon.Sink] Add 需要一个 Sink，收到 {Level.Describe(sink)}（裸函数请先 Sink.New(name, fn)）`
	)
	assert(type(sink.Write) == "function", `[Neon.Sink] 输出端缺 Write：{Level.Describe(sink.name)}`)
	for index = 1, #registry do
		local existing = registry[index]
		assert(
			existing ~= sink,
			`[Neon.Sink] 同一个输出端被重复注册：{existing.name}（第 {index} 位）`
		)
		assert(
			existing.name ~= sink.name,
			`[Neon.Sink] 输出端名字撞了：{sink.name} 已被第 {index} 位占用；换名或先 Remove`
		)
	end
	table.insert(registry, sink)
end

--[=[
	注销。传输出端本身或它的 `name`。返回是否真的摘掉了一个 ——
	返回 false 通常说明它是在别处注册的，那是接线问题，不是这里的问题。
]=]
function Sink.Remove(target: Sink | string): boolean
	local index: number? = nil
	for candidate = 1, #registry do
		local sink = registry[candidate]
		if type(target) == "string" then
			if sink.name == (target :: string) then
				index = candidate
				break
			end
		elseif sink == (target :: Sink) then
			index = candidate
			break
		end
	end
	if index == nil then
		return false
	end
	table.remove(registry, index :: number)
	return true
end

--[=[ 当前注册数。]=]
function Sink.Count(): number
	return #registry
end

--[=[
	注册表本身（活引用，顺序 = 注册顺序）。只用于读与断言；
	直接 `table.insert` 它会绕过重复注册检查。
]=]
function Sink.Snapshot(): { Sink }
	return registry
end

--[=[ 已注册输出端的名字，按注册顺序。]=]
function Sink.Names(): { string }
	local out: { string } = {}
	for index = 1, #registry do
		table.insert(out, registry[index].name)
	end
	return out
end

--[=[
	投递一条记录。返回本次的投递情况：
	`{ delivered, failed, errors }`，`errors[i]` 是「输出端名: 错误信息」。

	错误隔离用 `pcall`：日志系统最不该做的事就是因为某个输出端坏了而让业务代码跟着炸，
	或者更糟 —— 把整条记录丢掉。所以抛错的 sink 只损失它自己那一份。
]=]
function Sink.Broadcast(record: Record.Record): { delivered: number, failed: number, errors: { string } }
	local count = #registry
	if count == 0 then
		-- 「一个输出端都没注册」是启动早期与测试里的常态（W1 的判据正是它）。这里返回共享的
		-- 冻结空结果，而不是每条日志新建两个表 —— 打印入口是全工程最高频的调用点，
		-- 每次打印都分配一个结果表等于让所有组件替它付钱。
		return EMPTY_RESULT
	end
	local delivered = 0
	local failed = 0
	-- errors 只在真的出错时才分配：happy path 上一个表都不用。ownErrors 这个旗标
	-- 不是多余的 —— 把 errors 声明成 `{ string }?` 再靠 `~= nil` 判别，类型系统不会在
	-- 赋值后把 `bucket` 收窄回非空表，`table.insert` 就报 Expected {string} but {string}?
	-- （types 门禁实测）。非空类型 + 独立旗标两边都干净。
	local errors: { string } = EMPTY_ERRORS
	local ownErrors = false
	-- 先取长度再逐个索引：广播途中有新注册的不参与本轮（否则「谁会被叫到」
	-- 取决于 sink 内部有没有副作用，这种不确定性在测试里根本复现不出来）。
	for index = 1, count do
		local sink = registry[index]
		if sink ~= nil then
			-- 闭包显式 `return nil`：直接 pcall(sink.Write, record) 的话，类型系统按
			-- 「Write 不返回值」把 pcall 的结果收窄成只有一个 boolean，多接一个 err
			-- 就是类型错误 —— 而错误文本恰恰是这道隔离层唯一有用的输出。
			local ok, err = pcall(function(): any
				sink.Write(record)
				return nil
			end)
			if ok then
				delivered += 1
			else
				failed += 1
				if not ownErrors then
					ownErrors = true
					errors = {}
				end
				table.insert(errors, `{sink.name}: {tostring(err)}`)
			end
		end
	end
	deliveredTotal += delivered
	failedTotal += failed
	return { delivered = delivered, failed = failed, errors = errors }
end

--[=[
	累计投递统计（自上次 `Reset` 起）。给 `Neon.Stats()` 用，也是 W2 判据里
	「一个抛错、其余仍收到」那条断言的落点。
]=]
function Sink.Stats(): { delivered: number, failed: number }
	return { delivered = deliveredTotal, failed = failedTotal }
end

--[=[ 清空注册表与计数（测试夹具用的全量清场；命名按 H3：一律叫 `Reset`，不叫 `Clear`）。]=]
function Sink.Reset(): ()
	-- 就地清空，不重建表：`Sink.Snapshot()` 的持有者（测试里的活引用断言）不能因为
	-- 一次 Reset 就指向一张空的新表 —— 那会让所有引用比较静默失效。
	for index = #registry, 1, -1 do
		registry[index] = nil
	end
	deliveredTotal = 0
	failedTotal = 0
end

return Sink
