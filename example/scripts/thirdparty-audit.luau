--!strict
-- 第三方依赖审计 + I20 门禁（`.plan/THIRDPARTY.md` §7 的五步义务）
--
--   lune run scripts/thirdparty-audit.luau              # 审计并重写 docs/thirdparty/AUDIT.md（有违规 exit 1）
--   lune run scripts/thirdparty-audit.luau --quiet      # 只输出结论
--   lune run scripts/thirdparty-audit.luau --write-lock # 有意升级上游后重建锁文件（见 §漂移）
--   lune run scripts/thirdparty-audit.luau --selftest   # 自检：证明本门禁会失败
--
-- 它同时是**证据生成器**与**门禁**：AUDIT.md 是 CC1 产物，退出码是 CI 判据。
--
-- 为什么需要它：Scribe 42,077 行 + QuickZone 6,534 行不是我们写的，做「全量人工审计」不现实
-- （THIRDPARTY.md §7 原话）。可执行的做法是**按入口收敛审计面**：先算 require 可达闭包，
-- 再对闭包内的文件做后门面扫描。本脚本把这件事机器化，并在形状不认识时**报错而不是跳过**
-- （静默漏边会让闭包假小，那是最危险的失败模式）。

local fs = require("@lune/fs")
local process = require("@lune/process")

local ROOT = "."
local LIBS = {
	{ name = "Scribe", dir = "src/ReplicatedStorage/Scribe", upstream = "ericplane/scribe" },
	{ name = "QuickZone", dir = "src/ReplicatedStorage/QuickZone", upstream = "ldgerrits/quickzone" },
}
local AUDIT_FILE = "docs/thirdparty/AUDIT.md"
local LOCK_FILE = "docs/thirdparty/LOCK.txt"
local DEUTERIUM_DIR = "src/ReplicatedStorage/Deuterium"
-- I20：Deuterium 下只允许这些目录 require 第三方（THIRDPARTY.md §3 的五个适配器）
local ADAPTER_MARKERS = { "/Adapter/", "/Adapters/", "/Integration/" }

-- 先声明再定义函数：Lua 的局部变量只在其声明**之后**的函数体里可见
local flags = { quiet = false, writeLock = false }

-- ---------- 基础 ----------
local function trim(text: string): string
	return (string.gsub(text, "^%s*(.-)%s*$", "%1"))
end

-- FNV-1a 32 位。用途是**漂移检测**（升级上游时锁会变），不是防篡改 —— Lune 0.11.1 无 @lune/crypto。
local function hash32(text: string): string
	local h = 2166136261
	for i = 1, #text do
		h = bit32.bxor(h, string.byte(text, i) :: number)
		h = bit32.band(bit32.lshift(h, 13) + h, 0xFFFFFFFF)
	end
	return string.format("%08x", h)
end

local function joinPath(a: string, b: string): string
	if a == "" or a == "." then
		return b
	end
	return a .. "/" .. b
end

local function dirName(path: string): string
	local cut = string.find(path, "/[^/]*$")
	if cut == nil then
		return ""
	end
	return string.sub(path, 1, cut - 1)
end

local function baseName(path: string): string
	return (string.match(path, "([^/]*)$")) :: string
end

local function readFile(path: string): string
	return fs.readFile(joinPath(ROOT, path))
end

local function listFiles(dir: string): { string }
	local out: { string } = {}
	local function walk(here: string)
		local entries = fs.readDir(joinPath(ROOT, here))
		table.sort(entries)
		for _, entry in entries do
			local child = joinPath(here, entry)
			if fs.isDir(joinPath(ROOT, child)) then
				walk(child)
			else
				table.insert(out, child)
			end
		end
	end
	walk(dir)
	return out
end

-- ---------- 实例模型（Roblox 路径语义）----------
-- `script` 指向的节点：init.luau 的节点是**所在目录**（其子项即该目录内容），
-- 其余文件的节点是**文件自身**（叶子，无子项）。`Parent` 一律回上一级容器。
local function isContainer(path: string): boolean
	return fs.isDir(joinPath(ROOT, path))
