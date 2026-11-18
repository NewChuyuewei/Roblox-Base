--!strict
-- DO-178C 认证范围守卫 —— 门禁 10（不变量 I16）。
--
-- 认证范围（DAL C/D，docs/cert/HAZARD.md §4）内的文件**不得**接触引擎、网络、
-- 非认证层。它让"用设计隔离代替平台鉴定"（.plan/CERT.md §4.2）成为可执行约束。
--
-- 两阶段：
--   A 字面模式：引擎 API / 跨树 require / 非认证层名字
--   B 依赖闭包：认证文件里每个 require 必须**解析到范围内**
--
-- 为什么必须有 B：A 只抓字面。写 require(script.Parent.Parent.Parent.Diagnostics.Logging.Logger)
-- 时 A 什么都不报，但它已经依赖了 DAL E 的日志层 —— I16 被静默穿透。
--
-- 为什么用 Lune 而不是 bash：bash 版每行要起 4~6 个子进程，Windows 上 57 个条目
-- 直接跑到 4 分钟。单进程实现既快又可自检，而**门禁本身必须先被验证**。
--
-- 用法：
--   lune run scripts/cert-scope-check.luau             # 校验
--   lune run scripts/cert-scope-check.luau --quiet     # 只输出问题与摘要
--   lune run scripts/cert-scope-check.luau --selftest  # 自检：证明本门禁会失败
-- 退出码：0 = 无违规；1 = 有违规 / 缺清单 / 自检失败

local fs = require("@lune/fs")
local process = require("@lune/process")

local ROOT = "."
local SCOPE_FILE = "docs/cert/scope.txt"

-- ---------- 小工具（不依赖 string.split，避免扩展差异） ----------
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

-- 折叠 a/./ 与 a/../（栈式实现，无可循环空间）
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

-- ---------- 语义核心：require(script.Parent…) → 仓库相对路径（无扩展名） ----------
-- Roblox/Rojo 语义（最易弄错的一点）：
--   script          = 本文件
--   script.Parent   = 本文件所在文件夹 = dirname(file)   ← 就是 dir 本身
-- 所以 N 个 Parent 只向上 **(N-1)** 层。
export type Resolution = { kind: "resolved" | "self" | "literal" | "unknown", path: string? }

local function resolveRequire(fromFile: string, arg: string): Resolution
	local a = trim(arg)
	if a == "script" then
		return { kind = "self" }
	end
	if string.find(a, '"', 1, true) ~= nil or string.find(a, "'", 1, true) ~= nil then
		return { kind = "literal", path = a } -- 路径式 require：认证范围不可静态追溯
	end
	if string.sub(a, 1, 6) ~= "script" then
		return { kind = "unknown", path = a }
	end

	local rest = string.sub(a, 8) -- 去掉 "script."（若只有 "script" 已在上面返回）
	local parts = split(rest, ".")
	local parents = 0
	for _, part in parts do
		if part ~= "Parent" then
			break
		end
		parents += 1
	end

	local base = dirname(fromFile)
	for _ = 2, parents do -- 第 1 个 Parent 已经由 base=dirname 体现
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

