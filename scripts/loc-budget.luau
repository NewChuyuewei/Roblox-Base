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
-- 第二张表按组件的标准形状（.plan/CARBON.md §3.3）再分一次，只报告、不设门槛：
--   PURE         不碰引擎的核心：组件内除去下面三类
--   HOST         宿主目录（默认 Host/，Deuterium 是 Runtime/）—— 预算上仍算在组件核心里
--   INTEGRATION  顶层 Integration/
--   TEST         SelfTest.luau（在哪个目录都算）与 tests/<组件>/**
-- HOST% = HOST ÷ (PURE + HOST)：组件核心里有多少行贴着引擎、因而无头测不到。
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
type Shape = { name: string, pure: number, host: number, integration: number, test: number }

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

-- 组件的宿主目录名：默认取 hostDir，个别组件在 hostDirs 里改名。
local function hostDirOf(manifest: typeof(Manifest), componentName: string): string
	local m: any = manifest
	local override = if m.hostDirs ~= nil then m.hostDirs[componentName] else nil
	return override or m.hostDir or "Host"
end

-- 仓库相对路径 → 在组件标准形状里属于哪一列。返回 列, 组件名?
--   "pure" | "host" | "integration" | "test" | "none"
-- 与 classify 的关系：classify 的 "core" 在这里拆成 pure 与 host，其余一一对应。
local function shapeOf(manifest: typeof(Manifest), path: string): (string, string?)
	local kind, component = classify(manifest, path)
	if component == nil or kind == "e2e" or kind == "tools" then
		return "none", nil
	end
	if kind ~= "core" then
		return kind, component
	end
	local rest = string.sub(path, #manifest.root + 2)
	local sub = string.match(rest, "^[^/]+/([^/]+)/")
	if sub == hostDirOf(manifest, component) then
		return "host", component
	end
	return "pure", component
end

-- 把 { 路径 → 行数 } 按组件 × 形状累加；行的顺序与清单一致。
local function shapeTally(manifest: typeof(Manifest), lineCounts: { [string]: number }): { Shape }
	local shapes: { Shape } = {}
	local byName: { [string]: any } = {}
	for _, component in manifest.components do
		local shape: Shape = { name = component.name, pure = 0, host = 0, integration = 0, test = 0 }
		table.insert(shapes, shape)
		byName[component.name] = shape
	end
	for path, lines in lineCounts do
		local column, component = shapeOf(manifest, path)
		if component ~= nil then
			byName[component][column] += lines
		end
	end
	return shapes
end

-- 宿主目录占组件核心（pure + host）的比例，0–1；核心为空时是 0。
local function hostShare(shape: Shape): number
	local core = shape.pure + shape.host
	return if core == 0 then 0 else shape.host / core
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

	print("")
	print("组件形状（只报告；HOST 在预算上算进上表的 core:<组件>）")
	local header = { "COMPONENT", "PURE", "HOST", "INTEGRATION", "TEST", "HOST%" }
	print(string.format("%-12s %8s %8s %12s %8s %7s", table.unpack(header)))
	local sum: Shape = { name = "ALL", pure = 0, host = 0, integration = 0, test = 0 }
	local shapes = shapeTally(Manifest, counts)
	table.insert(shapes, sum)
	for _, shape in shapes do
		if shape ~= sum then
			sum.pure += shape.pure
			sum.host += shape.host
			sum.integration += shape.integration
			sum.test += shape.test
		else
			print(string.rep("-", 60))
		end
		print(
			string.format(
				"%-12s %8d %8d %12d %8d %6.1f%%",
				shape.name,
				shape.pure,
				shape.host,
				shape.integration,
				shape.test,
				hostShare(shape) * 100
			)
		)
	end

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

	-- 组件形状
	local function shapeKind(path: string): string
		local column, component = shapeOf(Manifest, path)
		return if component ~= nil then `{column}:{component}` else column
	end
	local src = "src/ReplicatedStorage/"
	expect(shapeKind(src .. "Tin/Buffer.luau") == "pure:Tin", "形状：核心")
	expect(shapeKind(src .. "Tin/Host/Clock.luau") == "host:Tin", "形状：Host/")
	expect(shapeKind(src .. "Tin/Sub/Host/X.luau") == "pure:Tin", "形状：只认顶层 Host/")
	expect(shapeKind(src .. "Tin/Host.luau") == "pure:Tin", "形状：Host 文件不算")
	expect(shapeKind(src .. "Tin/Hosting/X.luau") == "pure:Tin", "形状：目录名必须整段相等")
	expect(shapeKind(src .. "Deuterium/Runtime/Platform/A.luau") == "host:Deuterium", "形状：改名")
	expect(shapeKind(src .. "Deuterium/Host/A.luau") == "pure:Deuterium", "形状：改名后 Host/ 普通")
	expect(shapeKind(src .. "Tin/Runtime/A.luau") == "pure:Tin", "形状：别人的改名不外溢")
	expect(shapeKind(src .. "Tin/Host/SelfTest.luau") == "test:Tin", "形状：宿主内自检")
	expect(shapeKind(src .. "Tin/Integration/P.luau") == "integration:Tin", "形状：集成层")
	expect(shapeKind("tests/Tin/Buffer.luau") == "test:Tin", "形状：tests/<组件>/")
	expect(shapeKind("tests/run.luau") == "none", "形状：端到端不属于任何组件")
	expect(shapeKind("scripts/x.luau") == "none", "形状：工具不属于任何组件")
	expect(shapeKind(src .. "Debug.luau") == "none", "形状：项目条目不属于任何组件")

	local shapeCounts = {
		[src .. "Tin/Buffer.luau"] = 60,
		[src .. "Tin/Host/Clock.luau"] = 20,
		[src .. "Tin/Host/SelfTest.luau"] = 9,
		[src .. "Tin/Integration/P.luau"] = 4,
		[src .. "Deuterium/Runtime/A.luau"] = 30,
		[src .. "Deuterium/Core/B.luau"] = 10,
		["tests/Tin/Buffer.luau"] = 6,
		["tests/run.luau"] = 3,
	}
	local shapes = shapeTally(Manifest, shapeCounts)
	local shapeByName: { [string]: Shape } = {}
	for _, shape in shapes do
		shapeByName[shape.name] = shape
	end
	local tin, deuterium = shapeByName.Tin, shapeByName.Deuterium
	expect(#shapes == #Manifest.components, "形状：每个组件一行")
	expect(tin.pure == 60 and tin.host == 20, "形状：核心与宿主目录分开累加")
	expect(tin.integration == 4 and tin.test == 15, "形状：集成层与自检分开累加")
	expect(deuterium.pure == 10 and deuterium.host == 30, "形状：改名的宿主目录累加")
	expect(hostShare(tin) == 0.25 and hostShare(deuterium) == 0.75, "形状：宿主目录占比")
	expect(hostShare(shapeByName.Neon) == 0, "形状：空组件的占比是 0 而不是 NaN")

	-- 两张表必须对得上：pure + host = 预算表的 core，其余两列各自求和后相等
	local budgetByArea: { [string]: number } = {}
	for _, row in (tally(Manifest, shapeCounts)) do
		budgetByArea[row.area] = row.actual
	end
	local integrationSum, mismatched = 0, 0
	for _, shape in shapes do
		integrationSum += shape.integration
		if shape.pure + shape.host ~= budgetByArea[`core:{shape.name}`] then
			mismatched += 1
		end
	end
	expect(mismatched == 0, "形状：pure + host 等于预算表的 core")
	expect(integrationSum == budgetByArea["integration"], "形状：集成层合计与预算表一致")

	if #failures == 0 then
		print(
			`[selftest] 通过：{cases} 例（行数 5 · 归类 12 · 预算自洽 1 · 累加 4 · release 判定 5 · 形状 22）`
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