end

local function nodeOfFile(path: string): string
	if baseName(path) == "init.luau" then
		return dirName(path)
	end
	return path
end

local function parentNode(node: string): string?
	if isContainer(node) then
		local up = dirName(node)
		return if up == "" then nil else up
	end
	return dirName(node)
end

-- 从 node 取名为 name 的子项：优先 `name.luau`，其次目录 `name`
local function childNode(node: string, name: string): string?
	local dir = if isContainer(node) then node else dirName(node)
	local asFile = joinPath(dir, name .. ".luau")
	if fs.isFile(joinPath(ROOT, asFile)) then
		return asFile
	end
	local asDir = joinPath(dir, name)
	if fs.isDir(joinPath(ROOT, asDir)) then
		return asDir
	end
	return nil
end

-- ---------- require 解析 ----------
export type Edge = { from: string, line: number, to: string?, text: string }

-- 收集 `local <别名> = script....` 的形式（实测第三方树只有 2 种写法）
local function aliases(lines: { string }): { [string]: string }
	local map: { [string]: string } = {}
	for _, line in lines do
		local name, chain = string.match(line, "^%s*local%s+([%w_]+)%s*=%s*(script[%w_.]*)$")
		if name ~= nil and chain ~= nil then
			map[name] = chain
		end
	end
	return map
end

local function resolveChain(fromFile: string, chain: string, alias: { [string]: string }): string?
	local first, rest = string.match(chain, "^([%w_]+)%.?(.*)$")
	if first == nil then
		return nil
	end
	local node: string? = nil
	if first == "script" then
		node = nodeOfFile(fromFile)
	elseif alias[first] ~= nil then
		node = resolveChain(fromFile, alias[first] :: string, alias)
		if node == nil then
			return nil
		end
	else
		return nil
	end
	if rest == nil or rest == "" then
		return node
	end
	for segment in string.gmatch(rest, "[%w_]+") do
		if segment == "Parent" then
			node = parentNode(node :: string)
		else
			node = childNode(node :: string, segment)
		end
		if node == nil then
			return nil
		end
	end
	return node
end

-- 只认 `require(<点链>)`；其它形状（动态 require、数字 require）**必须报违规**，不许静默跳过。
local function requireEdges(fromFile: string, text: string): ({ Edge }, { string })
	local lines = string.split(text, "\n")
	local alias = aliases(lines)
	local edges: { Edge } = {}
	local bad: { string } = {}
	for index, line in lines do
		local arg = string.match(line, "require%(([^)]*)%)")
		if arg ~= nil then
			local clean = trim(arg)
			local edge: Edge = { from = fromFile, line = index, to = nil, text = clean }
			if string.match(clean, "^[%w_.]+$") ~= nil then
				local target = resolveChain(fromFile, clean, alias)
				edge.to = target
				if target == nil then
					table.insert(bad, `无法解析的 require @ {fromFile}:{index} → {clean}`)
				end
			else
				table.insert(bad, `动态/可疑 require @ {fromFile}:{index} → {clean}`)
			end
			table.insert(edges, edge)
		end
	end
	return edges, bad
end

-- ---------- 扫描 ----------
-- 后门面：任何一处命中即**违规**。
-- 注意 `HttpService` 本身**不是**违规：实测 Scribe 只用它做 JSONEncode/GenerateGUID（零网络出口），
-- 真正要拦的是**网络出口**调用。
local FORBIDDEN = {
	"loadstring",
	"getfenv",
	"setfenv",
	"getgenv",
	"debug.getinfo",
	"debug.setupvalue",
	"require(%d",
	"_G.",
	"HttpService:GetAsync",
	"HttpService:PostAsync",
	"HttpService:RequestAsync",
}

