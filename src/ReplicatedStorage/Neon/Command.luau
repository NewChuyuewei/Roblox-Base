--!strict
-- Neon.Command —— 控制台命令：注册、参数解析、执行、补全、权限钩子（`.plan/PHASES.md` P2.W5）。
--
-- 为什么住在 L0 且零引擎依赖：命令表本身是纯数据 + 纯函数，「谁在敲」由宿主传进来。
-- 一旦这里 require 了 `Players`/`Player`，整套命令注册就只能跑在服务器上，而 W6/W7 的
-- 宿主接线要做的是**换一套权限实现**，不是重写解析器。
--
-- 三条形状上的决定，各挡一类事故：
--
--   1. **`Run` 绝不抛错**（W5 的判据）。畸形输入、未知命令、越权、handler 自己炸 —— 全部
--      以 `{ ok = false, error = ... }` 交回。理由：控制台是人现场改东西的地方，一条打错的
--      命令把调用栈甩在他脸上，他就再也看不清自己敲了什么。这条纪律和 `Sink.Broadcast`
--      包住每个输出端是同一条。
--   2. **注册期校验，不留到 Run**。`kind` 写错、必填出现在可选之后、`handler` 不是函数、
--      命令名撞了 —— 这些都在 `Register` 当场抛。留到运行期的话，症状是「那条命令偶尔不行」，
--      而没人会去怀疑注册。与 `Sink.Add` 的重复注册检查同一个理由。
--   3. **补全与 help 的输出按键排序**。`next` 不保证顺序，「候选列表稳定」这条判据没有排序就
--      测不住（`Format` 的键排序是同一条纪律）。
--   4. **错误文本按尾巴截断**（见 `errorText`）：`error()` 带路径前缀，按头截会把原因整个截掉。
--   5. **`ArgSpec.kind` 收 `string`、由注册期校验挡**（见 `ArgSpec`）：union 在这里的收益是零，
--      成本是每一个注册点都要抄 cast。
--
-- 权限钩子的失败模式是**拒绝**（fail closed）：钩子自己抛错时如果按「允许」处理，就等于把
-- 安全检查的默认值设成了开门 —— 那种默认值只在出事那天才被发现。
--
-- L0 约束：不碰引擎（`.plan/CARBON.md` §3.1）。

local Level = require(script.Parent.Level)
local Record = require(script.Parent.Record)

local Command = {}

--[=[ 允许的三种 `kind`。`ArgSpec.kind` 的类型是 `string` 而不是这个 union，理由见下面。]=]
export type ArgKind = "string" | "number" | "boolean"

--[=[ 一个参数的声明。]=]
export type ArgSpec = {
	name: string,
	-- 类型上收 `string`、合法性由注册期的 `KINDS` 挡，而不是写三字面量的 union：字符串字面量
	-- 嵌在表字面量里会被摊平成 `string`，于是**每一个**注册点都要补一遍 cast（CI 实测：15 例
	-- 自检里 8 例同一条报错，报错点还落在整张表上）。取舍与 `Record.New(level: any)` 相同 ——
	-- 「编译期能挡、但代价是全部调用点都要抄 cast」的地方，本仓选择运行期挡 + 一条准确错误。
	kind: string,
	optional: boolean?,
	-- 默认值只允许标量（含省略）。理由有两个：一是它要抄进 `help` 文本给人看，
	-- 塞一个表进去就等于让「help 说的」与「跑出来的」由两套代码决定；二是类型上写 `any`
	-- 的话，这一项到底可不可省略就说不清（类型门禁对 `any` 的缺省判定不是你想的那样）。
	default: nil | string | number | boolean,
}

--[=[ 执行时交给 handler 的上下文。`args` 的键是 `ArgSpec.name`。]=]
export type Context = {
	name: string,
	caller: any,
	args: { [string]: any },
	line: string,
}

--[=[ handler 返回一段文本给调用方显示，返回 `nil` 表示没有输出。]=]
export type Handler = (Context) -> string?

