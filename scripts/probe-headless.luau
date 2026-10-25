--!nocheck
-- Step 7 探针：headless 环境下我们能做什么、不能做什么。
--
-- 它回答两个**决定架构**的问题（不只是工具链问题）：
--   Q1 能否在无 Roblox 的环境里加载用 script.Parent 的模块？（决定核心模块怎么写）
--   Q2 能否做到行级结构覆盖？（决定 C4 是否可交付，进而决定 DAL C 是否成立 —— 风险 R18）
--
-- 运行：lune run scripts/probe-headless.luau
-- 结果固化在 docs/headless.md。

type Row = { label: string, ok: boolean, value: string }
local results: { Row } = {}

local function probe(label: string, fn: () -> any)
	local ok, value = pcall(fn)
	table.insert(results, { label = label, ok = ok, value = tostring(value) })
end

-- ---------- 运行时能力 ----------
probe("debug 表存在", function()
	return type(debug)
end)
probe("debug.sethook 存在", function()
	return type(debug.sethook)
end)
probe("debug.info 存在（Luau 版 getinfo）", function()
	return type(debug.info)
end)
probe("debug.getinfo 存在", function()
	return type(debug.getinfo)
end)
probe("getfenv / setfenv 存在", function()
	return tostring(type(getfenv)) .. " / " .. tostring(type(setfenv))
end)
probe("luau 库存在", function()
	return type(luau)
end)
probe("luau.load 存在", function()
	return type(luau.load)
end)
probe("os.time / os.date 可用", function()
	return tostring(os.time() > 0) .. " / " .. tostring(os.date("%H:%M:%S"))
end)
probe("coroutine 可用", function()
	return type(coroutine.create)
end)
probe("game 全局存在（应为 false）", function()
	return tostring(rawget(_G, "game") ~= nil)
end)

-- ---------- Q2 行级覆盖 ----------
local function tracedSum(n: number): number
	local sum = 0
	for i = 1, n do
		sum += i -- LINE_A
		if i % 2 == 0 then
			sum += 100 -- LINE_B
		end
	end
	return sum
end

probe("行钩子：计数被执行的行", function()
	local seen: { [number]: boolean } = {}
	debug.sethook(function(_event: string, line: number)
		seen[line] = true
	end, "l")
	tracedSum(4)
	debug.sethook()
	local count = 0
	for _ in pairs(seen) do
		count += 1
	end
	return `{count} 行被执行`
end)

probe("行钩子：能区分取与不取的分支行", function()
	local function run(n: number): number
		local seen: { [number]: boolean } = {}
		debug.sethook(function(_event: string, line: number)
			seen[line] = true
		end, "l")
		tracedSum(n)
		debug.sethook()
		local count = 0
		for _ in pairs(seen) do
			count += 1
		end
		return count
	end
	local onlyOdd = run(1) -- i % 2 == 0 永不成立 -> LINE_B 不该被命中
	local both = run(4) -- 两条分支都走
	return `n=1 命中 {onlyOdd} 行 / n=4 命中 {both} 行 -> 分支可区分: {both > onlyOdd}`
end)

probe("行钩子：协程内是否生效（关键）", function()
	local seen: { [number]: boolean } = {}
	local co = coroutine.create(function()
		local x = 1
		x += 1
		coroutine.yield(x)
		x += 1
		return x
	end)
	-- 钩子是 per-thread 的：必须在协程内设置才能覆盖协程
	debug.sethook(function(_event: string, line: number)
		seen[line] = true
	end, "l")
	coroutine.resume(co)
	coroutine.resume(co)
	debug.sethook()
	local count = 0
	for _ in pairs(seen) do
		count += 1
	end
	return `{count} 行（主线程钩子对协程的效果）`
end)

probe("协程内自行设置钩子", function()
	local seen: { [number]: boolean } = {}
	local co = coroutine.create(function()
		debug.sethook(function(_event: string, line: number)
			seen[line] = true
		end, "l")
		local x = 1
		x += 1
		coroutine.yield(x)
		x += 1
		debug.sethook()
		return x
	end)
	coroutine.resume(co)
	coroutine.resume(co)
	local count = 0
	for _ in pairs(seen) do
		count += 1
	end
	return `{count} 行（协程内设钩子）`
end)