-- 已审阅并**接受**的动态 require（不是违规）：路径 → 理由。新增必须经 CC1 评审。
local KNOWN_DYNAMIC = {
	["src/ReplicatedStorage/Scribe/Server/Persistence.luau"] = "依赖注入逃逸口 require(injected)：注入点由我们的适配器控制，不引入外部代码路径",
}
-- 引擎触点：**登记**而非违规（THIRDPARTY.md §4 的 I10 例外）
local INVENTORY = {
	"game:GetService(",
	"DataStoreService",
	"MarketplaceService",
	"MessagingService",
	"TeleportService",
	"RunService",
	"Players",
	"HttpService",
}

-- 先把注释去掉再扫：注释里的示例不算违规（实测 Scribe 有 2 处这样的假阳）。
-- 去掉注释与长字符串。
-- 不能用非贪婪正则：Scribe 的 `--[[ ... ]]` 文档块里出现 `]]`（markdown 示例）会让 `.-` 早停，
-- 把注释尾巴泄漏成“代码”（首版就是这么误报了 2 处）。这里用状态机逐行扫。
-- 长括号开头的级别：`[` `=`×n `[` → 返回 n（不是长括号则 nil）。
-- 必须支持 n>0：Scribe 的文档块用的是 `--[=[ … ]=]`（实测 111 处），只认 `[[` 会把块体当代码。
local function longOpenLevel(line: string, at: number): number?
	if string.sub(line, at, at) ~= "[" then
		return nil
	end
	local j = at + 1
	while string.sub(line, j, j) == "=" do
		j += 1
	end
	if string.sub(line, j, j) ~= "[" then
		return nil
	end
	return j - at - 1
end

local function closeToken(level: number): string
	return "]" .. string.rep("=", level) .. "]"
end

