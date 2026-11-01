--!strict
-- C4 / Step 73：自研 statement 覆盖工具（门禁 12 的实现）
--
--   lune run scripts/coverage.luau             # 跑认证线用例（插桩版）→ 产出 docs/cert/coverage/<MOD>.json + 门禁 12 判定
--   lune run scripts/coverage.luau --quiet
--   lune run scripts/coverage.luau --selftest  # 插桩器自己的测试（CERT.md §7.3 要求）
--
-- 机制（探针实测决定，见 `docs/headless.md` §3）：
--   `debug.sethook` 在 Lune 0.11.1 **不存在**（`scripts/probe-coverage.luau` P1 复测），
--   `@lune/luau` 只有 `compile`/`load`（无 parser、无 `getcoverage`）→ 原生覆盖路线不可用。
--   因此：**源码插桩 + loadstring + setfenv**。
--
-- 为什么不是"启发式插桩"：R21 的失效模式就是插桩器自己写错（高估→假绿）。
-- 这里用一个**编译器当裁判**的办法把它变成可验证的：
--   ① 预筛掉空白/注释/块尾（`end`/`else`/`}`…）这类显然不能插的行；
--   ② 对每个候选行，**单独**插一行 `__cov.HIT(n); ` 并交给 `loadstring` 编译 —— 只有真能编译的才留下；
--   ③ 用保留集整体再编译一次（若失败 = 插桩器 bug，直接报错而不是继续算数）；
--   ④ 与 `debug.info(fn, "sln")` 的函数定义行交叉校验（R21 明写的对策）；
--   ⑤ 插桩版必须让**同一套**认证线用例仍然全过（语义未变），否则覆盖数字不可信。
--
-- 分母的口径：**通过了编译验证的行** = 可执行行。这不是"我认为它能插"，而是"编译器同意它是个语句"。
-- 未覆盖行必须逐条在 `docs/cert/coverage/UNCOVERED.md` 里给出理由，否则门禁 12 失败
-- （`CERT.md` §7.2："100% statement coverage + 覆盖未达标的合理解释"）。

local Loader = require("./lune-loader")
local Harness = require("./cert-harness")
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local CERT_MODULES = {
	{
		mod = "CORETYPES",
		key = "CoreTypes",
		src = "src/ReplicatedStorage/Deuterium/Core/Foundation/CoreTypes.luau",
	},
	{
		mod = "CONTRACT",
		key = "Contract",
		src = "src/ReplicatedStorage/Deuterium/Core/Foundation/Contract.luau",
	},
	{
		mod = "ERRORHANDLER",
		key = "ErrorHandler",
		src = "src/ReplicatedStorage/Deuterium/Core/Foundation/ErrorHandler.luau",
	},
	{
		mod = "INTERFACE",
		key = "Interface",
		src = "src/ReplicatedStorage/Deuterium/Types/Contract/Interface.luau",
	},
}
local COVERAGE_DIR = "docs/cert/coverage"
local EXPLAINED_FILE = `{COVERAGE_DIR}/UNCOVERED.md`

-- ---------- 插桩器（独立模块）----------
-- 探针与覆盖工具共用同一份逻辑（见 scripts/instrument.luau 的文件头）。
-- ⚠ 要先 require 再起别名：Luau 的局部变量只在其声明**之后**可见（这条坑在本项目踩过三次）。
local Instrumenter = require("./instrument")
local Instrument = Instrumenter.Instrument
local splitLines = Instrumenter.splitLines
local trim = Instrumenter.trim
local HIT = Instrumenter.HIT
local HIT_FN = Instrumenter.HIT_FN
export type LineClass = Instrumenter.LineClass
export type Instrumented = Instrumenter.Instrumented

-- ---------- 未覆盖理由登记表 ----------
-- 格式：`- <file>:<line> — <理由>`（理由至少 8 个字符，避免写成 "n/a" 糊过去）
local function readExplained(): { [string]: string }
	local out: { [string]: string } = {}
	if not fs.isFile(EXPLAINED_FILE) then
		return out
	end
	for _, line in splitLines(fs.readFile(EXPLAINED_FILE)) do
		local path, number, reason = string.match(line, "^%-%s+([%w%./_%-]+):(%d+)%s+[—%-]%s+(.+)$")
		if path ~= nil and number ~= nil and reason ~= nil and #trim(reason) >= 8 then
			out[`{path}:{number}`] = trim(reason)
		end
	end
	return out
