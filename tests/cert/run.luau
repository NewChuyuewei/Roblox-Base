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
-- harness 与覆盖工具（scripts/coverage.luau）共用一份：两条路必须跑同一套断言语义
local Harness = require("../../scripts/cert-harness")
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
	local cases = Harness.loadCases(entry.key)
	local results, t = Harness.runCases(cases, M)
	local recorded: { any } = {}
	for _, case in results do
		totalCases += 1
		if not case.pass then
			totalFail += 1
		end
		table.insert(recorded, {
			id = case.id,
			kind = case.kind,
			covers = table.concat(case.covers, ", "),
			pass = case.pass,
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
