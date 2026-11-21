--!strict
-- Neon.RingSink —— 内存环形缓冲输出端（`.plan/PHASES.md` P2.W2）。
--
-- 用途有两个：Studio 控制台（W7）读历史，以及测试断言「这条日志确实打出来了」。
-- 后者是它现在就必须存在的原因 —— 没有它，Core 的判据只能靠读 stdout，而那是
-- 整个 CI 里最难断言、最容易假绿的地方。
--
-- 语义（W2 判据逐条对应，别在别处另立一套）：
--   · 容量固定，写满后覆盖最旧的一条；
--   · `Records()` 按**由旧到新**返回；
--   · 只存引用，不复制记录（记录本身已冻结，见 `Neon/Record.luau`）；
--   · 容量 0 = 不存任何记录，但仍然计数（用于「只想要计数」的场景，也让负例能写）。
--
-- L0 约束：不碰引擎（`.plan/CARBON.md` §3.1）。

local Level = require(script.Parent.Level)
local Record = require(script.Parent.Record)
local Sink = require(script.Parent.Sink)

local RingSink = {}

export type Ring = Sink.Sink & {
	Records: () -> { Record.Record },
	Count: () -> number,
	Capacity: () -> number,
	Written: () -> number,
	Dropped: () -> number,
	Reset: () -> number,
}

-- 无名构造时的自动编号。名字参与 `Sink.Add` 的撞名检查，所以不能全叫 "ring"。
-- 从 1 起（0 读起来像「还没分配」，而它其实是合法下标）。
local serial = 1

--[=[
	造一个容量为 `capacity` 的环形缓冲。

	`capacity` 必须是**非负整数**：`3.5` 这类值在这里不是可以四舍五入的小事 ——
	它意味着调用方对「容量」的理解和这里不一致，猜一下就把这个分歧留到运行时了。
]=]
function RingSink.New(capacity: number, name: string?): Ring
	assert(
		type(capacity) == "number" and math.type(capacity) == "integer" and capacity >= 0,
		`[Neon.RingSink] capacity 必须是非负整数，收到 {Level.Describe(capacity)}`
	)

	local ringName = name
	if ringName == nil then
		ringName = `ring#{serial}`
		serial += 1
	end

	local buffer: { [number]: Record.Record } = {}
	local capacityValue = capacity :: number
	local count = 0 -- 当前存了多少条（<= capacity）
	local cursor = 0 -- 最新一条所在下标（1 基）
	local written = 0 -- 收过多少条（含被覆盖掉的）

	local self: Ring = {
		name = ringName :: string,
		Write = function(_record: Record.Record)
			-- 这里不校验记录来源：`Sink.Write` 的契约就是「收到一条 Core 构造的记录」。
			-- 就地校验会让手工喂记录给缓冲的测试必须模仿构造器 —— 那是把实现细节
			-- 焊进契约。要校验的是「它是不是个东西」，一行足够。
			assert(
				type(_record) == "table",
				`[Neon.RingSink] {ringName :: string} 收到不是记录的值：{Level.Describe(_record)}`
			)
			written += 1
			if capacityValue == 0 then
				return
			end
			cursor += 1
			if cursor > capacityValue then
				cursor = 1
			end
			buffer[cursor] = _record
			if count < capacityValue then
				count += 1
			end
			-- count 已达上限时，被覆盖那条就是 Dropped 的那一条。
		end,
		Count = function(): number
			return count
		end,
		Capacity = function(): number
			return capacityValue
		end,
		Written = function(): number
			return written
		end,
		Dropped = function(): number
			return written - count
		end,
		Records = function(): { Record.Record }
			local out: { Record.Record } = table.create(count)
			for offset = 1, count do
				local index: number
				if count < capacityValue then
					-- 还没写满：条目就按 1..count 排，最旧在 1。
					index = offset
				else
					-- 写满了：`cursor` 是最新一条，最旧在它的下一格。
					index = ((cursor + offset - 1) % capacityValue) + 1
				end
				local record = buffer[index]
				if record ~= nil then
					table.insert(out, record)
				end
			end
			return out
		end,
		Reset = function(): number
			local cleared = count
			for index in pairs(buffer) do
				buffer[index] = nil
			end
			count = 0
			cursor = 0
			return cleared
		end,
	}

	return self
end

return RingSink