--[=[ 权限钩子：返回「可不可以」与「不行的话为什么」。]=]
export type PermissionHook = (any, string) -> (boolean, string?)

export type Result = {
	ok: boolean,
	name: string?,
	output: string?,
	error: string?,
}

type Entry = {
	name: string, -- 注册时给的原样名字（给人看的）
	help: string?,
	args: { ArgSpec }?,
	handler: Handler,
}

-- 命令名的查找键：一律小写。这与级别名的约定一致（`Level.Normalize` 也不区分大小写），
-- 所以 `TP 5` 与 `tp 5` 是同一条命令；而 `Add` 与 `add` 撞车会在注册时当场抛错，
-- 不会变成「有一条从此没人能调用」。
local function lookupKey(name: string): string
	return string.lower(name)
end

local registry: { [string]: Entry } = {}
local registeredCount = 0
local permissionHook: PermissionHook? = nil

local runTotal = 0
local succeededTotal = 0
local rejectedTotal = 0 -- 解析或绑定阶段就被挡下（没有进 handler）
local deniedTotal = 0 -- 权限钩子拒绝
local erroredTotal = 0 -- handler 自己抛错

-- 三种 kind 的集合。用「集合 + 排序数组」两份而不是抄两份表：`argKindNames` 给报错信息
-- 与 help 用，顺序必须稳定，所以单独列出来。
local KINDS: { [string]: boolean } = { string = true, number = true, boolean = true }
local KIND_ORDER: { string } = { "string", "number", "boolean" }

local function clip(text: string, limit: number): string
	if #text <= limit then
		return text
	end
	return string.sub(text, 1, limit) .. "…"
end

-- 单次错误文本的上限（字节）。给得比 `Level.Describe` 宽，是因为错误信息里「路径 + 原因」是
-- 常态，四十来字节只够装下路径。
local ERROR_TEXT_LIMIT = 240

--[=[
	handler 与权限钩子抛出的东西要变成**一行**文本。两个讲究：
	
	* 截断要**留尾巴**。Luau 的 `error("...")` 会在返回值前面加 `路径:行号: `，按头截断（那正是
	  `Level.Describe` 的做法）截出来的全是路径，原因恰好被切掉 —— 判据「错误要能说明为什么」
	  会静默失效。W5 的自检第一次跑 CI 就是这样挂的，所以这里刻意反着截。
	* 控制字符整类换成空格。错误文本要进控制台那一行，也就必须过 `Record.IsOneLine` 的判据；
	  第三方 handler 里 `error(\`多行模板\`)` 是常见写法。
]=]
local function errorText(value: any): string
	local text = (string.gsub(tostring(value), "%c", " "))
	if #text <= ERROR_TEXT_LIMIT then
		return text
	end
	local tail = string.sub(text, -(ERROR_TEXT_LIMIT - 3))
	-- 掐掉可能被切坏的开头半个汉字：UTF-8 续接字节（\x80-\xBF）不成对出现就是坏码，
	-- 宁可少一个字符，也不能交出一段非法 UTF-8 出去。
	tail = (string.gsub(tail, "^[\x80-\xBF]+", ""))
	return "…" .. tail
end

