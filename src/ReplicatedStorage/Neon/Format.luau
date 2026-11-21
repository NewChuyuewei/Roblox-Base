--!strict
-- Neon.Format —— 把一条记录渲染成一行文本（`.plan/PHASES.md` P2.W3）。
--
-- 三条判据各自决定了一处实现，写在这里以免日后被「顺手简化」掉：
--
--   1. **同一条记录渲染两次必须完全相同。** 所以：表按键排序（`next` 的顺序不保证）；
--      函数与 userdata 只印类型、**不印地址**（地址每次运行都不同，一进来就让这条判据
--      永远失败）；不读时钟 —— 时间取记录里的 `time`。
--   2. **自引用的表不许把打印拖进死循环。** 循环判定只看「当前这条递归路径」，所以同一个
--      表出现在两个兄弟位置不算循环（那很常见，全标 `<cycle>` 会把日志变成噪音），只有在
--      一条链上再次遇到才算。
--   3. **截断要标注被截掉的长度。** 只留省略号的话，读日志的人会以为看到的就是全文 ——
--      那是把人朝错误方向打发的省事写法。
--
-- 另外两处平台性的坑也在这里处理掉：按字节截断会切断 UTF-8 序列（中文日志必撞），
-- 所以退回字符边界；不使用 `utf8.*` / `debug.*` 这类库函数 —— 本仓库 `types` 门禁用的是
-- vendor 的窄定义，里头没声明的 API 在类型层就是错的（`math.type` 已经这样炸过一次）。
--
-- L0 约束：不碰引擎（`.plan/CARBON.md` §3.1）。

local Level = require(script.Parent.Level)
local Record = require(script.Parent.Record)

local Format = {}

-- 上限默认值。截断位必须宿主可调：W7 的游戏内控制台行宽比标准输出窄得多，
-- 没有这个接缝它只能把本模块复制一份 —— 复制出去的第二份从此不会再跟着修。
local DEFAULT_DEPTH = 2
local DEFAULT_VALUE_LENGTH = 200
local DEFAULT_MESSAGE_LENGTH = 2000
-- 整行硬上限。字段值各自有上限，但 64 个键拼起来仍能到十几 KB —— 那足以把控制台的
-- 环形缓冲挤爆（W7 能看到多少历史取决于每行多大）。正文超限就砍尾并标注。
local DEFAULT_LINE_LENGTH = 4096

local maxDepth = DEFAULT_DEPTH
local maxValueLength = DEFAULT_VALUE_LENGTH
local maxMessageLength = DEFAULT_MESSAGE_LENGTH
local maxLineLength = DEFAULT_LINE_LENGTH

local ELLIPSIS = "…"

-- 级别补齐到这个宽度，让多行日志的正文对齐。宽度不足时直接输出原文：
-- 把级别字母截掉比不对齐糟得多。
local LEVEL_WIDTH = 5

-- 单个表最多展开多少个键。日志不是导出工具：一个万键的表在这里只该露个边。
local MAX_KEYS = 64