end

-- ---------- 装载与运行 ----------
local function nodeFor(path: string): any
	local root = Loader.mount()
	local rel = (string.gsub(path, "^src/ReplicatedStorage/", "")) :: string
	local node = root
	for segment in string.gmatch(rel, "[^/]+") do
		local name = if string.sub(segment, -5) == ".luau" then string.sub(segment, 1, -6) else segment
		node = (name == "init") and node or node.children[name]
		if node == nil then
			error(`[coverage] 找不到节点: {path}（在 {segment} 处）`, 0)
		end
	end
	return node
end

export type ModuleReport = {
	mod: string,
	file: string,
	sourceHash: number,
	lineCount: number,
	candidates: number,
	executable: number,
	hit: number,
	missed: { { line: number, text: string, explained: string? } },
	-- 分类要可人工复核：哪些行被归为不可执行、理由是什么（R21 / CERT.md §7.3 的审核面）
	skipped: { { line: number, reason: string, text: string } },
	functionLines: { { line: number, name: string, classified: boolean } },
	cases: number,
	caseFailures: { string },
}

local function fnLine(fn: any): (number?, string)
	local ok, source, line = pcall(function()
		return debug.info(fn, "sln")
	end)
	local _ = ok
	local _ = source
	return line, ""
end

local function coverageRun(): ({ ModuleReport }, { string })
	local violations: { string } = {}
	local explained = readExplained()
	local reports: { ModuleReport } = {}

	-- 先装载**未插桩**版本，用于取函数定义行（debug.info 的交叉校验）
	local plainModules: { [string]: any } = {}
	for _, entry in CERT_MODULES do
		plainModules[entry.key] = Loader.load(entry.src)
	end

	-- 插桩版：每个模块单独插桩，并注入收集器
	local instrumentedModules: { [string]: any } = {}
	local plans: { [string]: Instrumented } = {}
	local hits: { [string]: { [number]: number } } = {}
	for _, entry in CERT_MODULES do
		local source = fs.readFile(entry.src)
		local plan = Instrument(source, entry.src)
		plans[entry.key] = plan
		local collector: { [number]: number } = {}
		hits[entry.key] = collector
		local env = Loader.env(nodeFor(entry.src), {})
		env[HIT] = {
			[HIT_FN] = function(no: number)
				collector[no] = (collector[no] or 0) + 1
			end,
		}
		local chunk = assert(loadstring(plan.text, entry.src))
		setfenv(chunk, env)
		instrumentedModules[entry.key] = chunk()
	end

	-- 用**同一套用例**跑插桩版：语义必须没变
	local M: any = { meta = { engineStub = false, instrumented = true } }
	for _, entry in CERT_MODULES do
		M[entry.key] = instrumentedModules[entry.key]
	end
	local caseFailures: { [string]: { string } } = {}
	local caseCounts: { [string]: number } = {}
	for _, entry in CERT_MODULES do
		local cases = Harness.loadCases(entry.key)
		caseCounts[entry.key] = #cases
		local _, t = Harness.runCases(cases, M)
		caseFailures[entry.key] = t.failures
		if #t.failures > 0 then
			for _, f in t.failures do
				table.insert(violations, `插桩版用例失败（{entry.mod}）: {f}`)
			end
		end
	end

	-- 汇总
	for _, entry in CERT_MODULES do
		local plan = plans[entry.key] :: Instrumented
		local collector = hits[entry.key] :: { [number]: number }
		local lines = splitLines(fs.readFile(entry.src))
		local missed: { { line: number, text: string, explained: string? } } = {}
		local hitCount = 0
		for _, lineNo in plan.executable do
			if collector[lineNo] ~= nil then
				hitCount += 1
			else
				local key = `{entry.src}:{lineNo}`
				local reason = explained[key]
				table.insert(missed, {
					line = lineNo,
					text = trim(lines[lineNo] or ""),
					explained = reason,
				})
				if reason == nil then
					table.insert(
						violations,
						`未覆盖且无理由（{entry.mod}）: {key} —— {trim(lines[lineNo] or "")}`
					)
				end
			end
		end

		-- R21 的交叉校验：插桩版的每个导出函数的定义行，必须被分类过（可执行或明确跳过）
		local functionLines: { { line: number, name: string, classified: boolean } } = {}
		local function scan(container: any, prefix: string)
			for key, value in container do
				if type(value) == "function" then
					local line = fnLine(value)
					if line ~= nil then
						local classified = collector[line] ~= nil
							or table.find(plan.executable, line) ~= nil
							or (function()
								for _, skip in plan.skipped do
									if skip.line == line then
										return true
									end
								end
								return false
							end)()
						table.insert(
							functionLines,
							{ line = line, name = `{prefix}{tostring(key)}`, classified = classified }
						)
						if not classified then
							table.insert(
								violations,
								`R21 交叉校验失败（{entry.mod}）: 函数 {prefix}{tostring(key)} 的定义行 {line} 未被插桩器分类`
							)
						end
					end
				end
			end
		end
		scan(plainModules[entry.key], "")

		local hash = 0
		local source = fs.readFile(entry.src)
		for i = 1, #source do
			hash = bit32.bxor(bit32.lshift(hash, 5) + hash + (string.byte(source, i) :: number), 0)
		end

		local skippedList: { { line: number, reason: string, text: string } } = {}
		for _, skip in plan.skipped do
			table.insert(skippedList, {
				line = skip.line,
				reason = skip.reason,
				text = trim(lines[skip.line] or ""),
			})
		end
		table.sort(skippedList, function(a, b)
			return a.line < b.line
		end)

		table.insert(reports, {
			mod = entry.mod,
			file = entry.src,
			sourceHash = hash,
			lineCount = #lines,
			candidates = plan.candidates,
			executable = #plan.executable,
			hit = hitCount,
			missed = missed,
			skipped = skippedList,
			functionLines = functionLines,
			cases = caseCounts[entry.key] or 0,
			caseFailures = caseFailures[entry.key] or {},
		})
	end

	return reports, violations
