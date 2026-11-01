--!nocheck
-- C4 / Step 73 的**成功性探针**：在动手写覆盖工具之前，先把"机制到底行不行"测清楚。
--
--   lune run scripts/probe-coverage.luau
--
-- 它回答四个问题（每条都给可复现的实测输出，不是推断）：
--   P1 `debug.sethook` 存在吗？（Step 7 说不存在 —— 现在再测一次）
--   P2 有什么可用的 debug 面？（`debug.info` 的返回形状决定 R21 的交叉校验怎么写）
--   P3 源码插桩 + `loadstring` + `setfenv` 这条路线在**真实认证文件**上能跑吗？
--   P4 插桩后的语义与未插桩是否一致？（不一致 = 插桩器坏了 = R21 的假绿来源）
--
-- 结论写进 `docs/headless.md` §3 与 `CERT.md` §7.2/§7.3；本文件是那条结论的证据。

local fs = require("@lune/fs")
-- 注意：`debug` 是**全局**，但它**不是** `_G` 的键（Lune 的 `_G` 是空表）——
-- 首版写成 `_G.debug` 直接拿到 nil 而崩。别用 `_G` 探测标准库。

local function heading(text: string)
	print("")
	print(`--- {text} ---`)
end

local facts: { { id: string, question: string, result: string } } = {}
local function record(id: string, question: string, result: string)
	table.insert(facts, { id = id, question = question, result = result })
	print(`[{id}] {question}`)
	print(`      → {result}`)
end

-- ---------- P1：sethook ----------
heading("P1 debug.sethook 是否可用")
local sethook = (debug :: any).sethook
local sethookText = `存在（{type(sethook)}）`
if sethook == nil then
	sethookText = "nil —— 行钩子路线确实作废"
end
record("P1", "debug.sethook 存在吗", sethookText)

-- ---------- P2：可用的 debug 面 ----------
heading("P2 可用的 debug 面")
local probeFn = function(a: number, b: number): number
	local sum = a + b
	if sum > 10 then
		return sum * 2
	end
	return sum
end
local info = (debug :: any).info
local available: { string } = {}
for _, name in { "info", "traceback", "getinfo", "profilebegin", "profileend", "setmetatable", "getupvalue" } do
	if (debug :: any)[name] ~= nil then
		table.insert(available, name)
	end
end
record("P2", "debug 上存在的名字", table.concat(available, " · "))

local sourceInfo = info(probeFn, "s")
local sourceInfoText = "nil"
if sourceInfo ~= nil then
	sourceInfoText = tostring(sourceInfo)
end
record("P2b", 'debug.info(fn, "s") 的返回', sourceInfoText)

local okInfo, infoSln = pcall(info, probeFn, "sln")
local slnCount = select("#", info(probeFn, "sln"))
record("P2c", 'debug.info(fn, "sln") 的返回', `ok={okInfo} 个数={slnCount} 值={tostring(infoSln)}`)

local lineInfo = info(probeFn, "l")
record(
	"P2d",
	'debug.info(fn, "l") 的类型',
	`{type(lineInfo)}（函数定义所在行，不是行范围）`
)

-- ---------- P3：用**真实的**插桩器（scripts/instrument.luau）跑一个认证文件 ----------
heading("P3 源码插桩（真实工具）+ loadstring + setfenv（真实认证文件）")
print(
	"      （刻意不用探针自带的粗糙副本：探针若自带一份，它证明的就不是实际在跑的机制）"
)

local Instrumenter = require("./instrument")
local Loader = require("./lune-loader")
local splitLines = Instrumenter.splitLines

local target = "src/ReplicatedStorage/Deuterium/Core/Foundation/ErrorHandler.luau"
local original = fs.readFile(target)

-- 装载插桩版需要 loader 的环境，否则 require(script.Parent.CoreTypes) 解析不了
local function nodeFor(path: string): any
	local root = Loader.mount()
	local node = root
	local rel = (string.gsub(path, "^src/ReplicatedStorage/", "")) :: string
	for segment in string.gmatch(rel, "[^/]+") do
		local name = if string.sub(segment, -5) == ".luau" then string.sub(segment, 1, -6) else segment
		node = (name == "init") and node or node.children[name]
		if node == nil then
			error(`找不到节点: {path}（在 {segment} 处）`, 0)
		end
	end
	return node
end

local plan = Instrumenter.Instrument(original, target)
local hits: { [number]: number } = {}
local env = Loader.env(nodeFor(target), {})
env[Instrumenter.HIT] = {
	[Instrumenter.HIT_FN] = function(no: number)
		hits[no] = (hits[no] or 0) + 1
	end,
}
local ok, module = pcall(function()
	local chunk = assert(loadstring(plan.text, target))
	setfenv(chunk, env)
	return chunk()
end)
local loadResult = `不能: {tostring(module)}`
if ok then
	loadResult = `能（返回 {type(module)}）`
end
record("P3", "插桩后的 ErrorHandler 能加载吗", loadResult)
record(
	"P3b",
	"插桩器认定的可执行行数",
	`{#plan.executable} 行（文件共 {#splitLines(original)} 行）`
)
record(
	"P3c",
	"插桩器给出的不可执行行数",
	`{#plan.skipped} 行（逐条理由见 docs/cert/coverage/*.json）`
)

-- ---------- P4：语义一致性（R21 的核心）----------
heading("P4 插桩前后语义是否一致")
local plainChunk = loadstring(original, target)
setfenv(plainChunk, Loader.env(nodeFor(target), {}))
local plain = plainChunk()

