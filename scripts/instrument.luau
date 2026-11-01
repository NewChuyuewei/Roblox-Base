--!strict
-- 自研 statement 插桩器（C4 / Step 73）—— **纯函数 + 可注入的编译谓词**，所以可单测。
--
-- 抽出成模块的原因：`scripts/coverage.luau`（覆盖工具）与 `scripts/probe-coverage.luau`（成功性探针）
-- 必须用**同一份**插桩逻辑。探针若自带一份粗糙副本，它证明的就不是实际在跑的机制（会撒谎）。
--
-- 机制与三条已知陷阱（都是实测出来的，见 `docs/headless.md` §3）：
--  ① Lune 的 `loadstring` 遇到语法错会**抛**（不是返回 nil+err）→ 试编译必须 pcall；
--  ② 只靠编译裁判不够：表构造器里的 `a = 1,` 加上前缀会被当成合法的数组元素（`;` 是表分隔符）
--     → 必须用**括号深度 0** 排除构造器/表达式内部，否则分母虚高且会给表注入元素；
--  ③ 块注释/长字符串的关闭记号要按级别匹配（`--[=[` 对应 `]=]`），否则后面的代码被当成注释。
-- 探针前缀：`__cov.HIT(<行号>); `（放在**同一行**，行号不位移 —— 报告与 debug.info 都靠它）
local HIT = "__cov"
local HIT_FN = "HIT"

local function splitLines(text: string): { string }
	local out: { string } = {}
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		table.insert(out, line)
	end
	return out
end

local function trim(text: string): string
	return (string.gsub(text, "^%s*(.-)%s*$", "%1")) :: string
end

export type LineClass = { line: number, reason: string }
export type Instrumented = {
	text: string,
	executable: { number },
	skipped: { LineClass },
	candidates: number,
	issues: { string },
}

local function countChar(text: string, char: string): number
	return (select(2, string.gsub(text, char, ""))) :: number
end

-- 从含有长括号开头的行里取“关闭记号”（`--[=[` → `]=]`）。级别必须对上：只认 `]]` 会让
-- `--[=[ … ]=]` 里的 `]=]` 关不掉，后面的代码全被当成注释（第三方审计踩过同一个坑）。
-- 必须定义在 scanBrackets 之前：Luau 的局部函数不能先用后定义。
local function blockCloseOf(text: string): string?
	local level = string.match(text, "%[(=*)%[")
	if level == nil then
		return nil
	end
	return "]" .. level .. "]"
end

-- 扫描一行的**括号净深度**（只数代码部分，跳过字符串与行注释）。
-- 为什么必须有它：语句只能在括号深度为 0 处开始。只靠编译裁判不够 ——
-- 实测（自检 S8）：表构造器里的 `a = 1,` 加上前缀会变成 `{ __cov.HIT(n); a = 1, }`，
-- 这在 Luau 里**合法**（`;` 是表构造器的分隔符）→ 编译裁判放行 → 于是：
--   ① 分母把表字段行当语句（虚高）；② 前缀给表**注入了数组元素**（行为被改）。
-- 这正是 R21 所说的“插桩器自己错 → 假绿”，所以修在工具里，不修期望值。
-- 返回 (净深度, 本行末是否停在长字符串里)。
local function scanBrackets(line: string): (number, string?)
	local delta = 0
	local quote: string? = nil
	local i = 1
	while i <= #line do
		local ch = string.sub(line, i, i)
		if quote ~= nil then
			if ch == "\\" then
				i += 2
				continue
			end
			if ch == quote then
				quote = nil
			end
			i += 1
		elseif ch == '"' or ch == "'" then
			quote = ch
			i += 1
		elseif ch == "-" and string.sub(line, i + 1, i + 1) == "-" then
			break -- 行注释：后半行不计
		elseif ch == "[" then
			local close = blockCloseOf(string.sub(line, i, i + 8))
			if close ~= nil then
				return delta, close -- 长字符串开头：本行余下不计，且状态跨行
			end
			delta += 1
			i += 1
		elseif ch == "(" or ch == "{" then
			delta += 1
			i += 1
		elseif ch == ")" or ch == "}" or ch == "]" then
			delta -= 1
			i += 1
		else
			i += 1
		end
	end
	return delta, nil
end

-- 预筛：只排除"明显不是语句开头"的行。**故意宽松** —— 剩余判断交给编译器，
-- 因为漏判（把真语句当成不能插）会让分母偏小、覆盖率虚高，那比多试几次编译危险得多。
local function prefilter(line: string): (boolean, string)
	local stripped = trim(line)
	if stripped == "" then
		return false, "空行"
	end
	if string.sub(stripped, 1, 2) == "--" then
		return false, "注释行"
	end
	local first = string.match(stripped, "^([%w_]+)")
	if first == "end" or first == "else" or first == "elseif" or first == "until" or first == "then" then
		return false, `块结构行（{first}）`
	end
	local ch = string.sub(stripped, 1, 1)
	if ch == "}" or ch == ")" or ch == "]" then
		return false, "块尾行"
	end
	return true, ""
end