-- ---------- Q1 script 垫片 ----------
probe("luau.load(src, {environment}) 注入 script", function()
	local chunk = luau.load("return script.Parent.Answer", {
		environment = { script = { Parent = { Answer = 42 } } },
	})
	return chunk()
end)

probe("luau.load(src, {injectGlobals}) 注入 script", function()
	local chunk = luau.load("return script.Parent.Answer", {
		injectGlobals = { script = { Parent = { Answer = 42 } } },
	})
	return chunk()
end)

probe("_G 赋值是否被被 require 的模块看见", function()
	rawset(_G, "PROBE_GLOBAL", "visible")
	local chunk = luau.load("return PROBE_GLOBAL")
	return chunk()
end)

-- ---------- 第二轮：C4（结构覆盖）可行性 ----------
-- 第一轮已证明 debug.sethook 不可用 -> 行钩子路线作废。
-- 改问：**源码插桩 + loadstring** 是否可行（商用覆盖工具做的就是源码/AST 插桩，不靠 VM 调试 API）。

probe("loadstring / load 可用", function()
	return tostring(type(loadstring)) .. " / " .. tostring(type(load))
end)

probe("setfenv 可用于 loadstring 的 chunk", function()
	local chunk = assert(loadstring("return VALUE"))
	setfenv(chunk, { VALUE = 7 })
	return `注入环境后取到 {chunk()}`
end)

probe("端到端：文本插桩 + loadstring 报告行覆盖", function()
	local source = table.concat({
		"local function f(n)",
		"  local s = 0",
		"  for i = 1, n do",
		"    s += i",
		"    if i % 2 == 0 then",
		"      s += 100",
		"    end",
		"  end",
		"  return s",
		"end",
		"return f",
	}, "\n")

	-- 粗粒度插桩：在非空/非注释/非块尾行前插 __hit(N)。
	-- 已知限制：以 end/else/elseif/until/} 开头的行必须跳过，否则语法错。
	local skipHeads = { ["end"] = true, ["else"] = true, ["elseif"] = true, ["until"] = true, ["}"] = true }
	local hit: { [number]: boolean } = {}
	local out: { string } = {}
	local lineNo = 0
	for line in string.gmatch(source .. "\n", "([^\n]*)\n") do
		lineNo += 1
		local trimmed = string.match(line, "^%s*(.-)%s*$") or ""
		local head = string.match(trimmed, "^(%S+)") or ""
		if trimmed == "" or string.sub(trimmed, 1, 2) == "--" or skipHeads[head] then
			table.insert(out, line)
		else
			table.insert(out, string.format("__hit(%d) %s", lineNo, line))
		end
	end
	local instrumented = table.concat(out, "\n")
	local chunk = assert(loadstring(instrumented, "instrumented"))
	setfenv(chunk, {
		__hit = function(n: number)
			hit[n] = true
		end,
	})
	local f = chunk()
	local sum = f(4)
	local count = 0
	for _ in pairs(hit) do
		count += 1
	end
	local hitLines: { string } = {}
	for line in pairs(hit) do
		table.insert(hitLines, tostring(line))
	end
	table.sort(hitLines)
	return `f(4)={sum} · 命中行 {table.concat(hitLines, ",")}`
end)

probe("插桩能暴露未覆盖行（n=1 时不该命中 L6）", function()
	local source = "local s = 0\nfor i = 1, N do\ns += i\nif i % 2 == 0 then\ns += 100\nend\nend\nreturn s"
	local hit: { [number]: boolean } = {}
	local out: { string } = {}
	local lineNo = 0
	for line in string.gmatch(source .. "\n", "([^\n]*)\n") do
		lineNo += 1
		local head = string.match(line, "^%s*(%S+)") or ""
		if head == "end" then
			table.insert(out, line)
		else
			table.insert(out, string.format("__hit(%d) %s", lineNo, line))
		end
	end
	local chunk = assert(loadstring(table.concat(out, "\n")))
	setfenv(chunk, {
		N = 1,
		__hit = function(n: number)
			hit[n] = true
		end,
	})
	chunk()
	return `N=1 时命中 {if hit[5]
		then "含 L5（错：%2==0 不可能成立）"
		else "不含 L5（对：分支被区分）"}`
end)