--[=[
	渲染上限。四项都可选，缺省的保持原值。非法值抛错而不是夹紧（clamp）：
	夹紧会把「我以为是 200」变成「实际是 1」，而这种偏差只在日志被截得莫名其妙时才暴露。
]=]
function Format.SetLimits(options: {
	maxDepth: number?,
	maxValueLength: number?,
	maxMessageLength: number?,
	maxLineLength: number?,
}): ()
	assert(
		type(options) == "table",
		`[Neon.Format] SetLimits 需要一个表，收到 {Level.Describe(options)}`
	)

	local function checkInteger(value: any, name: string, lowerBound: number): number?
		if value == nil then
			return nil
		end
		assert(
			type(value) == "number"
				and math.floor(value :: number) == (value :: number)
				and value >= lowerBound,
			`[Neon.Format] {name} 必须是 ≥ {lowerBound} 的整数，收到 {Level.Describe(value)}`
		)
		return value :: number
	end

	local depth = checkInteger(options.maxDepth, "maxDepth", 1)
	-- 下限是省略号本身：留给正文字数 ≤ 0 的「截断」只会输出一个省略号，不如直接拒。
	local valueLength = checkInteger(options.maxValueLength, "maxValueLength", #ELLIPSIS + 1)
	local messageLength = checkInteger(options.maxMessageLength, "maxMessageLength", #ELLIPSIS + 1)
	local lineLength = checkInteger(options.maxLineLength, "maxLineLength", #ELLIPSIS + 1)

	-- 三项先全部校验完再赋值：中途抛错不能留下「一半新一半旧」的配置。
	if depth ~= nil then
		maxDepth = depth
	end
	if valueLength ~= nil then
		maxValueLength = valueLength
	end
	if messageLength ~= nil then
		maxMessageLength = messageLength
	end
	if lineLength ~= nil then
		maxLineLength = lineLength
	end
end

--[=[ 把四项上限恢复到默认值。测试用例改过它们就必须复原 —— 否则「同一记录两次渲染相同」
这类断言会在下一个用例里读到上一个用例留下的截断位，症状是偶发失败、单跑又都对。]=]
function Format.Reset(): ()
	maxDepth = DEFAULT_DEPTH
	maxValueLength = DEFAULT_VALUE_LENGTH
	maxMessageLength = DEFAULT_MESSAGE_LENGTH
	maxLineLength = DEFAULT_LINE_LENGTH
end

--[=[ 当前上限的快照，**冻结**。改它不影响模块配置（模块的真相只有那几个 local），
而想改的人会当场收到「frozen table」的错误 —— 比「写了没人发现没生效」好得多。]=]
function Format.Limits(): {
	maxDepth: number,
	maxValueLength: number,
	maxMessageLength: number,
	maxLineLength: number,
}
	return table.freeze({
		maxDepth = maxDepth,
		maxValueLength = maxValueLength,
		maxMessageLength = maxMessageLength,
		maxLineLength = maxLineLength,
	})
end

-- UTF-8 首字节 → 该字符的总长度。非法/后续字节按 1 处理（那种输入本来就不是合法 UTF-8，
-- 这里的目标是「不越界、不切半」，不是替调用方修数据）。
local function sequenceWidth(lead: number): number
	if lead >= 0xF0 then
		return 4
	elseif lead >= 0xE0 then
		return 3
	elseif lead >= 0xC0 then
		return 2
	end
	return 1
end

--[=[
	在 `limit` 字节以内、且不切断 UTF-8 序列的前提下，返回可保留的字节数。

	第一版只写「若 `limit` 处是后续字节（0x80–0xBF）就往前退到起始字节」——那不够：
	退到起始字节后，**那个字符本身可能还没结束**（`中文` 截在第 1 字节就剩一个 `0xE4`，
	下游拿到的是半个字）。所以判据要反过来：先看这个字符按首字节算需要几个字节，
	装得下就留到 `limit`，装不下就整字符退掉。
]=]
local function utfSafeEnd(text: string, limit: number): number
	if limit <= 0 then
		return 0
	end
	if #text <= limit then
		return #text
	end
	local last = limit
	-- 往回找到本字符的起始字节（最多退 3 步：一个序列最长 4 字节）
	local back = 0
	while last >= 1 and back < 3 do
		local byte = string.byte(text, last)
		if byte == nil then
			return last
		end
		if byte < 0x80 then
			return last -- ASCII 边界，干净
		end
		if byte >= 0xC0 then
			-- 落在起始字节上：还要看整个字符是否装得进 limit
			if last + sequenceWidth(byte) - 1 > limit then
				return last - 1
			end
			return limit
		end
		last -= 1
		back += 1
	end
	return last
end

--[=[
	截断并标注。返回「渲染文本」与「被丢掉的字节数」；`limit` 已经包含省略号自身，
	否则「截到 200」实际会给出 203 个字节（`…` 在 UTF-8 里占 3 字节）。
]=]
local function truncate(text: string, limit: number): (string, number)
	if limit <= 0 or #text <= limit then
		return text, 0
	end
	local keep = utfSafeEnd(text, limit - #ELLIPSIS)
	local dropped = #text - keep
	if keep <= 0 then
		return ELLIPSIS, dropped
	end
	return string.sub(text, 1, keep) .. ELLIPSIS, dropped
end

-- 「单行文本」这条判据的守门人：换行与制表符转成可见转义。
-- 不折叠的后果很实际 —— 控制台列表错位，CI 里按行 grep 日志的规则会漏掉半条记录。
-- 先做一次 plain find：绝大多数日志没有换行，不该每次都付一次 gsub 的构造成本。
local function toSingleLine(text: string): string
	if
		string.find(text, "\n", 1, true) == nil
		and string.find(text, "\r", 1, true) == nil
		and string.find(text, "\t", 1, true) == nil
	then
		return text
	end
	-- 外层括号是必要的：`gsub` 返回 (string, number)，而本函数签名只交出一个 string。
	return (
		string.gsub(text, "[\r\n\t]", function(char: string): string
			if char == "\n" then
				return "\\n"
			elseif char == "\r" then
				return "\\r"
			end
			return "\\t"
		end)
	)
end

-- 键序：先按类型分组，数字组内走数值序，其余走 tostring 的字典序。
-- 为什么要分组：嵌套表里数字键与字符串键混着放是合法 Luau，直接 `table.sort` 会撞上
-- 「无效的比较顺序」而抛错 —— 打印日志这一层绝不能把宿主炸了。
local function keyRank(key: any): number
	local kind = typeof(key)
	if kind == "number" then
		return 1
	elseif kind == "string" then
		return 2
	end
	return 3
end

local function sortsBefore(a: any, b: any): boolean
	local rankA = keyRank(a)
	local rankB = keyRank(b)
	if rankA ~= rankB then
		return rankA < rankB
	end
	if rankA == 1 then
		return (a :: number) < (b :: number)
	end
	return tostring(a) < tostring(b)
end

-- 递归路径上的表。用数组线性查而不是 `{ [table]: boolean }` 集合：本模块的深度上限
-- 是个位数，线性查更便宜，也躲开「用 any 当索引类型」这种在类型层就不成立的写法。
local function onPath(path: { any }, size: number, value: any): boolean
	for index = 1, size do
		if path[index] == value then
			return true
		end
	end
	return false
end

-- 折叠视图里的「元素数」。为什么不写 `#value`：`{a=1,b=2}` 的 `#` 是 0（它没有数组部分），
-- 于是日志里出现 `<table:0>`，而下面其实压着 2 个键 —— 那个数正是摘要唯一要传达的信息。
-- 数到 MAX_KEYS 就停：一个万键表不该为了折叠视图付整表遍历的钱，`64+` 已经说明问题。
local function countFields(value: any): string
	local dict = value :: { [string]: any }
	local count = 0
	for _ in dict do
		count += 1
		if count >= MAX_KEYS then
			return tostring(MAX_KEYS) .. "+"
		end
	end
	return tostring(count)
end

local function renderValue(value: any, depth: number, path: { any }, pathSize: number): string
	local kind = typeof(value)
	if kind == "string" then
		-- 收尾引号必须齐：少一个的话 `name = "loop"` 会印成 `name="loop`，读日志的人
		-- 分不清是被截断了还是引号本来就在（W3 自检第一轮就是这么把它抓出来的）。
		return `"{truncate(toSingleLine(value :: string), maxValueLength)}"`
	elseif kind == "number" or kind == "boolean" then
		-- 数字交给 Luau 的 tostring：精度固定，跨机器一致
		return tostring(value)
	elseif kind == "table" then
		if onPath(path, pathSize, value) then
			return "<cycle>"
		end
		if depth >= maxDepth then
			-- 带上元素数：看到 `<table:9>` 至少知道下面还有多少东西没印
			return `<table:{countFields(value)}>`
		end
		local dict = value :: { [string]: any }
		local keys: { any } = {}
		local seen = 0
		for key in dict do
			seen += 1
			table.insert(keys, key)
			if seen >= MAX_KEYS then
				break
			end
		end
		table.sort(keys, sortsBefore)
		path[pathSize + 1] = value
		local parts: { string } = table.create(#keys)
		for index = 1, #keys do
			local key = keys[index]
			table.insert(
				parts,
				`{tostring(key)}={renderValue(dict[key :: string], depth + 1, path, pathSize + 1)}`
			)
		end
		path[pathSize + 1] = nil
		if #parts == 0 then
			return "{}"
		end
		local tail = if seen > #keys then ",…" else ""
		return "{" .. table.concat(parts, ", ") .. tail .. "}"
	end
	-- function / userdata / thread / vector / 其余：只报类型，不报地址（见文件头第 1 条）
	return `<{kind}>`
end

--[=[ 安全打印任意值：深度上限 + 循环标记 + 键排序 + 截断。]=]
function Format.Value(value: any): string
	return renderValue(value, 0, {}, 0)
end

--[=[
	时间戳 → `HH:MM:SS`（UTC）。

	两个刻意的选择：

	* **用 UTC，且自己做算术。** 同一条记录在两台机器上必须印出同一段文本，否则任何跨机器
	  的回归比对都是假红。而 `os.date` 在这个构建的类型定义里只声明了 `"*t"` / `"!*t"` 两种
	  形式，传 `"%H:%M:%S"` 直接是 TypeError（types 门禁实测）——就算绕过类型，它也要过一层
	  宿主实现，而打印是全工程最高频的入口。Unix 秒本身与时区无关，时分秒除 3600、取余就
	  出来了：确定性更严、成本更低，两头都赚。
	* **坏时间戳不抛错。** 丢日志比丢时间格式严重得多，这里降级成 `<time?>`，其余字段照打。
	  Lua 的 `%` 是 floor 语义，1970 之前的负数也稳稳落在 0..86399。
]=]
function Format.Time(time: number): string
	if type(time) ~= "number" or time ~= time or time == math.huge or time == -math.huge then
		return "<time?>"
	end
	local secondsOfDay = math.floor(time) % 86400
	local hour = math.floor(secondsOfDay / 3600)
	local minute = math.floor(secondsOfDay / 60) % 60
	return string.format("%02d:%02d:%02d", hour, minute, secondsOfDay % 60)
end

--[=[
	一条记录 → 一行文本：`[03:22:01] INFO  combat: hit {hp=1, world="w1"}`。

	频道排在正文之前：它是日志的第一索引，控制台里按频道筛就是筛这一段。
	没有字段时不打空 `{}` —— 绝大多数行除了正文什么都没有，摆一串花括号纯是噪音。

	本函数对**裸记录**（没走 `Record.New` 的表）也要出活：缺哪栏就省哪栏，不印 "nil"，
	也不抛错。打印这一层抛错的代价是这条日志彻底消失，比缺一栏信息糟得多；真正必须抛的
	只有一件 —— 传进来的根本不是记录。
]=]
function Format.Line(record: Record.Record): string
	assert(type(record) == "table", `[Neon.Format] Line 需要一条记录，收到 {Level.Describe(record)}`)

	local level = tostring(record.level)
	if #level < LEVEL_WIDTH then
		level = level .. string.rep(" ", LEVEL_WIDTH - #level)
	end

	-- 时间戳坏了（nan / inf / 越界）→ `<time?>`，正文照打；见 Format.Time。
	local head = string.format("[%s] %s", Format.Time(record.time), string.upper(level))
	local rawChannel: any = record.channel
	if type(rawChannel) == "string" and rawChannel ~= "" then
		-- 频道再过一遍 toSingleLine 只为裸记录：`Record.New` 已经挡过换行，那条路径上这里
		-- 只会命中 plain find 短路，不付 gsub 的构造成本。
		head = head .. " " .. toSingleLine(rawChannel :: string) .. ": "
	else
		head = head .. " "
	end

	local rawMessage: any = record.message
	local messageText = if rawMessage == nil then "" else tostring(rawMessage)
	local message, dropped = truncate(toSingleLine(messageText), maxMessageLength)
	local line = head .. message
	-- `(+N)` 紧跟被截的正文，不放整行末尾：放到末尾会让人以为少掉的是行尾的字段，
	-- 而实际少掉的是正文 —— 标错位置的截断标记比没标记更容易把人带偏。
	if dropped > 0 then
		line = line .. `(+{dropped})`
	end

	local fields = record.fields
	if fields ~= nil and next(fields) ~= nil then
		-- 字段从 maxDepth - 1 起步：记录本身算一层，嵌套还能再展开一层
		line = line .. " " .. renderValue(fields, maxDepth - 1, {}, 0)
	end

	-- 省略号与 `(+N)` 都在上限之外：上限管的是正文，标记是附加说明。为了把「截掉多少」
	-- 说清楚，允许整行比上限多几个字节 —— 这比「凑整数上限而丢掉长度信息」诚实。
	local clipped, lineDropped = truncate(line, maxLineLength)
	if lineDropped > 0 then
		return clipped .. `(+{lineDropped})`
	end
	return clipped
end

return Format