-- ---------- A 阶段：禁止的字面模式 ----------
-- 逐条都有理由：
--   GetService( / game: / game.  —— 触碰引擎（I10：引擎 API 只应出现在 Dr.Runtime）
--   ReplicatedStorage            —— 跨树 require；认证核心只允许同树相对 require
--   Dr.*/Tri.* 非认证层           —— CERT.md §3.2
--   workspace: / loadstring(      —— 引擎全局 / 动态求值
local BANNED = {
	"GetService(",
	"game:",
	"game.",
	"ReplicatedStorage",
	"Dr.Runtime",
	"Dr.Net.",
	"Dr.Security",
	"Dr.Diagnostics",
	"Dr.Testing",
	"Tri.Runtime",
	"Tri.Integration",
	"workspace:",
	"loadstring(",
}

-- 扫描前剥掉整行注释（保留行号）。
-- 理由：否则"说明为什么不能用 Debug"的注释会被判违规，而会误报文档的门禁最终会
-- 被人加豁免关掉 —— 那比没有门禁更糟。
-- 保守性：只剥"行首即注释"，行尾注释仍参与扫描，因此不会因剥离而隐藏真违规。
local function stripComments(source: string): { string }
	local out: { string } = {}
	for _, line in split(source, "\n") do
		local trimmed = trim(line)
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
			local close = string.find(line, ")", at, true)
			local text = if close == nil
				then string.sub(line, at + 8)
				else string.sub(line, at + 8, close - 1)
			table.insert(out, { line = index, text = text })
			start = at + 8
		end
	end
	return out
end

-- ---------- 审计核心（check 与 selftest **共用同一条路径**）----------
-- 自检必须走真实代码路径；自己再写一遍循环就等于什么都没测。
local function audit(path: string, lines: { string }, inScope: (string) -> boolean): { string }
	local detail: { string } = {}

	-- A 字面模式
	for index, line in lines do
		for _, pattern in BANNED do
			if string.find(line, pattern, 1, true) ~= nil then
				table.insert(detail, `{pattern}@L{index}`)
			end
		end
	end

	-- B 依赖闭包
	for _, req in findRequires(lines) do
		local resolved = resolveRequire(path, req.text)
		if resolved.kind == "resolved" then
			local target = resolved.path :: string
			if not inScope(target) then
				table.insert(detail, `依赖范围外:{target}@L{req.line}`)
			end
		elseif resolved.kind == "literal" then
			table.insert(detail, `路径式require不可追溯@L{req.line}`)
		elseif resolved.kind == "unknown" then
			table.insert(detail, `require无法解析:{resolved.path}@L{req.line}`)
		end
	end

	return detail
end

-- ---------- 主校验 ----------
type Finding = { file: string, state: string, detail: string }

local function readScope(): { string }
	local text = fs.readFile(SCOPE_FILE) :: string
	local out: { string } = {}
	for _, raw in split(text, "\n") do
		local line = trim((string.gsub(raw, "#.*$", ""))) -- 双括号：gsub 返回两个值，丢掉第二个
		if line ~= "" then
			table.insert(out, line)
		end
	end
	return out
end

local function check(verbose: boolean): (number, number, number, { Finding })
	local entries = readScope()
	local inScopeSet: { [string]: boolean } = {}
	for _, path in entries do
		inScopeSet[path] = true
	end

	local function inScope(path: string): boolean
		return inScopeSet[path .. ".luau"] == true or inScopeSet[path .. "/init.luau"] == true
	end

	local findings: { Finding } = {}
	local present, missing, violations = 0, 0, 0
	for _, path in entries do
		if not fs.isFile(path) then
			missing += 1
			if verbose then
				table.insert(findings, { file = path, state = "PLANNED", detail = "(尚未创建)" })
			end
			continue
		end
		present += 1
		local detail = audit(path, stripComments(fs.readFile(path) :: string), inScope)

		if #detail > 0 then
			violations += 1
			table.insert(findings, { file = path, state = "VIOLATION", detail = table.concat(detail, " ") })
		elseif verbose then
			table.insert(findings, { file = path, state = "OK", detail = "" })
		end
	end

	return present, missing, violations, findings
end

-- ---------- 自检：门禁必须先证明自己会失败 ----------
local function selftest(): boolean
	local failures: { string } = {}
	local function expect(cond: boolean, what: string)
		if not cond then
			table.insert(failures, what)
		end
	end

	-- 路径语义
	local r1 = resolveRequire(
		"src/ReplicatedStorage/Deuterium/Core/Foundation/Contract.luau",
		"script.Parent.ErrorHandler"
	)
	expect(
		r1.kind == "resolved" and r1.path == "src/ReplicatedStorage/Deuterium/Core/Foundation/ErrorHandler",
		"1 个 Parent = 同目录"
	)

	local r2 = resolveRequire(
		"src/ReplicatedStorage/Deuterium/Types/Contract/Interface.luau",
		"script.Parent.Parent.Parent.Core.Foundation.ErrorHandler"
	)
	expect(
		r2.kind == "resolved" and r2.path == "src/ReplicatedStorage/Deuterium/Core/Foundation/ErrorHandler",
		"3 个 Parent 向上 2 层"
	)

	local r3 =
		resolveRequire("src/ReplicatedStorage/Deuterium/Core/Container/Kernel.luau", "script.Parent.Types")
	expect(
		r3.kind == "resolved" and r3.path == "src/ReplicatedStorage/Deuterium/Core/Container/Types",
		"同目录兄弟"
	)

	local r4 = resolveRequire("src/ReplicatedStorage/Deuterium/Core/X.luau", "'./y'")
	expect(r4.kind == "literal", "路径式 require 必须被识别为不可追溯")

	local r5 = resolveRequire("src/ReplicatedStorage/Deuterium/Core/X.luau", "script.Parent")
	expect(
		r5.kind == "resolved" and r5.path == "src/ReplicatedStorage/Deuterium/Core/init",
		"无尾名 -> 文件夹 init"
	)

	-- 门禁本身必须会失败。走真实的 audit 路径，用真实存在的文件（DAL E 的 Logging/Debug）：
	-- 它的 require 指向同目录的 Logger/LogSink，在一个“只含 Debug 自己”的范围里必须是违规。
	local probe = "src/ReplicatedStorage/Deuterium/Diagnostics/Logging/Debug.luau"
	if fs.isFile(probe) then
		local lines = stripComments(fs.readFile(probe) :: string)
		local only = function(path: string): boolean
			return path == "src/ReplicatedStorage/Deuterium/Diagnostics/Logging/Debug"
		end
		expect(#audit(probe, lines, only) > 0, "B 段必须报出范围外依赖（否则 I16 是空话）")
		expect(#audit(probe, lines, function(): boolean
			return true
		end) == 0, "全部在范围内时不得误报")
	end

	-- A 段必须会失败：engine 访问与跨树 require
	local badSource = 'local Debug = require(game:GetService("ReplicatedStorage"):WaitForChild("Debug"))\n'
	expect(#audit("x.luau", stripComments(badSource), function(): boolean
		return true
	end) > 0, "A 段必须抓到 game:GetService( 与 ReplicatedStorage")

	-- 剥注释：行首注释里的违规字样不得误报（否则门禁会被加豁免关掉）
	local commentOnly = '-- 举例：不要写 require(game:GetService("ReplicatedStorage"))\nreturn nil\n'
	expect(#audit("x.luau", stripComments(commentOnly), function(): boolean
		return true
	end) == 0, "整行注释不得误报")

	if #failures == 0 then
		print("[selftest] 通过：路径语义 5 例 · A 段 1 例 · B 段 2 例 · 注释剥离 1 例")
		return true
	end
	for _, f in failures do
		print(`[selftest] 失败: {f}`)
	end
	return false