-- 同一串调用分别打在"未插桩"与"插桩"两个模块实例上，逐个比对输出
local function snapshot(mod: any): { string }
	-- ErrorHandler.luau 返回的是**自身表**（不是 { ErrorHandler = ... }）；两种形状都容纳
	local handler = mod.ErrorHandler or mod
	local out: { string } = {}
	table.insert(out, handler.New("DR.A", "m", "s").code)
	table.insert(out, tostring(select(1, pcall(handler.New, "", "m"))))
	table.insert(out, handler.Render(nil))
	table.insert(out, tostring(handler.IsDrError(42)))
	local r = handler.Try(function()
		error("boom")
	end, "DR.F", "s")
	table.insert(out, `ok={tostring(r.ok)} code={r.err.code}`)
	table.insert(out, handler.Normalize("str", "DR.N", "s").code)
	return out
end

local before = snapshot(plain)
local after: { string } = {}
if ok then
	after = snapshot(module)
end
local mismatches = 0
for index = 1, #before do
	local other = after[index] or "n/a"
	local same = before[index] == other
	if not same then
		mismatches += 1
	end
	local mark = "一致"
	if not same then
		mark = "**不一致**"
	end
	print(`      #{index}: 普通={before[index]} 插桩={other} {mark}`)
end
local consistency = `{mismatches} 处不一致 → 插桩器有 bug`
if mismatches == 0 then
	consistency = "全部一致（插桩不改变行为）"
end
record("P4", "语义一致性", consistency)

local hitCount = 0
for _ in hits do
	hitCount += 1
end
record(
	"P4b",
	"插桩版跑完后的命中行数",
	`{hitCount} / {#plan.executable} 行（只跑了上面这几个调用，不是完整用例集）`
)

-- ---------- 结论 ----------
-- ---------- P5：loadstring 的错误行为（决定试编译怎么写）----------
heading("P5 loadstring 遇到语法错会抛还是返回 nil")
local okBad, valueA, valueB = pcall(loadstring, "local x = (", "bad")
record(
	"P5",
	"pcall(loadstring, 语法错)",
	`ok={okBad} · 值1={tostring(valueA):sub(1, 48)} · 值2={tostring(valueB)}`
)
print(
	"      （Roblox 的 loadstring 返回 nil+err；Lune 里会**抛** —— 试编译谓词必须 pcall）"
)

-- ---------- P6：@lune/luau 的能力面 ----------
heading("P6 @lune/luau 能不能给 AST / 原生覆盖")
local luauOk, luauLib = pcall(require, "@lune/luau")
if luauOk then
	local members: { string } = {}
	for key in luauLib do
		table.insert(members, tostring(key))
	end
	table.sort(members)
	record("P6", "@lune/luau 的成员", table.concat(members, " · "))
	record(
		"P6b",
		"有没有 parser / 覆盖读取",
		`parse={tostring(luauLib.parse)} · coverage={tostring(luauLib.coverage)}（nil = 没有）`
	)
else
	record("P6", "@lune/luau 可用性", `不可用: {tostring(luauLib)}`)
end

-- ---------- P7：_G 是不是环境表 ----------
heading("P7 _G 在 Lune 里是什么")
local globalNames = 0
for _ in _G do
	globalNames += 1
end
record(
	"P7",
	"_G 的键个数 / debug 是否在 _G 里",
	`{globalNames} 个键 · _G.debug={tostring((_G :: any).debug)}（而全局 debug={type(debug)}）`
)

-- ---------- P8：表构造器陷阱（插桩器为什么必须算括号深度）----------
heading("P8 只靠编译裁判够吗（下表字段行的反例）")
local injectedText = "local t = {\n\t__cov.HIT(2); a = 1,\n\tb = 2,\n}\nreturn t"
local injectedChunk = loadstring(injectedText, "ctor")
local injectNote = "被编译器拦住（那就没有这个问题）"
if injectedChunk ~= nil then
	setfenv(injectedChunk, setmetatable({ __cov = { HIT = function() end } }, { __index = _G }))
	local built = injectedChunk()
	local n = 0
	for _ in built do
		n += 1
	end
	injectNote = `编译器**放行**，且表被注入了数组元素（键数={n}，a/b 仍为 {tostring(
		built.a
	)}/{tostring(built.b)}）`
end
record("P8", "给表构造器的字段行加前缀会怎样", injectNote)
print(
	"      （`;` 在表构造器里是合法分隔符 → 前缀成了**数组元素**：编译裁判会放行，"
)
print(
	"        所以插桩器必须额外用括号深度排除构造器内部 —— 见 scripts/coverage.luau 的 scanBrackets）"
)

heading("结论")
print(
	"P1 决定机制路线，P2 决定 R21 的交叉校验怎么写，P3/P4 决定插桩器能不能作为覆盖工具的基础，"
)
print(
	"P5/P6/P7 是工具约束（试编译要 pcall、没有原生覆盖、别用 _G 探测），P8 是插桩器的关键陷阱。"
)
local hookText = "有"
if sethook == nil then
	hookText = "无"
end
local routeText = "不可行"
if ok then
	-- ok = P3 里插桩版成功装载（配合 P4 的语义一致才是“可行”）
	routeText = "可行"
end
local consistentText = "否"
if mismatches == 0 then
	consistentText = "是"
end
print(`本次：sethook={hookText} · 插桩路线={routeText} · 语义一致={consistentText}`)
