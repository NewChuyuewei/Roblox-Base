--!strict
-- LOC 记分板 —— 门禁 8（.plan/CARBON.md §5）。
--
-- 把 300,000 行的预算与实际行数逐区域对照。记分板**只防缩水、不奖励超额**：
-- 日常分支只报告（退出码 0）；加 `--release` 时，合计未达标或任一区域低于自身预算的
-- 70% 才阻断。
--
-- 口径（沿用 .plan/SCALE.md §2）：数物理行；只数 .luau；不含文档；不含 example/。
--
-- 行怎么归类：
--   组件核心     src/ReplicatedStorage/<组件>/** ，去掉下面两类
--   组件测试     src/ReplicatedStorage/<组件>/**/SelfTest.luau 与 tests/<组件>/**
--   集成层       src/ReplicatedStorage/<组件>/Integration/**
--   端到端测试   tests/** 中不属于任何单个组件的部分
--   工具         scripts/**
--   （不计入）   清单里登记的项目条目（Configs、Debug.luau）—— 单独列出，避免被误读成进度
--
-- 用法：
--   lune run scripts/loc-budget.luau             # 报告
--   lune run scripts/loc-budget.luau --release   # release 分支：不达标则阻断
--   lune run scripts/loc-budget.luau --selftest  # 自检
-- 退出码：0 = 报告完成 / 达标；1 = release 不达标 / 自检失败

local fs = require("@lune/fs")
local process = require("@lune/process")

local Manifest = require("./carbon-manifest")

type Row = { area: string, actual: number, budget: number }

-- ---------- 纯函数（自检直接测它们） ----------

-- 物理行数：与 `wc -l` 一致，但末行没有换行符时也算一行。
local function countLines(text: string): number
	if text == "" then
		return 0
	end
	local _, newlines = string.gsub(text, "\n", "")
	return if string.sub(text, -1) == "\n" then newlines else newlines + 1
end

-- 仓库相对路径 → 归到哪个桶。返回 桶种类, 组件名?
--   "core" | "test" | "integration" | "e2e" | "tools" | "project" | "ignore"
local function classify(manifest: typeof(Manifest), path: string): (string, string?)
	if string.sub(path, -5) ~= ".luau" then
		return "ignore", nil
	end
	local known: { [string]: boolean } = {}
	for _, component in manifest.components do
		known[component.name] = true
	end

	local rootPrefix = manifest.root .. "/"
	if string.sub(path, 1, #rootPrefix) == rootPrefix then
		local rest = string.sub(path, #rootPrefix + 1)
		local first = string.match(rest, "^([^/]+)") :: string
		if not known[first] then
			return "project", nil
		end
		if string.match(path, "/SelfTest%.luau$") ~= nil then
			return "test", first
		end
		if string.match(rest, "^[^/]+/Integration/") ~= nil then
			return "integration", first
		end
		return "core", first
	end
	if string.sub(path, 1, 6) == "tests/" then
		local first = string.match(string.sub(path, 7), "^([^/]+)/")
		if first ~= nil and known[first] then
			return "test", first
		end
		return "e2e", nil
	end
	if string.sub(path, 1, 8) == "scripts/" then
		return "tools", nil
	end
	return "ignore", nil
end

-- 预算行：每个组件的核心、每层的测试、集成层、端到端、工具。
local function budgetRows(manifest: typeof(Manifest)): ({ Row }, number)
	local rows: { Row } = {}
	local sum = 0
	for _, component in manifest.components do
		table.insert(rows, { area = `core:{component.name}`, actual = 0, budget = component.core })
		sum += component.core
	end
	for layer = 0, 3 do
		local budget = manifest.budget.testsByLayer[layer]
		table.insert(rows, { area = `tests:L{layer}`, actual = 0, budget = budget })
		sum += budget
	end
	table.insert(rows, { area = "integration", actual = 0, budget = manifest.budget.integration })
	table.insert(rows, { area = "e2e", actual = 0, budget = manifest.budget.endToEnd })
	table.insert(rows, { area = "tools", actual = 0, budget = manifest.budget.tools })
	sum += manifest.budget.integration + manifest.budget.endToEnd + manifest.budget.tools
	return rows, sum
end

-- 把 { 路径 → 行数 } 累加进预算行；返回 行表, 合计, 不计入的项目条目行数。
local function tally(manifest: typeof(Manifest), lineCounts: { [string]: number }): ({ Row }, number, number)
	local rows = budgetRows(manifest)
	local byArea: { [string]: Row } = {}
	for _, row in rows do
		byArea[row.area] = row
	end
	local layerOf: { [string]: number } = {}
	for _, component in manifest.components do
		layerOf[component.name] = component.layer
	end

	local total, project = 0, 0
	for path, lines in lineCounts do
		local kind, component = classify(manifest, path)
		local area: string? = nil
		if kind == "core" then
			area = `core:{component :: string}`
		elseif kind == "test" then
			area = `tests:L{layerOf[component :: string]}`
		elseif kind == "integration" or kind == "e2e" or kind == "tools" then
			area = kind
		elseif kind == "project" then
			project += lines
		end
		if area ~= nil then
			byArea[area].actual += lines
			total += lines
		end
	end
	return rows, total, project
end

-- release 判定：合计达到 total，且每个区域达到自身预算的 floor。返回不达标的原因。
local function releaseProblems(manifest: typeof(Manifest), rows: { Row }, total: number): { string }
	local problems: { string } = {}
	if total < manifest.budget.total then
		table.insert(problems, `合计 {total} < {manifest.budget.total}`)
	end
	for _, row in rows do
		if row.actual < row.budget * manifest.releaseFloor then
			table.insert(
				problems,
				`{row.area}：{row.actual} < {manifest.releaseFloor * 100}% × {row.budget}`
			)
		end
	end
	return problems
end

-- ---------- 真实仓库 ----------
local function walk(dir: string, out: { [string]: number })
	if not fs.isDir(dir) then
		return
	end
	for _, entry in fs.readDir(dir) do
		local full = `{dir}/{entry}`
		if fs.isDir(full) then
			walk(full, out)
		elseif string.sub(entry, -5) == ".luau" then
			out[full] = countLines(fs.readFile(full) :: string)
		end
	end
end

local function percent(actual: number, budget: number): string
	return string.format("%5.1f%%", if budget == 0 then 0 else actual / budget * 100)
end

local function report(release: boolean): number
	local counts: { [string]: number } = {}
	walk(Manifest.root, counts)
	walk("tests", counts)
	walk("scripts", counts)

	local rows, total, project = tally(Manifest, counts)

	print(string.format("%-18s %9s %9s %7s  %s", "AREA", "ACTUAL", "BUDGET", "RATIO", "ROLE"))
	local roleOf: { [string]: string } = {}
	for _, component in Manifest.components do
		roleOf[`core:{component.name}`] = component.role
	end
	for _, row in rows do
		local ratio = percent(row.actual, row.budget)
		print(
			string.format(
				"%-18s %9d %9d %7s  %s",
				row.area,
				row.actual,
				row.budget,
				ratio,
				roleOf[row.area] or ""
			)
		)
	end
	print(string.rep("-", 46))
	print(
		string.format(
			"%-18s %9d %9d %7s",
			"TOTAL",
			total,
			Manifest.budget.total,
			percent(total, Manifest.budget.total)
		)
	)
	print("")
	print(
		`不计入：项目条目（{table.concat(Manifest.project, "、")}）{project} 行；example/ 与文档不统计`
	)

	local problems = releaseProblems(Manifest, rows, total)
	if release then
		if #problems > 0 then
			print("")
			print(`门禁 8（release）不达标：{#problems} 项`)
			for _, problem in problems do
				print("  " .. problem)
			end
			return 1
		end
		print("门禁 8（release）达标")
		return 0
	end
	print(`门禁 8（日常，仅报告）：距 release 线还有 {#problems} 项未达标`)
	return 0
end

-- ---------- 自检 ----------
local function selftest(): boolean
	local failures: { string } = {}
	local cases = 0
	local function expect(cond: boolean, what: string)
		cases += 1
		if not cond then
			table.insert(failures, what)
		end
	end

	-- 行数
	expect(countLines("") == 0, "空文件 0 行")
	expect(countLines("a\n") == 1, "一行带换行")
	expect(countLines("a") == 1, "一行不带换行")
	expect(countLines("a\nb\n\n") == 3, "空行也算")
	expect(countLines("a\nb") == 2, "末行无换行")

	-- 归类
	local function kindOf(path: string): string
		local kind, component = classify(Manifest, path)
		return if component ~= nil then `{kind}:{component}` else kind
	end
	expect(kindOf("src/ReplicatedStorage/Platinum/Vec.luau") == "core:Platinum", "组件核心")
	expect(
		kindOf("src/ReplicatedStorage/Deuterium/Net/Core/SelfTest.luau") == "test:Deuterium",
		"组件内 SelfTest"
	)
	expect(
		kindOf("src/ReplicatedStorage/Mercury/Integration/DrPort.luau") == "integration:Mercury",
		"集成层"
	)
	expect(
		kindOf("src/ReplicatedStorage/Mercury/Sub/Integration/X.luau") == "core:Mercury",
		"只有顶层 Integration/ 算集成层"
	)
	expect(kindOf("src/ReplicatedStorage/Configs/Deuterium/init.luau") == "project", "项目条目不计入")
	expect(kindOf("src/ReplicatedStorage/Debug.luau") == "project", "遗留垫片不计入")
	expect(kindOf("tests/Platinum/Vec.luau") == "test:Platinum", "tests/<组件>/")
	expect(kindOf("tests/run.luau") == "e2e", "tests/ 顶层算端到端")
	expect(kindOf("tests/cert/run.luau") == "e2e", "tests/ 下的非组件目录算端到端")
	expect(kindOf("scripts/coverage.luau") == "tools", "工具")
	expect(kindOf("src/ReplicatedStorage/Platinum/README.md") == "ignore", "文档不计")
	expect(kindOf("example/src/ReplicatedStorage/Scribe/init.luau") == "ignore", "example/ 不计")

	-- 预算自洽：各行之和必须等于清单声明的总数（防止改一处漏一处）
	local _, sum = budgetRows(Manifest)
	expect(
		sum == Manifest.budget.total,
		`预算各行之和 {sum} 必须等于 total {Manifest.budget.total}`
	)

	-- 累加
	local rows, total, project = tally(Manifest, {
		["src/ReplicatedStorage/Platinum/Vec.luau"] = 100,
		["src/ReplicatedStorage/Platinum/SelfTest.luau"] = 40,
		["tests/Neon/Print.luau"] = 5,
		["src/ReplicatedStorage/Mercury/Integration/DrPort.luau"] = 7,
		["src/ReplicatedStorage/Debug.luau"] = 21,
		["tests/run.luau"] = 3,
		["scripts/x.luau"] = 2,
		["README.md"] = 999,
	})
	local got: { [string]: number } = {}
	for _, row in rows do
		got[row.area] = row.actual
	end
	expect(got["core:Platinum"] == 100, "核心累加")
	expect(got["tests:L0"] == 45, "同层的测试合并（Platinum 的 SelfTest + tests/Neon）")
	expect(got["integration"] == 7 and got["e2e"] == 3 and got["tools"] == 2, "其余三桶")
	expect(total == 157 and project == 21, "合计不含项目条目与文档")

	-- release 判定必须会失败，也必须会通过
	expect(#releaseProblems(Manifest, rows, total) > 0, "远低于预算时必须不达标")
	local full, fullTotal = budgetRows(Manifest)
	for _, row in full do
		row.actual = row.budget
	end
	expect(#releaseProblems(Manifest, full, fullTotal) == 0, "恰好达到预算时达标")
	for _, row in full do
		row.actual = math.ceil(row.budget * Manifest.releaseFloor)
	end
	local atFloor = releaseProblems(Manifest, full, fullTotal)
	expect(#atFloor == 0, "每区域恰在 70% 线上、合计达标时达标")
	full[1].actual = math.floor(full[1].budget * Manifest.releaseFloor) - 1
	expect(#releaseProblems(Manifest, full, fullTotal) == 1, "单个区域跌破 70% 即不达标")
	expect(#releaseProblems(Manifest, full, fullTotal - 1) == 2, "合计差 1 行也不达标")

	if #failures == 0 then
		print(
			`[selftest] 通过：{cases} 例（行数 5 · 归类 12 · 预算自洽 1 · 累加 4 · release 判定 5）`
		)
		return true
	end
	for _, failure in failures do
		print(`[selftest] 失败：{failure}`)
	end
	return false
end

local release = false
for _, arg in process.args do
	if arg == "--selftest" then
		process.exit(if selftest() then 0 else 1)
	elseif arg == "--release" then
		release = true
	end
end

process.exit(report(release))
