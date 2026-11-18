--!strict
-- Carbon 依赖方向门禁（.plan/CARBON.md §3）。
--
-- 19 个组件分 4 层。本门禁把「只许向下依赖、同层走端口」变成可执行约束：
--
--   UPWARD        require 了更高层的组件
--   SAME_LAYER    在 `Integration/` 之外 require 了同层组件
--   UNDECLARED    require 了清单里没有声明的（更低层 / 同层）组件
--   PORT_ONLY     声明为 ports 的组件在 `Integration/` 之外被 require
--   OUTSIDE       require 解析到了任何组件之外（项目配置、遗留垫片、仓库别处）
--   THIRDPARTY    require 里出现只作参考的第三方库名字
--   UNTRACEABLE   路径式 / 动态 require：无法静态判定去向
--   ENGINE_OUTSIDE_HOST  组件的宿主目录之外出现引擎字面（规则 H1，所有层）
--   CORE_REQUIRES_HOST   组件的核心 require 了自己的宿主目录（规则 H3）
--   HOST_CROSS           require 了别的组件的宿主目录（规则 H4）
--   STRAY         组件根目录下出现清单外的条目（防止第 20 个组件悄悄长出来）
--   MISSING       清单里的组件没有目录
--   MANIFEST      清单自身不自洽（依赖不存在 / deps 指向同层或更高层 / ports 指向更高层）
--
-- 宿主目录（.plan/CARBON.md §3.2）：每个组件唯一可以出现引擎 API 的地方。默认叫 `Host`，
-- 清单的 `hostDirs` 可按组件改名（Deuterium 是既有的 `Runtime`）。清单的 `hostRequirable`
-- 列出宿主目录本身就是公开端口层的组件：它们不受 H3 约束，别的组件 require 它们的
-- 宿主目录也不算 H4。
--
-- 与门禁 10（cert-scope-check）的关系：那一道管「认证范围 ↔ 非认证范围」，
-- 这一道管「组件 ↔ 组件」。两者的 require 解析语义相同（N 个 Parent 向上 N-1 层）。
--
-- 用法：
--   lune run scripts/carbon-deps-check.luau             # 校验
--   lune run scripts/carbon-deps-check.luau --selftest  # 自检：证明本门禁会失败
-- 退出码：0 = 无违规；1 = 有违规 / 自检失败

local fs = require("@lune/fs")
local process = require("@lune/process")

local Manifest = require("./carbon-manifest")
local hostDirOf = Manifest.hostDirOf

type Component = Manifest.Component
type ManifestT = typeof(Manifest)
type Finding = { kind: string, where: string, detail: string }

-- ---------- 小工具 ----------
local function split(text: string, sep: string): { string }
	local out: { string } = {}
	local start = 1
	while true do
		local at = string.find(text, sep, start, true)
		if at == nil then
			table.insert(out, string.sub(text, start))
			break
		end
		table.insert(out, string.sub(text, start, at - 1))
		start = at + #sep
	end
	return out
end

local function trim(text: string): string
	return (string.gsub(text, "^%s*(.-)%s*$", "%1"))
end

local function normalize(path: string): string
	local stack: { string } = {}
	for _, part in split(path, "/") do
		if part == "" or part == "." then
			continue
		elseif part == ".." then
			table.remove(stack)
		else
			table.insert(stack, part)
		end
	end
	return table.concat(stack, "/")
end

local function dirname(path: string): string
	local last = string.find(path, "/[^/]*$")
	return if last == nil then "." else string.sub(path, 1, last - 1)
end

local function contains(list: { string }, item: string): boolean
	return table.find(list, item) ~= nil
end