-- 插桩：把 `HIT(n); ` 前缀放在**同一行**（保持行号不位移 —— 报告与 debug.info 都要靠它）
local function instrumentText(text: string, keep: { [number]: boolean }): string
	local out: { string } = {}
	local index = 0
	for _, line in splitLines(text) do
		index += 1
		if keep[index] then
			table.insert(out, `{HIT}.{HIT_FN}({index}); {line}`)
		else
			table.insert(out, line)
		end
	end
	return table.concat(out, "\n")
end

-- ⚠ Lune 的 `loadstring` 在**语法错时会抛**（不像 Roblox 的返回 nil+err；已实测：
-- `pcall(loadstring, "local x = (")` → ok=false）。不 pcall 的话试编译会把整管炸穿 ——
-- 首版就是这样在 CoreTypes 的类型块上崩的。
local function tryCompile(text: string, chunkName: string): (boolean, string)
	local ok, fn, err = pcall(loadstring, text, chunkName)
	if not ok then
		return false, tostring(fn)
	end
	if fn == nil then
		return false, tostring(err)
	end
	return true, ""
end

-- ---------- 插桩主流程（纯函数：只依赖传入的文本与一个编译谓词）----------
-- 用可注入的 compile 谓词，自检才能用假的编译器来构造"插桩器该报错"的场景。
local function Instrument(
	text: string,
	chunkName: string,
	compile: ((string, string) -> (boolean, string))?
): Instrumented
	local compiler = compile or tryCompile
	local lines = splitLines(text)
	local candidates: { number } = {}
	local skipped: { LineClass } = {}
	local issues: { string } = {}
	local blockClose: string? = nil
	local inType = false
	local typeBalance = 0
	local depth = 0
	for index, line in lines do
		if blockClose ~= nil then
			table.insert(skipped, { line = index, reason = "块注释/长字符串内部" })
			if string.find(line, blockClose, 1, true) ~= nil then
				blockClose = nil
			end
		elseif inType then
			-- 类型定义是**编译期**的东西，不是可执行语句 → 整块归入不可执行
			table.insert(skipped, { line = index, reason = "类型定义内部（编译期）" })
			typeBalance += countChar(line, "{") - countChar(line, "}")
			if typeBalance <= 0 then
				inType = false
			end
		else
			local stripped = trim(line)
			local isTypeDecl = string.match(stripped, "^export%s+type%s") ~= nil
				or string.match(stripped, "^local%s+type%s") ~= nil
				or string.match(stripped, "^type%s+%w") ~= nil
			if isTypeDecl then
				table.insert(skipped, { line = index, reason = "类型声明（编译期，不可执行）" })
				local balance = countChar(line, "{") - countChar(line, "}")
				if balance > 0 then
					inType = true
					typeBalance = balance
				end
			else
				local opensBlock = blockCloseOf(line)
				if string.sub(stripped, 1, 2) == "--" and opensBlock ~= nil then
					table.insert(skipped, { line = index, reason = "块注释开始" })
					blockClose = opensBlock
				else
					local ok, reason = prefilter(line)
					if ok and depth > 0 then
						-- 深度 > 0 = 在表达式/表构造器/多行调用里，不是语句边界
						if string.find(line, "function", 1, true) ~= nil then
							-- 造器里的函数体若被整块跳过，就是**少统计**（宁可报违规也不静默）
							table.insert(
								issues,
								`{chunkName}:{index} 表达式/构造器内的 function 会被整块跳过（会少统计）`
							)
						end
						table.insert(
							skipped,
							{ line = index, reason = "表达式/表构造器内部（不是语句边界）" }
						)
					elseif ok then
						table.insert(candidates, index)
					else
						table.insert(skipped, { line = index, reason = reason })
					end
				end
			end
		end
		-- 括号深度在“看完这一行”之后更新（无论它是否是候选行）
		local delta, opensLong = scanBrackets(line)
		depth += delta
		if opensLong ~= nil and blockClose == nil then
			blockClose = opensLong
		end
	end

	-- 逐行试编译：只有编译器接受的候选行才算可执行行
	local keep: { [number]: boolean } = {}
	local executable: { number } = {}
	for _, index in candidates do
		local single: { [number]: boolean } = { [index] = true }
		local ok = compiler(instrumentText(text, single), chunkName)
		if ok then
			keep[index] = true
			table.insert(executable, index)
		else
			table.insert(skipped, { line = index, reason = "编译验证未通过（不是语句开头）" })
		end
	end

	local instrumented = instrumentText(text, keep)
	local jointOk, jointErr = compiler(instrumented, chunkName)
	assert(jointOk, `[coverage] 插桩器 bug：逐行都能编译，合起来却不行 —— {jointErr}`)

	return {
		text = instrumented,
		executable = executable,
		skipped = skipped,
		candidates = #candidates,
		issues = issues,
	}
end
-- 只暴露消费者需要的面（其余是内部实现）
local M = {
	Instrument = Instrument,
	HIT = HIT,
	HIT_FN = HIT_FN,
	splitLines = splitLines,
	trim = trim,
	countChar = countChar,
	blockCloseOf = blockCloseOf,
	scanBrackets = scanBrackets,
	prefilter = prefilter,
}

return table.freeze(M)