end

-- ---------- 报告 ----------
local function writeReports(reports: { ModuleReport }): ()
	if not fs.isDir(COVERAGE_DIR) then
		fs.writeDir(COVERAGE_DIR)
	end
	for _, report in reports do
		local payload = {
			module = report.mod,
			file = report.file,
			sourceHash = report.sourceHash,
			lines = {
				total = report.lineCount,
				candidates = report.candidates,
				executable = report.executable,
				hit = report.hit,
				missed = report.executable - report.hit,
			},
			missed = report.missed,
			nonExecutable = report.skipped,
			functions = report.functionLines,
			cases = report.cases,
			caseFailures = report.caseFailures,
			instruments = {
				tool = "scripts/coverage.luau",
				method = "source-instrumentation + bracket-depth + compile-oracle",
				note = "可执行行 = 通过编译验证且位于括号深度 0 的语句行；nonExecutable 逐行给出其余归类理由",
			},
		}
		fs.writeFile(`{COVERAGE_DIR}/{report.mod}.json`, serde.encode("json", payload))
	end
end

-- ---------- 自检：插桩器自己的测试（CERT.md §7.3）----------
local function selftest(): boolean
	local failures: { string } = {}
	local expect = function(cond: boolean, what: string)
		if not cond then
			table.insert(failures, what)
		end
	end
	local set = function(list: { number }): { [number]: boolean }
		local out: { [number]: boolean } = {}
		for _, v in list do
			out[v] = true
		end
		return out
	end

	-- S1：正常函数体 —— 每一行语句都该被插桩
	local sample = table.concat({
		"local M = {}",
		"",
		"-- 注释不该被插",
		"function M.Add(a, b)",
		"\tlocal sum = a + b",
		"\tif sum > 10 then",
		"\t\treturn sum * 2",
		"\tend",
		"\treturn sum",
		"end",
		"",
		"M.Const = {",
		"\ta = 1,",
		"\tb = 2,",
		"}",
		"",
		"return M",
	}, "\n")
	local plan = Instrument(sample, "sample")
	local exec = set(plan.executable)
	expect(exec[1] == true, "S1: `local M = {}` 应可插")
	expect(exec[4] == true, "S1: 函数定义行应可插")
	expect(exec[5] == true, "S1: 函数体语句应可插")
	expect(exec[6] == true, "S1: `if ... then` 应可插")
	expect(exec[7] == true, "S1: 分支内语句应可插")
	expect(exec[8] ~= true, "S1: `end` 不得被插")
	expect(exec[9] == true, "S1: `return sum` 应可插")
	expect(exec[11] ~= true, "S1: 空行不得被插")
	expect(exec[12] == true, "S1: 多行表的首行（`M.Const = {`）是可执行语句")
	expect(
		exec[13] ~= true,
		"S1: 多行表的字段行不得被插（在构造器内部，不是语句边界）"
	)
	expect(exec[14] ~= true, "S1: 多行表字段行不得被插")
	expect(exec[15] ~= true, "S1: `}` 不得被插")
	expect(exec[3] ~= true, "S1: 注释行不得被插")
	expect(exec[2] ~= true, "S1: 空行不得被插")

	-- S2：插桩后的文本行数与原文一致（行号不位移 —— 报告与 debug.info 都靠它）
	local instrumentedLines = splitLines(plan.text)
	expect(#instrumentedLines == #splitLines(sample), "S2: 插桩不得改变行数")
	expect(
		string.find(plan.text, "__cov.HIT(4);", 1, true) ~= nil,
		"S2: 前缀样式应为 __cov.HIT(<行号>);"
	)

	-- S3：字符串里的 `--` 不得被当成注释而漏插（宽松预筛 + 编译器裁判）
	local tricky = table.concat({
		'local msg = "not a -- comment"',
		"local n = #msg",
		"return msg, n",
	}, "\n")
	local trickyPlan = Instrument(tricky, "tricky")
	expect(#trickyPlan.executable == 3, `S3: 三行都可插（实到 {#trickyPlan.executable}）`)

	-- S4：块注释内部的行不得被插（含 --[=[ 级别）
	local blocky = table.concat({
		"local x = 1",
		"--[=[",
		"这行在块注释里 require(script.Nope)",
		"内容里还有 ]] 之类的字样",
		"]=]",
		"return x",
	}, "\n")
	local blockyPlan = Instrument(blocky, "blocky")
	local blockyExec = set(blockyPlan.executable)
	expect(blockyExec[1] == true, "S4: 块注释前的语句应可插")
	expect(blockyExec[3] ~= true, "S4: 块注释内部不得被插")
	expect(blockyExec[5] ~= true, "S4: 块注释结束行不得被插")
	expect(blockyExec[6] == true, "S4: 块注释之后的语句应可插")

	-- S5：编译裁判必须真的在拦 —— 假编译器只拒"单行试编译"，于是可执行集合应为空
	local rejectSingle: (string, string) -> (boolean, string) = function(text)
		if select(2, string.gsub(text, "HIT%(", "")) == 1 then
			return false, "单行试编译被拒"
		end
		return true, ""
	end
	local planNever = Instrument(sample, "never", rejectSingle)
	expect(
		#planNever.executable == 0,
		"S5: 裁判全拒时，可执行集合必须为空（不许绕过裁判）"
	)
	expect(#planNever.skipped >= planNever.candidates, "S5: 被拒的行要留下理由")

	-- S6：插桩器发现"合起来编不过"时必须报错（而不是输出一份假覆盖表）
	local jointFails: (string, string) -> (boolean, string) = function(text)
		if select(2, string.gsub(text, "; ", "")) > 1 then
			return false, "合起来编不过"
		end
		return true, ""
	end
	local jointOk6 = pcall(function()
		Instrument(tricky, "joint", jointFails)
	end)
	expect(
		jointOk6 == false,
		"S6: 整体编译失败必须抛错（插桩器 bug 不得被静默当成 0 覆盖）"
	)

	-- S7：类型定义是编译期的东西，不算可执行语句（CoreTypes 会遇到）
	local withType = table.concat({
		"export type T = {",
		"\tcode: string,",
		"}",
		"local function f()",
		"\treturn 1",
		"end",
		"return f",
	}, "\n")
	local typePlan = Instrument(withType, "types")
	local typeExec = set(typePlan.executable)
	expect(typeExec[1] ~= true, "S7: 类型声明行不算可执行语句")
	expect(typeExec[2] ~= true, "S7: 类型定义内部不算可执行语句")
	expect(typeExec[3] ~= true, "S7: 类型定义的 } 不算可执行语句")
	expect(typeExec[4] == true, "S7: 类型定义之后的普通语句仍应可插")
	expect(typeExec[7] == true, "S7: 文件末尾的 return 仍应可插")

	-- S8（回归）：表构造器的字段行不得被当成语句。编译器会把它当成数组元素而**放行** ——
	-- 这是本工具修过的真 bug（R21 的失效模式），所以除了分类断言，再加一条**行为级**断言：
	-- 插桩不得改变表的内容（否则“覆盖到了”是拿改了语义的代码换来的）。
	local ctor = table.concat({
		"local t = {",
		"\ta = 1,",
		"\tb = 2,",
		"}",
		"return t",
	}, "\n")
	local ctorPlan = Instrument(ctor, "ctor")
	local ctorExec = set(ctorPlan.executable)
	expect(ctorExec[1] == true, "S8: 构造器首行是可执行语句")
	expect(ctorExec[2] ~= true, "S8: 构造器字段行不得被插（否则会给表注入数组元素）")
	expect(ctorExec[3] ~= true, "S8: 构造器字段行不得被插")
	expect(ctorExec[4] ~= true, "S8: 构造器的 } 不得被插")
	expect(ctorExec[5] == true, "S8: 构造器之后的语句仍应可插")
	local ctorLoaded = loadstring(ctorPlan.text, "ctor")
	if ctorLoaded ~= nil then
		-- 注入一个空的收集器：这里只关心“表有没有被注入数组元素”，不关心命中数
		setfenv(ctorLoaded, setmetatable({ __cov = { HIT = function() end } }, { __index = _G }))
		local built = ctorLoaded()
		expect(#built == 0, `S8: 插桩不得给表注入数组元素（#t 应为 0，实到 {#built}）`)
		expect(built.a == 1 and built.b == 2, "S8: 插桩不得改变构造器的字段值")
	else
		table.insert(failures, "S8: 插桩后的构造器样例应能加载")
	end

	if #failures > 0 then
		for _, f in failures do
			print(`[selftest] 失败: {f}`)
		end
		return false
	end
	print(
		"[selftest] 通过：S1 语句/块尾/多行表 · S2 行号不位移 · S3 字符串里的 `--` · S4 块注释级别 · S5 编译裁判不可绕过 · S6 整体失败必报错 · S7 类型块 · S8 构造器字段行（回归）"
	)
	return true
end

-- ---------- CLI ----------
local flags = { quiet = false }
for _, arg in process.args do
	if arg == "--quiet" then
		flags.quiet = true
	elseif arg == "--selftest" then
		process.exit(if selftest() then 0 else 1)
	end
end

local reports, violations = coverageRun()
writeReports(reports)

if not flags.quiet then
	print(string.format("%-14s %-10s %-10s %-8s %s", "MODULE", "EXECUTABLE", "HIT", "MISSED", "CASES"))
	for _, report in reports do
		print(
			string.format(
				"%-14s %-10d %-10d %-8d %s",
				report.mod,
				report.executable,
				report.hit,
				report.executable - report.hit,
				`{report.cases}`
			)
		)
	end
	print("")
	local totalExec, totalHit = 0, 0
	for _, report in reports do
		totalExec += report.executable
		totalHit += report.hit
	end
	print(
		`门禁 12（statement 覆盖）：{totalHit}/{totalExec} = {string.format(
			"%.1f",
			totalHit / math.max(totalExec, 1) * 100
		)}% · 违规 {#violations} · 报告写入 {COVERAGE_DIR}/`
	)
	for _, v in violations do
		print(`  {v}`)
	end
end

if #violations > 0 then
	print(`FAIL: 结构覆盖未达标或插桩器校验失败（{#violations} 处）`)
	process.exit(1)
end