--[=[
	把一行文本切成词。规则只有一条额外的：引号段可以和裸片段拼在同一个词里
	（`a"b c"` → `ab c`），因为现场调参时最常写的是 `--name="some value"` 这种连体形式。
	反斜杠只在引号内生效，用于塞一个引号本身。

	返回 `tokens` 与 `error`。**不抛错**：这一层的失败都是「人敲错了」，不是程序 bug。
]=]
local function tokenize(line: string): ({ string }, string?)
	local tokens: { string } = {}
	local parts: { string } = {}
	local hasParts = false
	local quote: number? = nil
	local quoteAt = 0
	local index = 1
	local length = #line

	local function pushText(text: string): ()
		if text ~= "" then
			parts[#parts + 1] = text
		end
	end

	local function flushWord(): ()
		if hasParts then
			tokens[#tokens + 1] = table.concat(parts)
			parts = {}
			hasParts = false
		end
	end

	while index <= length do
		local byte = string.byte(line, index) :: number
		if quote ~= nil then
			if byte == 92 then
				-- 反斜杠：把下一个字节原样收进来
				if index + 1 > length then
					return tokens, `第 {index} 字节处的反斜杠后面没有字符了`
				end
				pushText(string.sub(line, index + 1, index + 1))
				index += 2
			elseif byte == quote then
				quote = nil
				index += 1
			else
				pushText(string.sub(line, index, index))
				index += 1
			end
		elseif byte == 32 or byte == 9 then
			flushWord()
			index += 1
		elseif byte == 34 or byte == 39 then
			quote = byte
			quoteAt = index
			-- 空引号也是一个词：`""` 是「空字符串参数」，不是「少了一个参数」
			hasParts = true
			index += 1
		else
			pushText(string.sub(line, index, index))
			hasParts = true
			index += 1
		end
	end

	if quote ~= nil then
		return tokens, `引号没有闭合：从第 {quoteAt} 字节开始`
	end
	flushWord()
	return tokens, nil
end

export type Parsed = {
	tokens: { string },
	error: string?,
}

--[=[
	把一行文本切成词（不查注册表、不执行）。暴露出来有两个理由：

	* 判据「畸形输入返回错误信息而不抛错」属于**解析**这一层。纯函数才写得出手算的期望值，
	  也才不会因为顺手跑了一条命令就把 `Stats()` 的账改脏。
	* W7 的控制台要在回车之前先知道「这行还值不值得执行」（边打字边给参数提示用的就是它）。
]=]
function Command.Parse(line: string): Parsed
	if type(line) ~= "string" then
		return {
			tokens = {},
			error = `[Neon.Command] Parse 需要一行文本，收到 {Level.Describe(line)}`,
		}
	end
	local tokens, parseError = tokenize(line :: string)
	return { tokens = tokens, error = parseError }
end

local function coerceValue(raw: string, arg: ArgSpec): (any, string?)
	if arg.kind == "number" then
		local number = tonumber(raw)
		if number == nil then
			return nil, `参数 {arg.name} 需要一个数，收到 "{clip(raw, 24)}"`
		end
		-- 拒绝 `nan` / `±inf`：`tonumber("nan")` 是合法的，而让一个 nan 流进 handler 之后，
		-- 症状会是「设置项变成了 nan 且再也改不回来」—— 那是几小时起步的排查。
		if number ~= number or number == math.huge or number == -math.huge then
			return nil, `参数 {arg.name} 必须是有限数，收到 {raw}`
		end
		return number, nil
	elseif arg.kind == "boolean" then
		local lowered = string.lower(raw)
		if lowered == "true" or lowered == "yes" or lowered == "1" or lowered == "on" then
			return true, nil
		elseif lowered == "false" or lowered == "no" or lowered == "0" or lowered == "off" then
			return false, nil
		end
		return nil,
			`参数 {arg.name} 需要布尔值（true/false/yes/no/on/off/1/0），收到 "{clip(raw, 24)}"`
	end
	return raw, nil
end

-- 注册期的 spec 校验。返回「可读的错误文本」而不是抛错，是为了让 `Register` 自己决定：
-- 注册是程序行为，抛错是对的；但文本要一次就说清是哪一项、为什么。
local function describeArgs(args: { ArgSpec }?): ({ ArgSpec }?, string?)
	if args == nil then
		return nil, nil
	end
	if type(args) ~= "table" then
		return nil, "args 必须是一个表"
	end
	local names: { [string]: boolean } = {}
	local sawOptional = false
	for index = 1, #args do
		local arg = args[index]
		if type(arg) ~= "table" then
			return nil, `第 {index} 个参数声明不是表`
		end
		if not Record.IsOneLine(arg.name) then
			return nil,
				`第 {index} 个参数的名字必须是不含控制字符的非空字符串，收到 {Level.Describe(
					arg.name
				)}`
		end
		if names[arg.name] == true then
			return nil, `参数名重复：{arg.name}`
		end
		names[arg.name] = true
		if arg.kind == nil or KINDS[arg.kind] == nil then
			return nil,
				`参数 {arg.name} 的 kind 不合法：{Level.Describe(arg.kind)}（可用：{table.concat(
					KIND_ORDER,
					" "
				)}`
		end
		if arg.optional == true then
			sawOptional = true
		elseif sawOptional then
			-- 「必填排在可选之后」在按位置绑定时是无解的：`cmd a` 到底是给了必填还是
			-- 跳过了可选？现在抛错，比在 Run 里猜一个答案好得多。
			return nil,
				`参数 {arg.name} 是必填的，但前面已经出现过可选参数：请按「必填在前、可选在后」声明`
		end
	end
	return args, nil
end

local function registerHelp(): ()
	local built = registry[lookupKey("help")]
	if built ~= nil then
		return
	end
	registry[lookupKey("help")] = {
		name = "help",
		help = "列出全部命令；`help <命令>` 看它的参数",
		args = { { name = "command", kind = "string", optional = true, default = nil } },
		handler = function(context: Context): string?
			return Command.Help(context.args.command)
		end,
	}
	registeredCount += 1
end

--[=[
	`help` 与 `help <命令>` 的文本。直接从注册表生成 —— 另立一份「命令清单」的话，
	它从今天起就不会再跟着注册/注销变化了。
]=]
function Command.Help(name: string?): string?
	local names: { string } = {}
	for key in registry do
		local entry = registry[key]
		if entry ~= nil and (name == nil or lookupKey(entry.name) == lookupKey(name :: string)) then
			names[#names + 1] = key :: string
		end
	end
	table.sort(names)
	if #names == 0 then
		return if name == nil
			then "（还没有注册任何命令）"
			else `未知命令 {Level.Describe(name)}`
	end
	if name ~= nil then
		local entry = registry[names[1]]
		if entry == nil then
			return nil
		end
		local out: { string } = { `{entry.name}  {entry.help or "（没有说明）"}` }
		local specs = entry.args
		if specs ~= nil then
			for index = 1, #specs do
				local arg = specs[index]
				local tail = if arg.optional == true
					then `（可选，默认 {Level.Describe(arg.default)}）`
					else "（必填）"
				out[#out + 1] = `    {arg.name}: {arg.kind}{tail}`
			end
		end
		return table.concat(out, "\n")
	end
	local out: { string } = {}
	for index = 1, #names do
		local entry = registry[names[index]]
		if entry ~= nil then
			local spec = entry.args
			local hint = if spec == nil or #spec == 0 then "" else ` <{#spec} 个参数>`
			out[#out + 1] = `  {entry.name}{hint}  {entry.help or "（没有说明）"}`
		end
	end
	return table.concat(out, "\n")
end

--[=[
	注册一条命令。`info` 可以是 `{ help = string, args = {ArgSpec} }`，也可以直接是一段
	说明文本（省掉只写 help 的那份表 —— 注册命令时十个里有九个只想写一句话）。

	校验失败**抛错**（见文件头第 2 条）。名字撞了也抛：静默覆盖会让「另一处也注册了同名命令」
	这种 bug 完全没有痕迹。要换实现就先 `Remove`。
]=]
function Command.Register(
	name: string,
	info: string | { help: string?, args: { ArgSpec }? },
	handler: Handler
): ()
	assert(
		Record.IsOneLine(name),
		`[Neon.Command] 命令名必须是不含控制字符的非空字符串，收到 {Level.Describe(name)}`
	)
	local key = lookupKey(name)
	assert(
		registry[key] == nil,
		`[Neon.Command] 命令 {name} 已注册（查找键 {key} 撞车：命令名大小写不敏感）；要换实现先 Remove`
	)
	assert(
		type(handler) == "function",
		`[Neon.Command] {name} 的 handler 必须是函数，收到 {Level.Describe(handler)}`
	)

	local help: string? = nil
	local specs: { ArgSpec }? = nil
	if type(info) == "string" then
		help = info :: string
	else
		assert(
			type(info) == "table",
			`[Neon.Command] {name} 的 info 只能是表或字符串，收到 {Level.Describe(info)}`
		)
		local table_ = info :: { help: string?, args: { ArgSpec }? }
		help = table_.help
		local checked, describeError = describeArgs(table_.args)
		assert(describeError == nil, `[Neon.Command] {name}: {describeError}`)
		specs = checked
	end

	registry[key] = { name = name, help = help, args = specs, handler = handler }
	registeredCount += 1
end

--[=[ 摘掉一条命令，返回是否真的摘掉了。与 `Sink.Remove` 同形。]=]
function Command.Remove(name: string): boolean
	local key = lookupKey(name)
	if registry[key] == nil then
		return false
	end
	registry[key] = nil
	registeredCount -= 1
	return true
end

--[=[ 命令名，按字典序（不是注册顺序 —— 那份顺序会随模块加载顺序变）。]=]
function Command.Names(): { string }
	local names: { string } = {}
	for key in registry do
		local entry = registry[key]
		if entry ~= nil then
			names[#names + 1] = entry.name
		end
	end
	table.sort(names)
	return names
end

function Command.Count(): number
	return registeredCount
end

--[=[
	补全候选。`prefix` 省略 = 全部。大小写不敏感，返回的是注册时的原样名字。

	只补命令名，不补参数值：参数值的候选属于各命令自己的领域（那要往 spec 里加
	`candidates`，而接缝每宽一寸，第三方命令就多一处会漏实现的地方 —— 见 `Sink` 的同条理由）。
]=]
function Command.Complete(prefix: string?): { string }
	local want = if prefix == nil then "" else lookupKey(prefix :: string)
	local names: { string } = {}
	for key in registry do
		local entry = registry[key]
		if entry ~= nil and string.sub(key, 1, #want) == want then
			names[#names + 1] = entry.name
		end
	end
	table.sort(names)
	return names
end

--[=[
	权限钩子。签名 `(caller, commandName) -> (allowed, whyNot)`。

	默认「一律允许」：核心不知道宿主的权限模型，猜一个默认值就是把某个游戏的规则当成通用规则。
	传 `nil` 复原。钩子**抛错时按拒绝处理**（fail closed，见文件头）。
]=]
function Command.SetPermissionHook(hook: PermissionHook?): ()
	if hook == nil then
		permissionHook = nil
		return
	end
	assert(
		type(hook) == "function",
		`[Neon.Command] 权限钩子必须是函数，收到 {Level.Describe(hook)}`
	)
	permissionHook = hook
end

local function fail(name: string?, errorText: string): Result
	rejectedTotal += 1
	return { ok = false, name = name, output = nil, error = errorText }
end

--[=[
	执行一行命令。**永不抛错**。

	返回 `{ ok, name, output, error }`：`ok` 只在 handler 正常跑完时为真；解析/绑定阶段的失败
	记进 `rejected`，越权记进 `denied`，handler 抛错记进 `errored` —— 三个数分开是有意的：
	「我的命令没生效」这三种原因的修法完全不同。
]=]
function Command.Run(line: string, caller: any?): Result
	if type(line) ~= "string" then
		return fail(nil, `[Neon.Command] Run 需要一行文本，收到 {Level.Describe(line)}`)
	end
	local tokens, parseError = tokenize(line :: string)
	if parseError ~= nil then
		return fail(nil, parseError)
	end
	if #tokens == 0 then
		return fail(nil, "空输入：没有命令名")
	end

	local rawName = tokens[1]
	local key = lookupKey(rawName)
	local entry = registry[key]
	if entry == nil then
		-- 顺手把前缀候选给出去：现场敲命令的人被打断一次就会记一次，比翻 help 快
		local candidates = Command.Complete(rawName)
		local hint = if #candidates > 0
			then `（是不是想打：{table.concat(candidates, ", ")}）`
			else ""
		return fail(rawName, `未知命令 {rawName}{hint}`)
	end

	runTotal += 1
	local hook = permissionHook
	if hook ~= nil then
		-- 钩子抛错 = 拒绝。这里 pcall 的返回值要接住两个（allowed 与 whyNot），所以把调用
		-- 包进一个显式返回两个值的闭包：直接 pcall(hook, ...) 在 `hook` 只返回一个值时，
		-- 类型层给不出第二个返回值（本仓的门禁实测过一次同形状的坑）。
		local ok, allowed, whyNot = pcall(function(): (boolean, string?)
			return hook(caller, entry.name)
		end)
		if not ok then
			deniedTotal += 1
			return {
				ok = false,
				name = entry.name,
				output = nil,
				error = `权限钩子抛错，按拒绝处理：{errorText(allowed)}`,
			}
		end
		if allowed ~= true then
			deniedTotal += 1
			return {
				ok = false,
				name = entry.name,
				output = nil,
				error = `未授权：{if whyNot == nil then entry.name else tostring(whyNot)}`,
			}
		end
	end

	local args: { [string]: any } = {}
	local specs = entry.args
	local given = #tokens - 1
	local declared = if specs == nil then 0 else #specs
	if given > declared then
		return fail(
			entry.name,
			`参数过多：{entry.name} 接受 {declared} 个，收到 {given} 个（多余的从第 {declared + 2} 个词开始）`
		)
	end
	if specs ~= nil then
		for index = 1, declared do
			local arg = specs[index]
			local raw = tokens[index + 1]
			if raw == nil then
				if arg.optional == true then
					if arg.default ~= nil then
						args[arg.name] = arg.default
					end
				else
					-- 把所有缺的都列出来：只报第一个的话，人改一个再试，要来回三趟。
					local missing: { string } = {}
					for scan = index, declared do
						local candidate = specs[scan]
						if candidate.optional ~= true then
							missing[#missing + 1] = candidate.name
						end
					end
					return fail(entry.name, `缺少参数：{table.concat(missing, ", ")}`)
				end
			else
				local value, coerceError = coerceValue(raw, arg)
				if coerceError ~= nil then
					return fail(entry.name, coerceError)
				end
				args[arg.name] = value
			end
		end
	end

	local context: Context = { name = entry.name, caller = caller, args = args, line = line }
	-- handler 抛错不能带走调用方（判据）。`handler` 声明成返回 `string?`，但第三方写的
	-- handler 什么都有可能返回，所以统一 tostring 过一遍再交出。
	local ok, output = pcall(entry.handler, context)
	if not ok then
		erroredTotal += 1
		return {
			ok = false,
			name = entry.name,
			output = nil,
			error = `命令 {entry.name} 抛错：{errorText(output)}`,
		}
	end
	succeededTotal += 1
	return {
		ok = true,
		name = entry.name,
		output = if output == nil then nil else tostring(output),
		error = nil,
	}
end

--[=[ 累计账目，**冻结**。与 `Filter.Stats()` 同一形状的理由：控制台界面一把读走就能显示。]=]
function Command.Stats(): {
	registered: number,
	run: number,
	succeeded: number,
	rejected: number,
	denied: number,
	errored: number,
}
	return table.freeze({
		registered = registeredCount,
		run = runTotal,
		succeeded = succeededTotal,
		rejected = rejectedTotal,
		denied = deniedTotal,
		errored = erroredTotal,
	})
end

--[=[
	清空注册表与账目，`help` 重新登记。

	「Reset 之后 help 还在」这件事必须写在代码里：测试夹具之间跑过一次 Reset，下一例的
	`Run("help")` 若成了「未知命令」，症状会出现在毫不相干的用例里。
]=]
function Command.Reset(): ()
	for key in registry do
		registry[key] = nil
	end
	registeredCount = 0
	permissionHook = nil
	runTotal = 0
	succeededTotal = 0
	rejectedTotal = 0
	deniedTotal = 0
	erroredTotal = 0
	registerHelp()
end

registerHelp()

return Command