end

-- ---------- 入口 ----------
local args = process.args
local quiet = false
local wantSelftest = false
for _, arg in args do
	if arg == "--quiet" then
		quiet = true
	elseif arg == "--selftest" then
		wantSelftest = true
	else
		-- 同 loc-budget：忽略未知参数会让打错的开关静默变成默认行为（假绿）。
		print(`未知参数：{arg}（可用：--quiet · --selftest）`)
		process.exit(2)
	end
end

if wantSelftest then
	process.exit(if selftest() then 0 else 1)
end

if not fs.isFile(SCOPE_FILE) then
	print(`FAIL: 缺少认证范围清单 {SCOPE_FILE}`)
	process.exit(1)
end

local present, missing, violations, findings = check(not quiet)

if not quiet then
	print(string.format("%-56s %-9s %s", "FILE", "STATE", "DETAIL"))
	for _, f in findings do
		print(string.format("%-56s %-9s %s", f.file, f.state, f.detail))
	end
	print("")
end

print(`认证范围：已存在 {present} 文件 · 计划未创建 {missing} 文件 · 违规 {violations}`)

if violations > 0 then
	print("")
	print(
		"门禁 10 失败：认证范围（DAL C/D）内有文件接触引擎/网络/非认证层，或依赖范围外模块。"
	)
	print("这不是警告 —— I16 是'用隔离代替平台鉴定'的前提。修法三选一：")
	print("  1) 该文件移出认证范围（从 scope.txt 删除，并核对 HAZARD.md §4）")
	print(
		"  2) 把不纯的部分拆出去（例：ErrorHandler.Report 已按此删除，见 HAZARD.md §5.1）"
	)
	print("  3) 依赖改为构造器注入（范围外依赖作为参数传入，而不是 require 它）")
	process.exit(1)
end

if present == 0 then
	print("注意：认证范围内**尚无任何文件**（全部是 PLANNED）。守卫目前空转。")
end

print("门禁 10 OK")