-- 剥注释：行首 `--` 的整行，以及 `--[[ … ]]`（含 --[=[ … ]=]）块注释的整个区间。
-- 块注释必须处理：长注释里出现 require(...) 或引擎字面时，逐行扫描会误报——
-- 门禁不该逼人改写注释来绕开它。行尾注释仍参与扫描，不会因剥离而隐藏真违规。
-- 简化处：只识别「行首即注释」的块注释开头；串字面量里的 --[[ 不处理（病理用法）。
local function stripComments(source: string): { string }
	local out: { string } = {}
	local openEq: number? = nil -- 处于块注释内时 = 开始标记的 '=' 数
	for _, raw in split(source, "\n") do
		local line = raw
		if openEq ~= nil then
			local close = string.find(line, "]" .. string.rep("=", openEq) .. "]", 1, true)
			if close == nil then
				table.insert(out, "")
				continue
			end
			line = string.sub(line, close + 2 + openEq)
			openEq = nil
		end
		local trimmed = trim(line)
		if string.sub(trimmed, 1, 2) == "--" and string.sub(trimmed, 3, 3) == "[" then
			local eq = 0
			local i = 4
			while string.sub(trimmed, i, i) == "=" do
				eq += 1
				i += 1
			end
			if string.sub(trimmed, i, i) == "[" then
				local close = string.find(trimmed, "]" .. string.rep("=", eq) .. "]", i + 1, true)
				if close == nil then
					openEq = eq
					table.insert(out, "")
					continue
				end
				table.insert(out, string.sub(trimmed, close + 2 + eq))
				continue
			end
		end
		table.insert(out, if string.sub(trimmed, 1, 2) == "--" then "" else line)
	end
	return out
end

local function findRequires(lines: { string }): { { line: number, text: string } }
	local out: { { line: number, text: string } } = {}
	for index, line in lines do
		local start = 1
		while true do
			local at = string.find(line, "require(", start, true)
			if at == nil then
				break
			end
			-- 括号配对到与之平衡的那个 ')'：require(a(b)) 的实参不能被第一个 ')' 截断
			local depth = 1
			local i = at + 8
			while i <= #line and depth > 0 do
				local ch = string.sub(line, i, i)
				if ch == "(" then
					depth += 1
				elseif ch == ")" then
					depth -= 1
				end
				if depth > 0 then
					i += 1
				end
			end
			local text = if depth == 0 then string.sub(line, at + 8, i - 1) else string.sub(line, at + 8)
			table.insert(out, { line = index, text = text })
			start = at + 8
		end
	end
	return out
end

-- require(script.Parent…) → 仓库相对路径（无扩展名）。
-- Rojo 语义：script.Parent = 本文件所在文件夹，所以 N 个 Parent 只向上 N-1 层。
type Resolution = { kind: "resolved" | "self" | "literal" | "unknown", path: string? }

local function resolveRequire(fromFile: string, arg: string): Resolution
	local a = trim(arg)
	if a == "script" then
		return { kind = "self" }
	end
	if string.find(a, '"', 1, true) ~= nil or string.find(a, "'", 1, true) ~= nil then
		return { kind = "literal", path = a }
	end
	if a ~= "script" and string.sub(a, 1, 7) ~= "script." then
		return { kind = "unknown", path = a }
	end

	local parts = split(string.sub(a, 8), ".")
	local parents = 0
	for _, part in parts do
		if part ~= "Parent" then
			break
		end
		parents += 1
	end

	local base = dirname(fromFile)
	for _ = 2, parents do
		base = normalize(base .. "/../")
	end

	local name: { string } = {}
	for index = parents + 1, #parts do
		if parts[index] ~= "" then
			table.insert(name, parts[index])
		end
	end
	local tail = if #name == 0 then "init" else table.concat(name, "/")
	return { kind = "resolved", path = normalize(base .. "/" .. tail) }
end

-- ---------- 清单索引与自洽性 ----------
local indexCache: { [any]: { [string]: Component } } = {}
local function index(manifest: ManifestT): { [string]: Component }
	-- auditFile 对每个文件都调一次：按清单缓存，别每文件重建
	local cached = indexCache[manifest]
	if cached ~= nil then
		return cached
	end
	local byName: { [string]: Component } = {}
	for _, component in manifest.components do
		byName[component.name] = component
	end
	indexCache[manifest] = byName
	return byName
end

local function auditManifest(manifest: ManifestT): { Finding }
	local findings: { Finding } = {}
	local byName = index(manifest)
	local seen: { [string]: boolean } = {}
	for _, component in manifest.components do
		if seen[component.name] then
			table.insert(findings, { kind = "MANIFEST", where = component.name, detail = "组件名重复" })
		end
		seen[component.name] = true
		for _, dep in component.deps do
			local target = byName[dep]
			if target == nil then
				table.insert(findings, {
					kind = "MANIFEST",
					where = component.name,
					detail = `deps 指向不存在的组件 {dep}`,
				})
			elseif target.layer >= component.layer then
				table.insert(findings, {
					kind = "MANIFEST",
					where = component.name,
					detail = `deps 必须指向更低层：{dep} 在 L{target.layer}，本组件在 L{component.layer}`,
				})
			end
		end
		for _, port in component.ports do
			local target = byName[port]
			if target == nil then
				table.insert(findings, {
					kind = "MANIFEST",
					where = component.name,
					detail = `ports 指向不存在的组件 {port}`,
				})
			elseif target.layer > component.layer then
				table.insert(findings, {
					kind = "MANIFEST",
					where = component.name,
					detail = `ports 不得指向更高层：{port} 在 L{target.layer}，本组件在 L{component.layer}`,
				})
			end
		end
	end

	-- 宿主目录字段自身的合法性：写错一个名字，H1/H3/H4 会整族规则静默失效
	local m: any = manifest
	local function badHostDir(dir: any): boolean
		return type(dir) ~= "string" or dir == "" or dir == "Integration"
			or string.find(dir, "/", 1, true) ~= nil
	end
	if m.hostDir ~= nil and badHostDir(m.hostDir) then
		table.insert(findings, {
			kind = "MANIFEST",
			where = "hostDir",
			detail = "宿主目录名不合法（空 / 叫 Integration / 含斜杠）",
		})
	end
	for compName, dir in m.hostDirs or {} do
		if byName[compName] == nil then
			table.insert(findings, {
				kind = "MANIFEST",
				where = `hostDirs.{compName}`,
				detail = "覆盖指向不存在的组件",
			})
		end
		if badHostDir(dir) then
			table.insert(findings, {
				kind = "MANIFEST",
				where = `hostDirs.{compName}`,
				detail = "宿主目录名不合法（空 / 叫 Integration / 含斜杠）",
			})
		end
	end
	for _, compName in m.hostRequirable or {} do
		if byName[compName] == nil then
			table.insert(findings, {
				kind = "MANIFEST",
				where = "hostRequirable",
				detail = `不是清单里的组件：{compName}`,
			})
		end
	end
	return findings
end

-- 路径属于哪个组件（或哪个非组件条目）。返回 组件名?, 是否在 Integration/ 内, 组件下的第一级目录名?。
local function ownerOf(manifest: ManifestT, path: string): (string?, boolean, string?)
	local prefix = manifest.root .. "/"
	if string.sub(path, 1, #prefix) ~= prefix then
		return nil, false, nil
	end
	local parts = split(string.sub(path, #prefix + 1), "/")
	return parts[1], parts[2] == "Integration", parts[2]
end

local function hostRequirable(manifest: ManifestT, componentName: string): boolean
	local m: any = manifest
	return m.hostRequirable ~= nil and contains(m.hostRequirable, componentName)
end

-- ---------- 审计核心（check 与 selftest 共用同一条路径） ----------
local function auditFile(manifest: ManifestT, path: string, source: string): { Finding }
	local findings: { Finding } = {}
	local byName = index(manifest)
	local ownerName, inIntegration, ownerSub = ownerOf(manifest, path)
	local owner = if ownerName ~= nil then byName[ownerName] else nil
	if owner == nil then
		return findings -- 不属于任何组件的文件不在本门禁管辖内
	end
	local inHost = ownerSub == hostDirOf(manifest, owner.name)
	local lines = stripComments(source)

	local function report(kind: string, line: number, detail: string)
		table.insert(findings, { kind = kind, where = `{path}:{line}`, detail = detail })
	end

	local function judge(line: number, targetName: string, how: string)
		if targetName == owner.name then
			return
		end
		local target = byName[targetName]
		if target == nil then
			report("OUTSIDE", line, `{how} 指向组件之外的 {targetName}`)
			return
		end
		if target.layer > owner.layer then
			report("UPWARD", line, `{owner.name}(L{owner.layer}) → {target.name}(L{target.layer})：{how}`)
			return
		end
		local isDep = contains(owner.deps, target.name)
		local isPort = contains(owner.ports, target.name)
		if target.layer == owner.layer and not inIntegration then
			report(
				"SAME_LAYER",
				line,
				`{owner.name} → 同层的 {target.name}，只允许在 Integration/ 内：{how}`
			)
			return
		end
		if not isDep and not isPort then
			report(
				"UNDECLARED",
				line,
				`{owner.name} → {target.name} 未在清单的 deps/ports 中声明：{how}`
			)
			return
		end
		if isPort and not isDep and not inIntegration then
			report(
				"PORT_ONLY",
				line,
				`{owner.name} → {target.name} 是端口依赖，只允许在 Integration/ 内：{how}`
			)
		end
	end

	-- H3 / H4：targetSub 是被 require 的路径在目标组件下的第一级目录名。
	local function judgeHost(line: number, targetName: string, targetSub: string?, how: string)
		if byName[targetName] == nil or targetSub ~= hostDirOf(manifest, targetName) then
			return
		end
		if hostRequirable(manifest, targetName) then
			return
		end
		if targetName == owner.name then
			if not inHost then
				report(
					"CORE_REQUIRES_HOST",
					line,
					`{owner.name} 的核心不得 require 自己的 {targetSub}/，宿主实现由调用方传入：{how}`
				)
			end
		else
			report("HOST_CROSS", line, `{owner.name} 不得 require {targetName} 的 {targetSub}/：{how}`)
		end
	end

	for _, req in findRequires(lines) do
		for _, name in manifest.forbidden do
			if string.find(req.text, name, 1, true) ~= nil then
				report(
					"THIRDPARTY",
					req.line,
					`require 里出现 {name}：第三方库只作参考，不得依赖`
				)
			end
		end

		local res = resolveRequire(path, req.text)
		if res.kind == "resolved" then
			local targetPath = res.path :: string
			local targetName, _, targetSub = ownerOf(manifest, targetPath)
			if targetName == nil then
				report(
					"OUTSIDE",
					req.line,
					`require({trim(req.text)}) 解析到组件根目录之外：{targetPath}`
				)
			else
				judge(req.line, targetName, `require({trim(req.text)})`)
				judgeHost(req.line, targetName, targetSub, `require({trim(req.text)})`)
			end
		elseif res.kind == "literal" then
			report(
				"UNTRACEABLE",
				req.line,
				`路径式 require({trim(req.text)})：组件内只允许 script 相对链`
			)
		elseif res.kind == "unknown" then
			-- 形如 require(ReplicatedStorage.X.Y) / require(Root.X)：按出现的组件名判定；
			-- 一个都认不出来就是无法追溯。
			local matched = false
			for _, component in manifest.components do
				if string.find(req.text, "%f[%w_]" .. component.name .. "%f[^%w_]") ~= nil then
					matched = true
					judge(req.line, component.name, `require({trim(req.text)})`)
					-- 绝对路径解析不出目录，只能按 `<组件>.<宿主目录>` 的字面判定
					local hostDir = hostDirOf(manifest, component.name)
					local hostPattern = "%f[%w_]" .. component.name .. "%." .. hostDir .. "%f[^%w_]"
					if string.find(req.text, hostPattern) ~= nil then
						judgeHost(req.line, component.name, hostDir, `require({trim(req.text)})`)
					end
				end
			end
			for _, name in manifest.project do
				local bare = (string.gsub(name, "%.luau$", ""))
				if string.find(req.text, "%f[%w_]" .. bare .. "%f[^%w_]") ~= nil then
					matched = true
					report("OUTSIDE", req.line, `require({trim(req.text)}) 指向非组件条目 {bare}`)
				end
			end
			if not matched then
				local forbiddenHit = false
				for _, name in manifest.forbidden do
					forbiddenHit = forbiddenHit or string.find(req.text, name, 1, true) ~= nil
				end
				if not forbiddenHit then
					report("UNTRACEABLE", req.line, `require({trim(req.text)})：无法静态判定去向`)
				end
			end
		end
	end

	-- H1：引擎字面只许出现在宿主目录里。每行只报一次（报第一个命中的字面）。
	if not inHost then
		local hostDir = hostDirOf(manifest, owner.name)
		for lineNo, line in lines do
			for _, literal in manifest.engineLiterals do
				if string.find(line, literal, 1, true) ~= nil then
					report(
						"ENGINE_OUTSIDE_HOST",
						lineNo,
						`{owner.name} 在 {hostDir}/ 之外出现引擎字面 '{literal}'`
					)
					break
				end
			end
		end
	end

	return findings
end

-- ---------- 真实仓库的遍历 ----------
local function walk(dir: string, out: { string })
	for _, entry in fs.readDir(dir) do
		local full = `{dir}/{entry}`
		if fs.isDir(full) then
			walk(full, out)
		elseif string.sub(entry, -5) == ".luau" then
			table.insert(out, full)
		end
	end
end

-- 登记在册的既有违规（棘轮）：只许减少，不许新增。键 = "KIND path"，值 = 允许的条数。
-- 目的是让门禁今天就能阻断**新增**违规，而不是等旧代码全部整改完才启用。
local function readBaseline(path: string): { [string]: number }
	local out: { [string]: number } = {}
	if not fs.isFile(path) then
		return out
	end
	for _, raw in split(fs.readFile(path) :: string, "\n") do
		local line = trim(raw)
		if line ~= "" and string.sub(line, 1, 1) ~= "#" then
			local count, key = string.match(line, "^(%d+)%s+(.+)$")
			if count ~= nil and key ~= nil then
				out[key] = tonumber(count) :: number
			end
		end
	end
	return out
end

local function keyOf(finding: Finding): string
	return finding.kind .. " " .. (string.match(finding.where, "^(.-):%d+$") or finding.where)
end

local BASELINE_FILE = "scripts/carbon-deps-baseline.txt"

local function check(): number
	local findings: { Finding } = auditManifest(Manifest)

	if not fs.isDir(Manifest.root) then
		table.insert(
			findings,
			{ kind = "MISSING", where = Manifest.root, detail = "组件根目录不存在" }
		)
	else
		local known: { [string]: boolean } = {}
		for _, component in Manifest.components do
			known[component.name] = true
			if not fs.isDir(`{Manifest.root}/{component.name}`) then
				table.insert(findings, {
					kind = "MISSING",
					where = `{Manifest.root}/{component.name}`,
					detail = "清单里的组件没有目录",
				})
			end
		end
		for _, name in Manifest.project do
			known[name] = true
		end
		for _, entry in fs.readDir(Manifest.root) do
			if not known[entry] then
				table.insert(findings, {
					kind = "STRAY",
					where = `{Manifest.root}/{entry}`,
					detail = "不在组件清单里，也不是登记的项目条目",
				})
			end
		end

		local files: { string } = {}
		for _, component in Manifest.components do
			local dir = `{Manifest.root}/{component.name}`
			if fs.isDir(dir) then
				walk(dir, files)
			end
		end
		table.sort(files)
		for _, file in files do
			for _, finding in auditFile(Manifest, file, fs.readFile(file) :: string) do
				table.insert(findings, finding)
			end
		end
		print(`扫描：组件 {#Manifest.components} · 文件 {#files}`)
	end

	-- 棘轮：按 "KIND path" 分组计数，与基线比较。
	local baseline = readBaseline(BASELINE_FILE)
	local counts: { [string]: number } = {}
	for _, finding in findings do
		local key = keyOf(finding)
		counts[key] = (counts[key] or 0) + 1
	end

	local fresh: { Finding } = {}
	local tolerated = 0
	local used: { [string]: number } = {}
	for _, finding in findings do
		local key = keyOf(finding)
		used[key] = (used[key] or 0) + 1
		if used[key] <= (baseline[key] or 0) then
			tolerated += 1
		else
			table.insert(fresh, finding)
		end
	end

	local stale: { string } = {}
	for key, allowed in baseline do
		if (counts[key] or 0) < allowed then
			table.insert(stale, `{key}：基线 {allowed}，实际 {counts[key] or 0}`)
		end
	end
	table.sort(stale)

	if #fresh > 0 then
		print("")
		print(string.format("%-13s %s", "KIND", "WHERE / DETAIL"))
		for _, finding in fresh do
			print(string.format("%-13s %s", finding.kind, finding.where))
			print(string.format("%-13s   %s", "", finding.detail))
		end
	end
	if #stale > 0 then
		print("")
		print("基线已过时（违规减少了，请把基线同步调低 —— 棘轮只降不升）：")
		for _, line in stale do
			print("  " .. line)
		end
	end

	print("")
	print(
		`依赖方向门禁：新增违规 {#fresh} · 登记在册的既有违规 {tolerated} · 过时基线 {#stale}`
	)
	if #fresh == 0 and #stale == 0 then
		print("依赖方向门禁 OK")
		return 0
	end
	return 1
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

	-- 合成清单：Low(L0) · Low2(L0) · Mid(L1, deps Low, ports Peer) · Peer(L1) · High(L2)
	local synthetic: any = {
		root = "src/RS",
		components = {
			{ name = "Low", layer = 0, deps = {}, ports = { "Low2" }, core = 1 },
			{ name = "Low2", layer = 0, deps = {}, ports = {}, core = 1 },
			{ name = "Mid", layer = 1, deps = { "Low" }, ports = { "Peer" }, core = 1 },
			{ name = "Peer", layer = 1, deps = {}, ports = {}, core = 1 },
			{ name = "High", layer = 2, deps = { "Mid" }, ports = { "Low" }, core = 1 },
		},
		project = { "Configs", "Debug.luau" },
		forbidden = { "Scribe", "QuickZone" },
		engineLiterals = Manifest.engineLiterals,
		hostDir = "Host",
		hostDirs = {},
		hostRequirable = {},
		budget = Manifest.budget,
		releaseFloor = Manifest.releaseFloor,
	}

	local function kinds(path: string, source: string, manifest: any?): string
		local seen: { string } = {}
		for _, finding in auditFile(manifest or synthetic, path, source) do
			table.insert(seen, finding.kind)
		end
		table.sort(seen)
		return table.concat(seen, ",")
	end

	-- 正控：合法依赖必须 0 违规（否则门禁只会喊狼来了）
	expect(kinds("src/RS/Mid/A.luau", "local x = require(script.Parent.B)") == "", "组件内 require 合法")
	expect(
		kinds("src/RS/Mid/A.luau", "local x = require(script.Parent.Parent.Low.Api)") == "",
		"声明过的向下依赖合法"
	)
	expect(
		kinds(
			"src/RS/Mid/Integration/PeerPort.luau",
			"local x = require(script.Parent.Parent.Parent.Peer.Api)"
		) == "",
		"Integration/ 内的同层端口合法"
	)
	expect(
		kinds(
			"src/RS/High/Integration/LowPort.luau",
			"local x = require(script.Parent.Parent.Parent.Low.Api)"
		) == "",
		"Integration/ 内的向下端口合法"
	)
	expect(
		kinds("src/RS/Mid/A.luau", "-- require(script.Parent.Parent.High.Api)") == "",
		"注释行里的 require 不算"
	)

	-- 负例：每一类违规都必须被抓到
	expect(
		kinds("src/RS/Mid/A.luau", "local x = require(script.Parent.Parent.High.Api)") == "UPWARD",
		"向上依赖"
	)
	expect(
		kinds("src/RS/Mid/A.luau", "local x = require(script.Parent.Parent.Peer.Api)") == "SAME_LAYER",
		"Integration/ 之外的同层依赖"
	)
	expect(
		kinds("src/RS/High/A.luau", "local x = require(script.Parent.Parent.Low2.Api)") == "UNDECLARED",
		"未声明的向下依赖"
	)
	expect(
		kinds("src/RS/High/A.luau", "local x = require(script.Parent.Parent.Low.Api)") == "PORT_ONLY",
		"端口依赖出现在 Integration/ 之外"
	)
	expect(
		kinds("src/RS/Mid/A.luau", "local x = require(script.Parent.Parent.Configs.Flags)") == "OUTSIDE",
		"指向非组件条目"
	)
	expect(
		kinds("src/RS/Mid/A.luau", "local x = require(script.Parent.Parent.Parent.Parent.tools.x)")
			== "OUTSIDE",
		"解析到组件根目录之外"
	)
	expect(
		kinds("src/RS/Mid/A.luau", "local x = require(script.Parent.Parent.Scribe.Server)")
			== "OUTSIDE,THIRDPARTY",
		"第三方库（相对链）"
	)
	expect(
		kinds("src/RS/Mid/A.luau", "local x = require(ReplicatedStorage.QuickZone)") == "THIRDPARTY",
		"第三方库（绝对路径）"
	)
	expect(
		kinds("src/RS/Mid/A.luau", "local x = require(ReplicatedStorage.High.Api)") == "UPWARD",
		"绝对路径的向上依赖"
	)
	expect(kinds("src/RS/Mid/A.luau", 'local x = require("./y")') == "UNTRACEABLE", "路径式 require")
	expect(kinds("src/RS/Mid/A.luau", "local x = require(someTable[key])") == "UNTRACEABLE", "动态 require")
	-- 宿主目录（H1 / H3 / H4）
	local ENGINE_LINE = 'local s = game:GetService("RunService")'
	expect(
		kinds("src/RS/Low/A.luau", ENGINE_LINE) == "ENGINE_OUTSIDE_HOST",
		"H1：L0 核心触碰引擎（每行只报一次）"
	)
	expect(kinds("src/RS/Mid/A.luau", ENGINE_LINE) == "ENGINE_OUTSIDE_HOST", "H1：L1 核心触碰引擎")
	expect(
		kinds("src/RS/Mid/Integration/P.luau", ENGINE_LINE) == "ENGINE_OUTSIDE_HOST",
		"H1：Integration/ 也不行"
	)
	expect(kinds("src/RS/Mid/Host/Impl.luau", ENGINE_LINE) == "", "H1：宿主目录里可以触碰引擎")
	expect(kinds("src/RS/Low/Host/Impl.luau", ENGINE_LINE) == "", "H1：L0 的宿主目录同样可以")
	expect(kinds("src/RS/Mid/A.luau", "-- " .. ENGINE_LINE) == "", "H1：注释行不算")
	expect(
		kinds("src/RS/Mid/A.luau", "local h = require(script.Parent.Host.Impl)") == "CORE_REQUIRES_HOST",
		"H3：核心 require 自己的宿主目录"
	)
	expect(
		kinds("src/RS/Mid/Host/Impl.luau", "local c = require(script.Parent.Parent.Core)") == "",
		"H3：宿主目录 require 本组件的核心合法"
	)
	expect(
		kinds("src/RS/Mid/Host/Impl.luau", "local c = require(script.Parent.Other)") == "",
		"H3：宿主目录内部互相 require 合法"
	)
	expect(
		kinds("src/RS/Mid/Host/Impl.luau", "local x = require(script.Parent.Parent.Parent.Low.Host.Impl)")
			== "HOST_CROSS",
		"H4：宿主目录 require 别的组件的宿主目录"
	)
	expect(
		kinds("src/RS/Mid/A.luau", "local x = require(script.Parent.Parent.Low.Host.Impl)") == "HOST_CROSS",
		"H4：核心 require 别的组件的宿主目录"
	)
	expect(
		kinds("src/RS/Mid/A.luau", "local x = require(ReplicatedStorage.Low.Host.Impl)") == "HOST_CROSS",
		"H4：绝对路径写法"
	)
	expect(
		kinds("src/RS/Mid/A.luau", "local x = require(script.Parent.Parent.Low.Hostile)") == "",
		"H4：名字只是以 Host 开头的普通模块不算"
	)

	-- 宿主目录改名与「宿主目录即公开端口层」的组件（真实清单里的 Deuterium / Runtime）
	local renamed: any = table.clone(synthetic)
	renamed.hostDirs = { Low = "Runtime" }
	renamed.hostRequirable = { "Low" }
	expect(
		kinds("src/RS/Low/Runtime/Impl.luau", ENGINE_LINE, renamed) == "",
		"改名后的宿主目录可以触碰引擎"
	)
	expect(
		kinds("src/RS/Low/Host/Impl.luau", ENGINE_LINE, renamed) == "ENGINE_OUTSIDE_HOST",
		"改名后默认名字不再是宿主目录"
	)
	expect(
		kinds("src/RS/Low/A.luau", "local r = require(script.Parent.Runtime.Port)", renamed) == "",
		"hostRequirable：核心可以 require 自己的宿主目录"
	)
	expect(
		kinds("src/RS/Mid/A.luau", "local r = require(script.Parent.Parent.Low.Runtime.Port)", renamed) == "",
		"hostRequirable：别的组件可以 require 它的宿主目录"
	)
	expect(
		kinds("src/RS/Mid/A.luau", "local r = require(script.Parent.Parent.Low.Runtime.Port)") == "",
		"未改名时 Runtime 只是普通目录"
	)

		-- 块注释与括号配对（注释里的引擎字面/require 不得误报，收尾之后的代码不得漏检）
	expect(
		kinds(
			"src/RS/Mid/A.luau",
			"--[[ doc\nlocal s = game:GetService(\"X\")\nrequire(script.Parent.Parent.High.Api)\n]]"
		) == "",
		"块注释整段不算"
	)
	expect(
		kinds("src/RS/Mid/A.luau", "--[[ 块内 ]] local x = require(script.Parent.Parent.High.Api)") == "UPWARD",
		"同行收尾后仍扫描"
	)
	expect(
		kinds(
			"src/RS/Mid/A.luau",
			"--[=[ 等号块 ]=] local x = require(script.Parent.Parent.High.Api)"
		) == "UPWARD",
		"=[=] 形式收尾后仍扫描"
	)
	local reqs = findRequires(stripComments("local x = require(a(script.Parent.Parent.High.Api))"))
	expect(
		#reqs == 1 and reqs[1].text == "a(script.Parent.Parent.High.Api)",
		"require 参数按括号配对提取"
	)
	expect(
		kinds("src/RS/Mid/A.luau", "local x = require(a(script.Parent.Parent.High.Api))") == "UPWARD",
		"嵌套调用里的违规照样抓到"
	)

	-- 清单自洽性
	local function manifestKinds(mutate: (any) -> ()): number
		local copy: any = {
			root = synthetic.root,
			components = {},
			project = synthetic.project,
			forbidden = synthetic.forbidden,
			engineLiterals = synthetic.engineLiterals,
		}
		for _, component in synthetic.components do
			table.insert(copy.components, {
				name = component.name,
				layer = component.layer,
				deps = table.clone(component.deps),
				ports = table.clone(component.ports),
				core = 1,
			})
		end
		mutate(copy)
		return #auditManifest(copy)
	end
	expect(manifestKinds(function() end) == 0, "合成清单本身自洽")
	expect(manifestKinds(function(m)
		table.insert(m.components[1].deps, "High")
	end) == 1, "deps 指向更高层")
	expect(manifestKinds(function(m)
		table.insert(m.components[3].deps, "Peer")
	end) == 1, "deps 指向同层")
	expect(manifestKinds(function(m)
		table.insert(m.components[1].ports, "Mid")
	end) == 1, "ports 指向更高层")
	expect(manifestKinds(function(m)
		table.insert(m.components[1].deps, "Nope")
	end) == 1, "deps 指向不存在的组件")
	expect(manifestKinds(function(m)
		m.hostDir = "Integration"
	end) == 1, "hostDir 不得叫 Integration")
	expect(manifestKinds(function(m)
		m.hostDirs = { Nope = "Host" }
	end) == 1, "hostDirs 指向不存在的组件")
	expect(manifestKinds(function(m)
		m.hostRequirable = { "Nope" }
	end) == 1, "hostRequirable 指向不存在的组件")
	expect(#auditManifest(Manifest) == 0, "真实清单自洽")

	-- 路径语义（与门禁 10 相同）
	local r = resolveRequire("src/RS/Mid/Sub/A.luau", "script.Parent.Parent.Parent.Low.Api")
	expect(r.kind == "resolved" and r.path == "src/RS/Low/Api", "3 个 Parent 向上 2 层")

	if #failures == 0 then
		print(`[selftest] 通过：{cases} 例`)
		return true
	end
	for _, failure in failures do
		print(`[selftest] 失败：{failure}`)
	end
	return false
end

for _, arg in process.args do
	if arg == "--selftest" then
		process.exit(if selftest() then 0 else 1)
	end
end

process.exit(check())