probe("debug.info 能取函数源行（覆盖分母用）", function()
	local function g(): number
		return 1
	end
	local src, line = debug.info(g, "sl")
	return tostring(src) .. " @L" .. tostring(line)
end)

-- ---------- 第三轮：Q1（能否 headless 加载真模块）----------
-- 思路：模块里写的是 require(script.Parent.X)。把源码 loadstring 后用 setfenv 注入一个
-- 环境，其中 script.Parent.X 已经是**拓扑序上先加载好的兄弟模块表**，而 require 换成
-- 恒等函数。这样不需要 Roblox 实例树，也不需要改源码。
-- （拓扑序本来就要算：Dr.Core.Container.DependencyInjector 就是干这个的。）

local fs = require("@lune/fs")

-- 关键发现：Lune 里 _G **不是**全局环境表（与第一轮“_G.script 注入无效”互相印证）。
-- 所以要显式拷贝需要的名字，并用 getfenv() 取真实的全局环境。
local GLB: any = getfenv(1)
local COPIED = {
	"print",
	"warn",
	"type",
	"typeof",
	"tostring",
	"tonumber",
	"pairs",
	"ipairs",
	"next",
	"select",
	"pcall",
	"xpcall",
	"error",
	"assert",
	"rawget",
	"rawset",
	"rawequal",
	"setmetatable",
	"getmetatable",
	"string",
	"table",
	"math",
	"os",
	"coroutine",
	"utf8",
	"bit32",
	"buffer",
	"debug",
}

local function makeEnv(siblings: { [string]: any }): { [string]: any }
	local env: { [string]: any } = {}
	for _, name in COPIED do
		env[name] = GLB[name]
	end
	env.warn = GLB.warn or print -- Lune 无 warn；测试失败时会用到
	env.script = { Parent = siblings }
	env.require = function(target: any): any
		return target
	end
	setmetatable(env, { __index = GLB }) -- 双保险
	return env
end

local function loadModule(path: string, siblings: { [string]: any }): any
	local source = fs.readFile(path) :: string
	local chunk = assert(loadstring(source, path))
	setfenv(chunk, makeEnv(siblings))
	return chunk()
end

probe("setfenv 后 __index=_G 仍能取到标准库", function()
	local chunk = assert(
		loadstring("return type(string.format) .. table.concat({'a','b'}, '-') .. tostring(os.time() > 0)")
	)
	setfenv(chunk, makeEnv({}))
	return chunk()
end)

probe("headless 加载 Logging 四模块（拓扑序）", function()
	local dir = "Deuterium/Diagnostics/Logging/"
	local StructuredLog = loadModule(dir .. "StructuredLog.luau", {})
	local LogSink = loadModule(dir .. "LogSink.luau", { StructuredLog = StructuredLog })
	local Logger = loadModule(dir .. "Logger.luau", { StructuredLog = StructuredLog, LogSink = LogSink })
	local Debug = loadModule(dir .. "Debug.luau", { Logger = Logger })
	return `四模块已加载；StructuredLog.Format 可用: {type(StructuredLog.Format) == "function"}`
end)

probe("headless 跑 Logging 的 SelfTest（真用例，非重写）", function()
	local dir = "Deuterium/Diagnostics/Logging/"
	local StructuredLog = loadModule(dir .. "StructuredLog.luau", {})
	local LogSink = loadModule(dir .. "LogSink.luau", { StructuredLog = StructuredLog })
	local Logger = loadModule(dir .. "Logger.luau", { StructuredLog = StructuredLog, LogSink = LogSink })
	local SelfTest = loadModule(dir .. "SelfTest.luau", {
		StructuredLog = StructuredLog,
		LogSink = LogSink,
		Logger = Logger,
	})
	local passed = SelfTest.RunAll()
	return `RunAll() = {passed}`
end)

-- ---------- 输出 ----------
print(("="):rep(78))
local pass, fail = 0, 0
for _, row in results do
	if row.ok then
		pass += 1
	else
		fail += 1
	end
	print(string.format("%-46s %-5s %s", row.label, if row.ok then "OK" else "FAIL", row.value))
end
print(("="):rep(78))
print(`探针 {#results} 项：OK {pass} · FAIL {fail}`)
print("（FAIL 不等于坏事：有些能力本就不该存在，例如 game 全局）")
