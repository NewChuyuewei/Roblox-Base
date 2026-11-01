--!nocheck
-- 认证线验证运行器（C3 / Step 72 的一部分）
--
--   lune run tests/cert/run.luau
--
-- 它做的事：装载**认证范围**里的模块（**不加引擎桩**，因为认证核心必须零引擎依赖）→
-- 跑 tests/cert/cases/<MOD>.luau 的用例 → 生成 docs/cert/verify/<MOD>.md（CC1 证据）。
--
-- 与产品线严格分开（CERT.md §9.2 / STEPS §二点五 规则 2）：
--   · 不 require 任何 Dr.Testing / SelfTest / TestKit
--   · 不写进 tests/run.luau 的报告，也不读它的输出
--   · 报告只落在 docs/cert/verify/ 下
--
-- 用例协议：cases/<MOD>.luau 返回 { { id, kind, covers = {...}, run = function(t, M) end }, ... }
--   t.ok(cond, label) / t.eq(actual, expected, label) / t.throws(fn, label) / t.raises(fn, codePrefix, label)

local Loader = require("../../scripts/lune-loader")
local fs = require("@lune/fs")
local process = require("@lune/process")

local CERT_MODULES = {
	{ mod = "CORETYPES", key = "CoreTypes", src = "src/ReplicatedStorage/Deuterium/Core/Foundation/CoreTypes.luau" },
	{ mod = "CONTRACT", key = "Contract", src = "src/ReplicatedStorage/Deuterium/Core/Foundation/Contract.luau" },
	{ mod = "ERRORHANDLER", key = "ErrorHandler", src = "src/ReplicatedStorage/Deuterium/Core/Foundation/ErrorHandler.luau" },
	{ mod = "INTERFACE", key = "Interface", src = "src/ReplicatedStorage/Deuterium/Types/Contract/Interface.luau" },
}
local VERIFY_DIR = "docs/cert/verify"

local function luneVersion(): string
	local ok, value = pcall(function()
		return (process :: any).version
	end)
	return if ok and type(value) == "string" then value else "?"
end

-- 用例文件是纯函数模块（不 require 任何东西），所以直接 loadstring 即可 ——
-- 不必让 loader 再挂一个根（一个进程只能挂一个根，而认证模块在
-- src/ReplicatedStorage、用例在 tests/cert/cases）。
local function loadCases(name: string): { any }
	local path = `tests/cert/cases/{name}.luau`
	local chunk = assert(loadstring(fs.readFile(path) :: string, path))
	return chunk()
end