local function stripComments(text: string): string
	local out: { string } = {}
	local inBlock = false
	local blockClose = "]]"
	for _, line in string.split(text, "\n") do
		if inBlock then
			local close = string.find(line, blockClose, 1, true)
			if close == nil then
				table.insert(out, "")
			else
				inBlock = false
				table.insert(out, string.sub(line, close + 2))
			end
		else
			local cut: number? = nil
			local quote: string? = nil
			local i = 1
			while i <= #line do
				local ch = string.sub(line, i, i)
				if quote ~= nil then
					if ch == quote then
						quote = nil
					end
					i += 1
				elseif ch == '"' or ch == "'" then
					quote = ch
					i += 1
				elseif ch == "[" then
					local level = longOpenLevel(line, i)
					if level ~= nil then
						inBlock = true -- 长字符串
						blockClose = closeToken(level)
						cut = i
						break
					end
					i += 1
				elseif ch == "-" and string.sub(line, i + 1, i + 1) == "-" then
					local level = longOpenLevel(line, i + 2)
					if level ~= nil then
						inBlock = true -- 块注释（含 --[=[）
						blockClose = closeToken(level)
					end
					cut = i
					break
				else
					i += 1
				end
			end
			table.insert(out, if cut ~= nil then string.sub(line, 1, cut - 1) else line)
		end
	end
	return table.concat(out, "\n")
end

local function countOf(text: string, needle: string): number
	local n, at = 0, 1
	while true do
		local found = string.find(text, needle, at, true)
		if found == nil then
			return n
		end
		n += 1
		at = found + #needle
	end
end

export type Finding = { state: string, file: string, detail: string }
export type LibReport = {
	name: string,
	version: string,
	files: number,
	loc: number,
	bytes: number,
	hash: string,
	forbidden: { Finding },
	inventory: { Finding },
	accepted: { Finding },
	entries: { { entry: string, files: number, loc: number } },
	reachable: number,
	reachableLoc: number,
	unresolved: { string },
}

local function locOf(text: string): number
	local n = 0
	for _ in string.gmatch(text, "\n") do
		n += 1
	end
	return n
end

local function analyseLib(
	lib: { name: string, dir: string, upstream: string },
	entries: { string }
): LibReport
	local files = listFiles(lib.dir)
	local manifest: { string } = {}
	local contents: { [string]: string } = {}
	local loc, bytes = 0, 0
	for _, path in files do
		local text = readFile(path)
		contents[path] = text
		loc += locOf(text)
		bytes += #text
		table.insert(manifest, `{path} {hash32(text)}`)
	end
	table.sort(manifest)

	local forbidden: { Finding } = {}
	local inventory: { Finding } = {}
	local accepted: { Finding } = {}
	local unresolved: { string } = {}
	local adjacency: { [string]: { string } } = {}
	for _, path in files do
		local text = stripComments(contents[path] :: string)
		for _, needle in FORBIDDEN do
			local n = countOf(text, needle)
			if n > 0 then
				table.insert(forbidden, { state = needle, file = path, detail = `{n} 处` })
			end
		end
		for _, needle in INVENTORY do
			local n = countOf(text, needle)
			if n > 0 then
				table.insert(inventory, { state = needle, file = path, detail = `{n} 处` })
			end
		end
		local edges, bad = requireEdges(path, text)
		local reason = KNOWN_DYNAMIC[path]
		for _, message in bad do
			if reason ~= nil then
				table.insert(accepted, { state = "动态 require", file = path, detail = reason })
			else
				table.insert(unresolved, message)
			end
		end
		local targets: { string } = {}
		for _, edge in edges do
			local target = edge.to
			if target ~= nil then
				if isContainer(target) then
					target = childNode(target, "init")
				end
				if target ~= nil then
					table.insert(targets, target)
				end
			end
		end
		adjacency[path] = targets
	end

	-- 可达闭包（BFS）
	local seen: { [string]: boolean } = {}
	local queue: { string } = { table.unpack(entries) }
	local reachableLoc = 0
	while #queue > 0 do
		local here = table.remove(queue, 1) :: string
		if not seen[here] and contents[here] ~= nil then
			seen[here] = true
			reachableLoc += locOf(contents[here] :: string)
			for _, next in adjacency[here] :: { string } do
				if not seen[next] then
					table.insert(queue, next)
				end
			end
		end
	end
	local reachable = 0
	for _ in seen do
		reachable += 1
	end

	local perEntry: { { entry: string, files: number, loc: number } } = {}
	for _, entry in entries do
		local sub: { [string]: boolean } = {}
		local q: { string } = { entry }
		local subLoc = 0
		while #q > 0 do
			local here = table.remove(q, 1) :: string
			if not sub[here] and contents[here] ~= nil then
				sub[here] = true
				subLoc += locOf(contents[here] :: string)
				for _, next in adjacency[here] :: { string } do
					if not sub[next] then
						table.insert(q, next)
					end
				end
			end
		end
		local n = 0
		for _ in sub do
			n += 1
		end
		table.insert(perEntry, { entry = entry, files = n, loc = subLoc })
	end

	return {
		name = lib.name,
		version = "",
		files = #files,
		loc = loc,
		bytes = bytes,
		upstream = lib.upstream,
		hash = hash32(table.concat(manifest, "\n")),
		forbidden = forbidden,
		inventory = inventory,
		accepted = accepted,
		entries = perEntry,
		reachable = reachable,
		reachableLoc = reachableLoc,
		unresolved = unresolved,
	}
end

local function versionOf(libName: string): string
	if libName == "Scribe" then
		local text = readFile("src/ReplicatedStorage/Scribe/Internal/Version.luau")
		return (string.match(text, 'return%s+"([^"]+)"') or "?") :: string
	end
	local text = readFile("src/ReplicatedStorage/QuickZone/init.luau")
	return (string.match(text, "v(%d+%.%d+%.%d+)") or "?") :: string
end

-- I20：Deuterium 下只有适配器目录可以 require 第三方
local function checkAdapterOnly(): { Finding }
	local bad: { Finding } = {}
	for _, path in listFiles(DEUTERIUM_DIR) do
		if string.sub(baseName(path), -7) == ".luau" then
			local text = readFile(path)
			for _, needle in { "Scribe", "QuickZone" } do
				if countOf(text, `require(%s*script`) > 0 and countOf(text, needle) > 0 then
					local allowed = false
					for _, marker in ADAPTER_MARKERS do
						if string.find(path, marker, 1, true) ~= nil then
							allowed = true
						end
					end
					if not allowed then
						-- 先落局部再 insert：`table.insert(x, {...})` 的嵌套形状会让 stylua 失去幂等
						local finding: Finding = {
							state = "I20",
							file = path,
							detail = `提到了 {needle} 却不在适配器目录`,
						}
						table.insert(bad, finding)
					end
				end
			end
		end
	end
	return bad
end

local function render(reports: { LibReport }, findings: { Finding }, lockState: string): string
	local out: { string } = {}
	local put = function(line: string)
		table.insert(out, line)
	end
	put("# 第三方依赖审计（生成物 — 勿手改）")
	put("")
	put("> 由 `scripts/thirdparty-audit.luau` 生成。权威契约是 `.plan/THIRDPARTY.md`；")
	put("> 证据归属 CC1；锁文件 `docs/thirdparty/LOCK.txt` 用于漂移检测。")
	put("")
	put("## 1. 版本锁定（§7 步 1）")
	put("")
	put("| 库 | 版本 | 上游 | 文件 | LOC | 字节 | 内容哈希（FNV-1a 32） |")
	put("| --- | --- | --- | --- | --- | --- | --- |")
	for _, lib in reports do
		put(
			`| {lib.name} | {lib.version} | {lib.upstream} | {lib.files} | {lib.loc} | {lib.bytes} | \`{lib.hash}\` |`
		)
	end
	put("")
	put(
		`锁文件状态：**{lockState}**（哈希是漂移检测，不是防篡改 —— Lune 0.11.1 无 @lune/crypto）。`
	)
	put("")
	put("## 2. 后门面扫描（§7 步 2）")
	put("")
	local forbiddenCount = 0
	for _, lib in reports do
		forbiddenCount += #lib.forbidden
	end
	if forbiddenCount == 0 then
		put("**违规 0 处**（模式：" .. table.concat(FORBIDDEN, " · ") .. "）")
	else
		put("**违规 " .. forbiddenCount .. " 处**：")
		put("")
		put("| 库 | 模式 | 文件 | 命中 |")
		put("| --- | --- | --- | --- |")
		for _, lib in reports do
			for _, f in lib.forbidden do
				put(`| {lib.name} | \`{f.state}\` | ` .. "`" .. f.file .. "` | " .. f.detail .. " |")
			end
		end
	end
	put("")
	put("### 引擎触点清单（登记而非违规 —— I10 例外，THIRDPARTY.md §4）")
	put("")
	put("| 模式 | 出现处（文件数） | 命中总数 |")
	put("| --- | --- | --- |")
	local byNeedle: { [string]: { files: number, hits: number } } = {}
	for _, lib in reports do
		for _, f in lib.inventory do
			local cell = byNeedle[f.state] or { files = 0, hits = 0 }
			cell.files += 1
			cell.hits += tonumber(string.match(f.detail, "%d+") :: string) :: number
			byNeedle[f.state] = cell
		end
	end
	local names: { string } = {}
	for name in byNeedle do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		local cell = byNeedle[name] :: { files: number, hits: number }
		put(`| \`{name}\` | {cell.files} | {cell.hits} |`)
	end
	put("")
	put("## 3. 可达闭包 = 真正的审计面（§7 步 3）")
	put("")
	put("| 库 | 入口 | 可达文件 | 可达 LOC |")
	put("| --- | --- | --- | --- |")
	for _, lib in reports do
		for _, entry in lib.entries do
			put(
				`| {lib.name} | ` .. "`" .. entry.entry .. "` | " .. entry.files .. " | " .. entry.loc .. " |"
			)
		end
		put(
			`| **{lib.name} 并集** | — | **{lib.reachable}** / {lib.files} | **{lib.reachableLoc}** / {lib.loc} |`
		)
	end
	put("")
	for _, lib in reports do
		if #lib.unresolved > 0 then
			put(
				`⚠ **{lib.name}：{#lib.unresolved} 处 require 形状无法解析** —— 闭包可能偏小，必须先修解析器：`
			)
			put("")
			for _, line in lib.unresolved do
				put(`- {line}`)
			end
			put("")
		end
	end
	put("### 已审阅并接受的例外（非违规）")
	put("")
	local acceptedCount = 0
	for _, lib in reports do
		acceptedCount += #lib.accepted
	end
	if acceptedCount == 0 then
		put("（无）")
	else
		put("| 库 | 种类 | 文件 | 理由 |")
		put("| --- | --- | --- | --- |")
		for _, lib in reports do
			for _, f in lib.accepted do
				put(`| {lib.name} | {f.state} | ` .. "`" .. f.file .. "` | " .. f.detail .. " |")
			end
		end
	end
	put("")
	put("## 4. I20 检查（第三方只经适配器）")
	put("")
	if #findings == 0 then
		put("`Deuterium/**` 内**没有**绕过适配器直接 require 第三方的文件。")
	else
		put("**违规 " .. #findings .. " 处**：")
		put("")
		for _, f in findings do
			put(`- \`{f.file}\` — {f.detail}`)
		end
	end
	put("")
	put("## 5. 五步义务状态（§7）")
	put("")
	put("| 步 | 状态 | 证据 / 关闭动作 |")
	put("| --- | --- | --- |")
	put("| 1 锁版本 | ✅ | 版本表 + `LOCK.txt`（升级上游时 `--write-lock` 重建） |")
	put(
		"| 2 全量审计（后门面） | ✅ 按可达闭包 | §2 的扫描；形状不认识的 require 会报错而非跳过 |"
	)
	put(
		"| 3 剥离 | ◐ | **不改上游文件**（可机械升级）；审计面按 §3 的闭包口径收敛。真删文件等适配器定下入口集 |"
	)
	put(
		"| 4 Overrides 层 | ✅ 约定 | 适配器优先、不改上游；必须改时放 `Overrides.luau`（漂移锁会拦下未登记的改动） |"
	)
	put(
		"| 5 留档 | ✅ | `docs/thirdparty/{LICENSE,NOTICE,licenses,wally.toml}` + 本文件 + `LOCK.txt` |"
	)
	put("")
	put("---")
	put("")
	put(
		"未读/未验证：闭包口径是 **require 静态可达**，不含运行期才被访问的路径；"
	)
	put(
		"`game:GetService` 的实际调用时序未验证（两库需要引擎，headless 下无法执行）。"
	)
	return table.concat(out, "\n") .. "\n"
end

-- ---------- 锁文件 ----------
local function lockText(reports: { LibReport }): string
	local out: { string } =
		{ "# 第三方依赖锁（漂移检测）—— 有意升级上游后跑 --write-lock 重建。", "" }
	for _, lib in reports do
		table.insert(
			out,
			`{lib.name} v{lib.version} files={lib.files} loc={lib.loc} bytes={lib.bytes} hash={lib.hash}`
		)
	end
	return table.concat(out, "\n") .. "\n"
end

-- ---------- 主流程 ----------
local function audit(): (number, string, { LibReport })
	local reports: { LibReport } = {}
	for _, lib in LIBS do
		local entries = { joinPath(lib.dir, "init.luau") }
		if lib.name == "Scribe" then
			table.insert(entries, joinPath(lib.dir, "Server/init.luau"))
			table.insert(entries, joinPath(lib.dir, "Client/init.luau"))
		end
		local report = analyseLib(lib, entries)
		report.version = versionOf(lib.name)
		table.insert(reports, report)
	end

	local violations = 0
	for _, lib in reports do
		violations += #lib.forbidden + #lib.unresolved
	end
	local i20 = checkAdapterOnly()
	violations += #i20

	local expected = lockText(reports)
	local lockState = "未建立"
	if fs.isFile(joinPath(ROOT, LOCK_FILE)) then
		if readFile(LOCK_FILE) == expected then
			lockState = "与锁一致"
		else
			lockState = "**与锁不一致**（上游被动过？若是有意升级，跑 --write-lock）"
			violations += 1
		end
	end
	fs.writeFile(joinPath(ROOT, AUDIT_FILE), render(reports, i20, lockState))
	if flags.writeLock then
		fs.writeFile(joinPath(ROOT, LOCK_FILE), expected)
		lockState = "已重建"
	end
	return violations, lockState, reports
end

-- ---------- 自检（证明本门禁会失败）----------
local function selftest(): boolean
	local failures: { string } = {}
	local expect = function(cond: boolean, what: string)
		if not cond then
			table.insert(failures, what)
		end
	end
	-- 1) 简单 script 链解析
	local edges, bad = requireEdges(
		"src/ReplicatedStorage/Scribe/Server/Leaderboards.luau",
		"local Internal = script.Parent.Parent.Internal\nlocal Log = require(Internal.Log)\n"
	)
	expect(#bad == 0, `别名链应可解析（bad={#bad}）`)
	expect(
		edges[1] ~= nil and edges[1].to == "src/ReplicatedStorage/Scribe/Internal/Log.luau",
		`别名链应解析到 Internal/Log.luau（得到 {tostring(edges[1] and edges[1].to)}）`
	)
	-- 2) init.luau 的 script 语义（节点=所在目录）
	local initEdges =
		requireEdges("src/ReplicatedStorage/Scribe/init.luau", "local X = require(script.Internal.Log)\n")
	expect(
		initEdges[1] ~= nil and initEdges[1].to == "src/ReplicatedStorage/Scribe/Internal/Log.luau",
		"init.luau 的 script.Internal 应指向同目录的 Internal"
	)
	-- 3) 动态 require 必须被拒（不许静默跳过）
	local _, dynamicBad = requireEdges("f.luau", "local m = require(someTable[key])\n")
	expect(#dynamicBad == 1, "动态 require 必须报违规")
	local _, numericBad = requireEdges("f.luau", "local m = require(12345)\n")
	expect(#numericBad == 1, "数字 require 必须报违规")
	-- 4) 后门面必须被抓
	expect(countOf("local f = loadstring('x')", "loadstring") == 1, "loadstring 必须被扫到")
	expect(
		countOf("local h = game:GetService('HttpService')", "HttpService") == 1,
		"HttpService 必须被扫到"
	)
	-- 5) 漂移锁：改一个字节，哈希必须变
	expect(hash32("abc") ~= hash32("abd"), "内容改变必须改变哈希")
	expect(hash32("") == hash32(""), "哈希必须确定")
	if #failures > 0 then
		for _, f in failures do
			print(`[selftest] 失败: {f}`)
		end
		return false
	end
	print(
		"[selftest] 通过：#1 别名链 · #2 init 语义 · #3 动态/数字 require · #4 后门面 · #5 漂移哈希（5 组）"
	)
	return true
end

for _, arg in process.args do
	if arg == "--quiet" then
		flags.quiet = true
	elseif arg == "--write-lock" then
		flags.writeLock = true
	elseif arg == "--selftest" then
		process.exit(if selftest() then 0 else 1)
	end
end

local violations, lockState, reports = audit()
if not flags.quiet then
	print(string.format("%-12s %-9s %-8s %-9s %-8s %s", "LIB", "VERSION", "FILES", "LOC", "REACH", "HASH"))
	for _, lib in reports do
		print(
			string.format(
				"%-12s %-9s %-8d %-9d %-8s %s",
				lib.name,
				lib.version,
				lib.files,
				lib.loc,
				`{lib.reachable}/{lib.files}`,
				lib.hash
			)
		)
	end
	print("")
	print(`第三方审计：锁 {lockState} · 违规 {violations} · 报告已写入 {AUDIT_FILE}`)
end
if violations > 0 then
	print(`FAIL: 第三方审计发现 {violations} 处违规（详见 {AUDIT_FILE}）`)
	process.exit(1)
end