local function newHarness()
	local t: any = { checks = 0, failures = {} }
	local function fail(label: string, detail: string)
		table.insert(t.failures, `{label} — {detail}`)
	end
	function t.ok(cond: any, label: string)
		assert(type(label) == "string" and #label > 0, "t.ok 必须带 label（两参）")
		t.checks += 1
		if not cond then
			fail(label, `期望为真，得到 {tostring(cond)}`)
		end
	end
	function t.eq(actual: any, expected: any, label: string)
		-- 护栏：写完真出过一次 “t.eq(cond, "文字")” 的少参误用，报错会指向错的地方。
		assert(type(label) == "string" and #label > 0, "t.eq 必须带 label（三参）")
		t.checks += 1
		if actual ~= expected then
			fail(label, `期望 {tostring(expected)}，得到 {tostring(actual)}`)
		end
	end
	-- 只要求“抛了”（用于 assert 类前置条件）
	function t.throws(fn: () -> (), label: string): any
		t.checks += 1
		local ok, err = pcall(fn)
		if ok then
			fail(label, "期望抛出，但没有抛")
		end
		return err
	end
	-- 要求“抛出的是 DrError”，并校验 code 前缀；返回实际 code
	function t.raises(fn: () -> (), codePrefix: string?, label: string): string
		t.checks += 1
		local ok, err = pcall(fn)
		if ok then
			fail(label, "期望抛出 DrError，但没有抛")
			return ""
		end
		if type(err) ~= "table" or type(err.code) ~= "string" or type(err.message) ~= "string" then
			fail(label, `抛出的不是 DrError（而是 {type(err)}: {tostring(err)}）`)
			return ""
		end
		if codePrefix ~= nil and codePrefix ~= "" and string.sub(err.code, 1, #codePrefix) ~= codePrefix then
			fail(label, `期望 code 前缀 {codePrefix}，得到 {err.code}`)
		end
		return err.code
	end
	return t
end

-- ---------- 装载认证模块（无引擎桩）----------
local M: any = { meta = { engineStub = false, loader = "scripts/lune-loader.luau" } }
for _, entry in CERT_MODULES do
	M[entry.key] = Loader.load(entry.src)
end

-- ---------- 跑用例 ----------
local reports: { { mod: string, cases: { any }, checks: number, failures: { string } } } = {}
local totalCases, totalFail = 0, 0
local totalChecks = 0
for _, entry in CERT_MODULES do
	-- 用例文件名用 key（PascalCase，与源码同名），不是全大写的 MOD 短名
	local cases = loadCases(entry.key)
	local t = newHarness()
	local recorded: { any } = {}
	for _, case in cases do
		local before = #t.failures
		local okRun, err = pcall(case.run, t, M)
		if not okRun then
			table.insert(t.failures, `{case.id} — 用例自身抛错: {tostring(err)}`)
		end
		local passed = #t.failures == before
		totalCases += 1
		if not passed then
			totalFail += 1
		end
		table.insert(recorded, {
			id = case.id,
			kind = case.kind,
			covers = table.concat(case.covers, ", "),
			pass = passed,
		})
	end
	totalChecks += t.checks
	table.insert(reports, { mod = entry.mod, cases = recorded, checks = t.checks, failures = t.failures })
end

-- ---------- 生成 docs/cert/verify/<MOD>.md（CC1 生成物）----------
if not fs.isDir(VERIFY_DIR) then
	fs.writeDir(VERIFY_DIR)
end
for _, report in reports do
	local out: { string } = {}
	local put = function(line: string)
		table.insert(out, line)
	end
	local failed = 0
	local covered: { [string]: boolean } = {}
	for _, case in report.cases do
		if not case.pass then
			failed += 1
		end
		for token in string.gmatch(case.covers, "[^,]+") do
			covered[(string.gsub(token, "^%s*(.-)%s*$", "%1")) :: string] = true
		end
	end
	local coveredList: { string } = {}
	for id in covered do
		table.insert(coveredList, id)
	end
	table.sort(coveredList)
	put(`# 验证用例与结果 · {report.mod}`)
	put("")
	put("> **生成物 — 勿手改**。由 `lune run tests/cert/run.luau` 生成（认证线）。")
	put("> 与产品线严格分开：本文件不含 `SelfTest`/`TestKit` 的任何输出（`CERT.md` §9.2）。")
	put("")
	put(`- 环境：Lune ` .. "`" .. luneVersion() .. "`" .. ` · loader \`scripts/lune-loader.luau\`（**无引擎桩**）`)
	put(`- 结果：**{ #report.cases - failed }/{ #report.cases } 用例通过** · 断言 {report.checks} 次`)
	put(`- 覆盖的需求：{table.concat(coveredList, "、")}`)
	put("")
	put("| 用例 | 类别 | 覆盖 | 结果 |")
	put("| --- | --- | --- | --- |")
	for _, case in report.cases do
		local mark = if case.pass then "PASS" else "**FAIL**"
		put(`| \`{case.id}\` | {case.kind} | {case.covers} | {mark} |`)
	end
	if #report.failures > 0 then
		put("")
		put("## 失败明细")
		put("")
		for _, f in report.failures do
			put(`- {f}`)
		end
	end
	fs.writeFile(`{VERIFY_DIR}/{report.mod}.md`, table.concat(out, "\n") .. "\n")
end

-- ---------- 报告 ----------
print(string.format("%-16s %-10s %-8s %s", "MODULE", "CASES", "CHECKS", "FAIL"))
for _, report in reports do
	local failed = 0
	for _, case in report.cases do
		if not case.pass then
			failed += 1
		end
	end
	local failedText = if failed == 0 then "0" else tostring(failed)
	print(string.format("%-16s %-10d %-8d %s", report.mod, #report.cases, report.checks, failedText))
end
print("")
print(`认证线（cert）：用例 {totalCases} · 失败 {totalFail} · 断言 {totalChecks} · 报告写入 {VERIFY_DIR}/`)
if totalFail > 0 then
	for _, report in reports do
		for _, f in report.failures do
			print(`  FAIL {report.mod}: {f}`)
		end
	end
	process.exit(1)
end
