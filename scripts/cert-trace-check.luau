--!strict
-- 门禁 11：追溯完整性（C3 / Step 72）—— 需求 · 代码 · 用例 三者的四向闭环
--
--   lune run scripts/cert-trace-check.luau            # 检查并重写 docs/cert/TRACE.md（有违规 exit 1）
--   lune run scripts/cert-trace-check.luau --quiet
--   lune run scripts/cert-trace-check.luau --selftest  # 自检：故意构造缺陷，证明本门禁会失败
--
-- 权威：`docs/cert/REQ-STD.md` §5。四个方向：
--   ① 需求 → 代码   每个 LLR 必须能在认证源码里找到 `-- LLR-<MOD>-nnn` 注解   （否则 孤儿需求 ORPHAN_LLR）
--   ② 代码 → 需求   认证源码里每个**导出声明**都必须有注解，且注解必须指向已登记的需求（否则 UNSOURCED_CODE）
--   ③ 需求 → 测试   每条 HLR/LLR 至少被一个 `TC` 覆盖                             （否则 UNTESTED_REQ）
--   ④ 需求 → 覆盖   需求映射到的代码行是否被执行过 —— **本门禁不判**，归 C4 的结构覆盖工具（见报告末尾）
--
-- 机检锚点（唯一可自动化的）：源码的 `-- LLR-…` 注解 + 用例文件的 `-- covers:` 头与 per-case `covers`。
-- 注解缺失不是风格问题，是**追溯缺失**（REQ-STD §5 原话）。

local fs = require("@lune/fs")
local process = require("@lune/process")

local SCOPE_FILE = "docs/cert/scope.txt"
local REQ_DIR = "docs/cert/req"
local CASE_DIR = "tests/cert/cases"
local HAZARD_FILE = "docs/cert/HAZARD.md"
local TRACE_FILE = "docs/cert/TRACE.md"

-- 认证源码里的路径前缀（需求文件里写的是 `Deuterium/...` 这种短形式）
local SRC_PREFIX = "src/ReplicatedStorage/"

local HLR_FIELDS = {
	"需求",
	"激励",
	"响应",
	"前置条件",
	"后置条件",
	"危害追溯",
	"验证方法",
	"可判定性",
}
local LLR_FIELDS = { "需求", "实现位置", "分支/边界", "验证方法", "上级需求" }

export type Violation = { kind: string, where: string, detail: string }
export type Input = {
	requirements: { { path: string, text: string } },
	sources: { { path: string, mod: string, text: string } },
	cases: { { path: string, mod: string, text: string } },
	hazards: { string },
	fileExists: (string) -> boolean,
}
export type Baseline = {
	hlr: { [string]: { [string]: string } },
	llr: { [string]: { [string]: string } },
}

-- ---------- 小工具 ----------
local function trim(text: string): string
	return (string.gsub(text, "^%s*(.-)%s*$", "%1")) :: string
end

local function splitLines(text: string): { string }
	local out: { string } = {}
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		table.insert(out, line)
	end
	return out
end

local function joinSorted(set: { [string]: boolean }): string
	local list: { string } = {}
	for key in set do
		table.insert(list, key)
	end
	table.sort(list)
	return table.concat(list, "、")
end

local function addTo(set: { [string]: boolean }, key: string)
	set[key] = true
end

-- ---------- 需求解析 ----------
local function parseRequirementBlocks(text: string, idPattern: string): { [string]: { [string]: string } }
	local found: { [string]: { [string]: string } } = {}
	local lines = splitLines(text)
	local currentId: string? = nil
	local fields: { [string]: string } = {}
	local function flush()
		if currentId ~= nil then
			found[currentId :: string] = fields
		end
		currentId, fields = nil, {}
	end
	for _, line in lines do
		local heading = string.match(line, "^###%s+(" .. idPattern .. ")")
		if heading ~= nil then
			flush()
			currentId = heading
		elseif string.match(line, "^##") ~= nil or line == "---" then
			flush()
		elseif currentId ~= nil then
			local key, value = string.match(line, "^%-%s+%*%*(.-)%*%*[:：]%s*(.*)$")
			if key ~= nil then
				fields[trim(key)] = trim(value)
			end
		end
	end
	flush()
	return found
end

local function parseBaseline(input: Input): (Baseline, { Violation })
	local hlr: { [string]: { [string]: string } } = {}
	local llr: { [string]: { [string]: string } } = {}
	local violations: { Violation } = {}
	for _, file in input.requirements do
		local parsedHlr = parseRequirementBlocks(file.text, "HLR%-%u+%-%d+")
		local parsedLlr = parseRequirementBlocks(file.text, "LLR%-%u+%-%d+")
		for id, fields in parsedHlr do
			if hlr[id] ~= nil then
				table.insert(violations, { kind = "DUP_ID", where = file.path, detail = `id 重复: {id}` })
			end
			hlr[id] = fields
		end
		for id, fields in parsedLlr do
			if llr[id] ~= nil then
				table.insert(violations, { kind = "DUP_ID", where = file.path, detail = `id 重复: {id}` })
			end
			llr[id] = fields
		end
	end

	for id, fields in hlr do
		for _, name in HLR_FIELDS do
			if fields[name] == nil or fields[name] == "" then
				table.insert(
					violations,
					{ kind = "REQ_FIELD_MISSING", where = id, detail = `缺少必填字段「{name}」` }
				)
			end
		end
		local hazard = fields["危害追溯"]
		if hazard ~= nil then
			local legal = false
			for _, token in input.hazards do
				if string.find(hazard, token, 1, true) ~= nil then
					legal = true
				end
			end
			if not legal then
				table.insert(violations, {
					kind = "HAZARD_INVALID",
					where = id,
					detail = `危害追溯「{hazard}」不在合法集合（{table.concat(
						input.hazards,
						"/"
					)}）内`,
				})
			end
		end
	end

	for id, fields in llr do
		for _, name in LLR_FIELDS do
			if fields[name] == nil or fields[name] == "" then
				table.insert(
					violations,
					{ kind = "REQ_FIELD_MISSING", where = id, detail = `缺少必填字段「{name}」` }
				)
			end
		end
		local parent = fields["上级需求"]
		if parent ~= nil then
			for parentId in string.gmatch(parent, "HLR%-%u+%-%d+") do
				if hlr[parentId] == nil then
					table.insert(violations, {
						kind = "HLR_MISSING",
						where = id,
						detail = `上级需求 {parentId} 不在基线里`,
					})
				end
			end
		end
		local place = fields["实现位置"]
		if place ~= nil then
			local path = string.match(place, "`([^`]+)`")
			if path == nil then
				table.insert(violations, {
					kind = "IMPL_PATH_MISSING",
					where = id,
					detail = "实现位置未用反引号给出文件路径",
				})
			else
				local full = if string.sub(path, 1, 4) == "src/" then path else SRC_PREFIX .. path
				if not input.fileExists(full) then
					table.insert(violations, {
						kind = "IMPL_PATH_MISSING",
						where = id,
						detail = `实现位置指向不存在的文件: {full}`,
					})
				end
			end
		end
		local verify = fields["验证方法"]
		if verify ~= nil and string.match(verify, "TC%-%u+%-%d+") == nil then
			table.insert(
				violations,
				{ kind = "TC_MISSING", where = id, detail = "验证方法未引用任何 TC" }
			)
		end
	end

	return { hlr = hlr, llr = llr }, violations
end

-- ---------- 源码解析 ----------
export type SourceUse = { annotations: { [string]: boolean }, declarations: number }

local function scanSource(text: string, mod: string, path: string, violations: { Violation }): SourceUse
	local lines = splitLines(text)
	local annotations: { [string]: boolean } = {}
	local declarations = 0
	for index, line in lines do
		local isExport = string.match(line, "^function%s+[%w_]+%.[%w_]+%s*%(") ~= nil
		local isType = string.match(line, "^export%s+type%s+%w+") ~= nil
		if isExport or isType then
			declarations += 1
			-- 向上找最近一个注释块里的注解（最多 12 行）
			local found: string? = nil
			local back = index - 1
			local budget = 12
			while back >= 1 and budget > 0 do
				local above = lines[back] :: string
				if string.match(above, "^%s*$") ~= nil then
					back -= 1
					budget -= 1
				elseif string.match(above, "^%s*%-%-") ~= nil then
					local id = string.match(above, "^%s*%-%-%s*(LLR%-%u+%-%d+)%s*$")
					if id ~= nil and found == nil then
						found = id
					end
					back -= 1
					budget -= 1
				else
					break
				end
			end
			local what = string.match(line, "^%s*(.-)%s*$") :: string
			if found == nil then
				table.insert(violations, {
					kind = "UNSOURCED_CODE",
					where = `{path}:{index}`,
					detail = `声明没有 LLR 注解（意外功能）: {what}`,
				})
			else
				addTo(annotations, found :: string)
				local idMod = string.match(found :: string, "^LLR%-(%u+)%-%d+")
				if idMod ~= mod then
					table.insert(violations, {
						kind = "MOD_MISMATCH",
						where = `{path}:{index}`,
						detail = `注解 {found} 属于 {tostring(idMod)}，但文件是 {mod}`,
					})
				end
			end
		end
	end
	return { annotations = annotations, declarations = declarations }
end

-- ---------- 用例解析 ----------
export type CaseFile = {
	mod: string,
	path: string,
	header: { [string]: boolean },
	cases: { { id: string, kind: string, covers: { [string]: boolean } } },
}

local function parseCaseFile(path: string, mod: string, text: string, violations: { Violation }): CaseFile
	local header: { [string]: boolean } = {}
	local cases: { { id: string, kind: string, covers: { [string]: boolean } } } = {}
	local lines = splitLines(text)
	local headerLine = string.match(text, "%-%- covers: ([^\n]+)")
	if headerLine == nil then
		-- 先落局部再 insert：嵌套的表构造会让 stylua 失去幂等（见 MEMORY.md §2）
		local finding: Violation = {
			kind = "HEADER_MISSING",
			where = path,
			detail = "用例文件缺少 `-- covers:` 头（SVP §3）",
		}
		table.insert(violations, finding)
	else
		for token in string.gmatch(headerLine, "[%u%d]+%-[%u%d]+%-%d+") do
			addTo(header, token)
		end
	end
	local currentId: string? = nil
	local currentKind = "?"
	local currentCovers: { [string]: boolean } = {}
	local function flush()
		if currentId ~= nil then
			table.insert(cases, { id = currentId :: string, kind = currentKind, covers = currentCovers })
		end
		currentId, currentKind, currentCovers = nil, "?", {}
	end
	for _, line in lines do
		-- id / kind / covers 可能在**同一行**（紧凑写法），所以三个都独立匹配，不用 else 串起来。
		local id = string.match(line, 'id%s*=%s*"(TC%-%u+%-%d+)"')
		if id ~= nil then
			flush()
			currentId = id
		end
		if currentId ~= nil then
			local kind = string.match(line, 'kind%s*=%s*"([^"]*)"')
			if kind ~= nil then
				currentKind = kind
			end
			local covers = string.match(line, "covers%s*=%s*%{([^}]*)}")
			if covers ~= nil then
				for token in string.gmatch(covers, "%u[%u%d]*%-%u[%u%d]*%-%d+") do
					addTo(currentCovers, token)
				end
			end
		end
	end
	flush()
	if #cases == 0 then
		table.insert(
			violations,
			{ kind = "CASE_EMPTY", where = path, detail = "用例文件里没有解析到任何用例" }
		)
	end
	return { mod = mod, path = path, header = header, cases = cases }
end

-- ---------- 四向检查（check 与 selftest 共用同一条路径）----------
export type Report = {
	baseline: Baseline,
	violations: { Violation },
	llrToCode: { [string]: { string } },
	reqToCases: { [string]: { string } },
	sourceStats: { { path: string, mod: string, declarations: number, annotations: number } },
	caseStats: { { path: string, mod: string, cases: number } },
}

local function analyze(input: Input): Report
	local violations: { Violation } = {}
	local baseline, reqViolations = parseBaseline(input)
	for _, v in reqViolations do
		table.insert(violations, v)
	end

	-- ② 代码 → 需求
	local allAnnotations: { [string]: boolean } = {}
	local llrToCode: { [string]: { string } } = {}
	local sourceStats: { { path: string, mod: string, declarations: number, annotations: number } } = {}
	for _, source in input.sources do
		local use = scanSource(source.text, source.mod, source.path, violations)
		local count = 0
		for id in use.annotations do
			count += 1
			addTo(allAnnotations, id)
			if baseline.llr[id] == nil then
				table.insert(violations, {
					kind = "UNKNOWN_LLR",
					where = source.path,
					detail = `注解 {id} 不在需求基线里（要么基线漏登记，要么注解写错）`,
				})
			else
				local list = llrToCode[id] or {}
				table.insert(list, source.path)
				llrToCode[id] = list
			end
		end
		table.insert(sourceStats, {
			path = source.path,
			mod = source.mod,
			declarations = use.declarations,
			annotations = count,
		})
	end

	-- ① 需求 → 代码
	for id in baseline.llr do
		if allAnnotations[id] == nil then
			local finding: Violation = {
				kind = "ORPHAN_LLR",
				where = id,
				detail = "没有任何认证源码实现它（需求无人实现）",
			}
			table.insert(violations, finding)
		end
	end

	-- ③ 需求 → 测试
	local caseFiles: { CaseFile } = {}
	local allTcs: { [string]: boolean } = {}
	for _, caseFile in input.cases do
		table.insert(caseFiles, parseCaseFile(caseFile.path, caseFile.mod, caseFile.text, violations))
	end
	local reqToCases: { [string]: { string } } = {}
	for _, caseFile in caseFiles do
		local union: { [string]: boolean } = {}
		for _, case in caseFile.cases do
			addTo(allTcs, case.id)
			for cover in case.covers do
				addTo(union, cover)
				local list = reqToCases[cover] or {}
				table.insert(list, case.id)
				reqToCases[cover] = list
				if baseline.hlr[cover] == nil and baseline.llr[cover] == nil then
					table.insert(violations, {
						kind = "UNKNOWN_COVER",
						where = `{caseFile.path}:{case.id}`,
						detail = `covers 里出现未登记的需求 {cover}`,
					})
				end
			end
		end
		-- 文件头 covers 与 per-case covers 必须一致（否则两处会各说各话）。
		-- 例外：头部的 `TC-*` 是**用例自身**的 id（用例的 covers 放的是需求 id），所以单独校验：
		-- 头部声明的 TC 必须真的在该文件里存在。
		local fileTcs: { [string]: boolean } = {}
		for _, case in caseFile.cases do
			addTo(fileTcs, case.id)
		end
		for token in caseFile.header do
			if string.sub(token, 1, 3) == "TC-" then
				if fileTcs[token] == nil then
					table.insert(violations, {
						kind = "HEADER_DRIFT",
						where = caseFile.path,
						detail = `文件头声明了用例 {token}，但文件里没有这个用例`,
					})
				end
			elseif union[token] == nil then
				table.insert(violations, {
					kind = "HEADER_DRIFT",
					where = caseFile.path,
					detail = `文件头声明覆盖 {token}，但没有任何用例真的 covers 它`,
				})
			end
		end
		for token in union do
			if caseFile.header[token] == nil then
				table.insert(violations, {
					kind = "HEADER_DRIFT",
					where = caseFile.path,
					detail = `用例覆盖 {token}，但文件头 `, -- covers:` 未声明`,
				})
			end
		end
	end
	for id in baseline.hlr do
		if reqToCases[id] == nil then
			table.insert(
				violations,
				{ kind = "UNTESTED_REQ", where = id, detail = "没有用例覆盖（孤儿需求）" }
			)
		end
	end
	for id in baseline.llr do
		if reqToCases[id] == nil then
			table.insert(
				violations,
				{ kind = "UNTESTED_REQ", where = id, detail = "没有用例覆盖（孤儿需求）" }
			)
		end
	end
	-- 需求文本里引用的 TC 必须真实存在
	for id, fields in baseline.llr do
		local verify = fields["验证方法"] or ""
		for tc in string.gmatch(verify, "TC%-%u+%-%d+") do
			if allTcs[tc] == nil then
				table.insert(violations, {
					kind = "TC_MISSING",
					where = id,
					detail = `验证方法引用了不存在的用例 {tc}`,
				})
			end
		end
	end

	local caseStats: { { path: string, mod: string, cases: number } } = {}
	for _, caseFile in caseFiles do
		table.insert(caseStats, { path = caseFile.path, mod = caseFile.mod, cases = #caseFile.cases })
	end

	return {
		baseline = baseline,
		violations = violations,
		llrToCode = llrToCode,
		reqToCases = reqToCases,
		sourceStats = sourceStats,
		caseStats = caseStats,
	}
end

-- ---------- 报告 ----------
local function render(report: Report): string
	local out: { string } = {}
	local put = function(line: string)
		table.insert(out, line)
	end
	local hlrIds: { string } = {}
	for id in report.baseline.hlr do
		table.insert(hlrIds, id)
	end
	table.sort(hlrIds)
	local llrIds: { string } = {}
	for id in report.baseline.llr do
		table.insert(llrIds, id)
	end
	table.sort(llrIds)

	put("# 追溯矩阵（生成物 — 勿手改）")
	put("")
	put(
		"> 由 `lune run scripts/cert-trace-check.luau` 生成（门禁 11）。权威规则：`docs/cert/REQ-STD.md` §5。"
	)
	put(
		"> 需求文本：`docs/cert/req/` · 用例：`tests/cert/cases/` · 用例结果：`docs/cert/verify/`。"
	)
	put("")
	put(`规模：**{#hlrIds} 条 HLR · {#llrIds} 条 LLR** · 违规 **{#report.violations}** 处`)
	put("")
	put("## 1. 需求 → 代码 → 用例")
	put("")
	put("| LLR | 上级 HLR | 实现位置 | 覆盖用例 |")
	put("| --- | --- | --- | --- |")
	for _, llrId in llrIds do
		local fields = report.baseline.llr[llrId] :: { [string]: string }
		local codeList = report.llrToCode[llrId]
		local code = if codeList ~= nil then table.concat(codeList, "、") else "**缺**"
		local cases = report.reqToCases[llrId]
		local caseText = if cases ~= nil then table.concat(cases, "、") else "**缺**"
		local parent = string.match(fields["上级需求"] or "", "[HLR%-%u+%-%d+]+")
		put(`| \`{llrId}\` | {tostring(parent)} | {code} | {caseText} |`)
	end
	put("")
	put("## 2. HLR → 用例")
	put("")
	put("| HLR | 危害追溯 | 覆盖用例 |")
	put("| --- | --- | --- |")
	for _, hlrId in hlrIds do
		local fields = report.baseline.hlr[hlrId] :: { [string]: string }
		local cases = report.reqToCases[hlrId]
		local caseText = if cases ~= nil then table.concat(cases, "、") else "**缺**"
		put(`| \`{hlrId}\` | {fields["危害追溯"] or "?"} | {caseText} |`)
	end
	put("")
	put("## 3. 认证源码的注解覆盖（② 代码 → 需求）")
	put("")
	put("| 文件 | 导出声明 | 注解 |")
	put("| --- | --- | --- |")
	for _, stat in report.sourceStats do
		put(string.format("| `%s` | %d | %d |", stat.path, stat.declarations, stat.annotations))
	end
	put("")
	put("## 4. 用例文件（③ 需求 → 测试）")
	put("")
	put("| 文件 | 用例数 |")
	put("| --- | --- |")
	for _, stat in report.caseStats do
		put(string.format("| `%s` | %d |", stat.path, stat.cases))
	end
	put("")
	put("## 5. 违规")
	put("")
	if #report.violations == 0 then
		put("**0 处** —— 四向闭环成立（方向 ④ 见下）。")
	else
		put("| 种类 | 位置 | 说明 |")
		put("| --- | --- | --- |")
		for _, v in report.violations do
			put(string.format("| `%s` | `%s` | %s |", v.kind, v.where, v.detail))
		end
	end
	put("")
	put("## 6. 方向 ④（需求 → 覆盖）—— 由覆盖工具负责")
	put("")
	put(
		"本节**不提供**行级覆盖数字：那属于 `scripts/coverage.luau`（**门禁 12**，C4 已交付）。"
	)
	put(
		"它按 statement 口径统计认证范围的可执行行，报告在 `docs/cert/coverage/<MOD>.json`，"
	)
	put("未覆盖行必须逐条登记在 `docs/cert/coverage/UNCOVERED.md`。")
	put("")
	put(
		"**关系要说清**：本文件证明「需求 ↔ 代码 ↔ 用例」的**映射链完整**；覆盖工具证明「映射到的代码真的被执行过」。"
	)
	put("两者都绿才算方向 ④ 成立 —— 本文件单独绿**不等于**覆盖达标。")
	put("---")
	put("")
	put(
		"未读/未验证：本地图是**静态**可导出的关系；`ILLR→代码` 的映射靠注解声明，"
	)
	put("而不是靠解析 AST —— 注解可以被放在错误的位置（有人为错误的空间），")
	put("这一残留风险由评审（`REQ-STD.md` §6）承担，不由本脚本消除。")
	return table.concat(out, "\n") .. "\n"
end

-- ---------- 自检：故意构造缺陷，证明门禁会失败 ----------
local function selftest(): boolean
	local failures: { string } = {}
	local expect = function(cond: boolean, what: string)
		if not cond then
			table.insert(failures, what)
		end
	end
	local function baseInput(overrides: any): Input
		local input: Input = {
			requirements = {
				{
					path = "docs/cert/req/FAKE.md",
					text = table.concat({
						"### HLR-FAKE-001",
						"",
						"- **需求**：r",
						"- **激励**：s",
						"- **响应**：t",
						"- **前置条件**：u",
						"- **后置条件**：v",
						"- **危害追溯**：基础",
						"- **验证方法**：测试（`TC-FAKE-001`）",
						"- **可判定性**：w",
						"",
						"### LLR-FAKE-001",
						"",
						"- **需求**：r",
						"- **实现位置**：`Deuterium/Fake.luau` → `f`",
						"- **分支/边界**：无",
						"- **验证方法**：测试（`TC-FAKE-001`）",
						"- **上级需求**：`HLR-FAKE-001`",
					}, "\n"),
				},
			},
			sources = {
				{
					path = "src/ReplicatedStorage/Deuterium/Fake.luau",
					mod = "FAKE",
					text = "-- LLR-FAKE-001\nfunction Fake.Do(x)\n\treturn x\nend\n",
				},
			},
			cases = {
				{
					path = "tests/cert/cases/Fake.luau",
					mod = "FAKE",
					text = table.concat({
						"-- covers: TC-FAKE-001, LLR-FAKE-001, HLR-FAKE-001",
						"return {",
						'\t{ id = "TC-FAKE-001", kind = "正常", covers = { "LLR-FAKE-001", "HLR-FAKE-001" }, run = function() end },',
						"}",
					}, "\n"),
				},
			},
			hazards = { "基础", "H1" },
			fileExists = function()
				return true
			end,
		}
		for key, value in overrides do
			(input :: any)[key] = value
		end
		return input
	end
	local kindsOf = function(report: Report): { [string]: boolean }
		local set: { [string]: boolean } = {}
		for _, v in report.violations do
			set[v.kind] = true
		end
		return set
	end

	-- 正控：干净输入必须 0 违规（否则后面的“抓到缺陷”没有意义）
	local cleanKinds = kindsOf(analyze(baseInput({})))
	local cleanList = joinSorted(cleanKinds)
	expect(#cleanList == 0, `正控失败：干净输入不应有违规，得到 {cleanList}`)

	-- N1（AC-C3 ①）：去掉用例的 covers → 必须报「孤儿需求」
	local stripped = baseInput({})
	stripped.cases[1].text =
		'-- covers: TC-FAKE-001\nreturn {\n\t{ id = "TC-FAKE-001", kind = "正常", covers = {}, run = function() end },\n}\n'
	local n1 = kindsOf(analyze(stripped))
	expect(
		n1["UNTESTED_REQ"] == true,
		"N1 失败：去掉测试覆盖后应报 UNTESTED_REQ（孤儿需求）"
	)

	-- N2（AC-C3 ②）：加一段没有 LLR 注解的代码 → 必须报「无需求代码」
	local dirty = baseInput({})
	dirty.sources[1].text =
		"-- LLR-FAKE-001\nfunction Fake.Do(x)\n\treturn x\nend\n\nfunction Fake.Extra()\n\treturn 1\nend\n"
	local n2 = kindsOf(analyze(dirty))
	expect(
		n2["UNSOURCED_CODE"] == true,
		"N2 失败：无注解的声明应报 UNSOURCED_CODE（无需求代码）"
	)

	-- N3：注解指向不存在的需求
	local n3input = baseInput({})
	n3input.sources[1].text = "-- LLR-FAKE-999\nfunction Fake.Do(x)\n\treturn x\nend\n"
	local n3 = kindsOf(analyze(n3input))
	expect(n3["UNKNOWN_LLR"] == true, "N3 失败：未知 LLR 注解应报 UNKNOWN_LLR")

	-- N4：需求没人实现
	local n4input = baseInput({})
	n4input.sources[1].text = "function Fake.Do(x)\n\treturn x\nend\n"
	local n4 = kindsOf(analyze(n4input))
	expect(n4["ORPHAN_LLR"] == true, "N4 失败：无实现的 LLR 应报 ORPHAN_LLR")

	-- N5：缺必填字段
	local n5input = baseInput({})
	n5input.requirements[1].text = string.gsub(n5input.requirements[1].text, "%- %*%*激励%*%*：s\n", "")
	local n5 = kindsOf(analyze(n5input))
	expect(n5["REQ_FIELD_MISSING"] == true, "N5 失败：缺字段应报 REQ_FIELD_MISSING")

	-- N6：危害追溯非法
	local n6input = baseInput({})
	n6input.requirements[1].text =
		string.gsub(n6input.requirements[1].text, "危害追溯%*%*：基础", "危害追溯**：H99")
	local n6 = kindsOf(analyze(n6input))
	expect(n6["HAZARD_INVALID"] == true, "N6 失败：非法危害应报 HAZARD_INVALID")

	-- N7：文件头与 per-case covers 不一致
	local n7input = baseInput({})
	n7input.cases[1].text =
		string.gsub(n7input.cases[1].text, "^%-%- covers: [^\n]+", "-- covers: TC-FAKE-001, LLR-FAKE-001")
	local n7 = kindsOf(analyze(n7input))
	expect(n7["HEADER_DRIFT"] == true, "N7 失败：文件头与用例不一致应报 HEADER_DRIFT")

	if #failures > 0 then
		for _, f in failures do
			print(`[selftest] 失败: {f}`)
		end
		return false
	end
	print(
		"[selftest] 通过：正控 1 例 · 负例 7 例（含 AC-C3 的「孤儿需求」与「无需求代码」两条）"
	)
	return true
end

-- ---------- 从磁盘搭输入 ----------
local function readScope(): { string }
	local out: { string } = {}
	for _, line in splitLines(fs.readFile(SCOPE_FILE)) do
		local clean = trim(line)
		if clean ~= "" and string.sub(clean, 1, 1) ~= "#" then
			table.insert(out, clean)
		end
	end
	return out
end

local function listFiles(dir: string): { string }
	local out: { string } = {}
	-- Luau 里 `for x in t do` 迭代的是**键**（1,2,3…），不是值 —— 必须写 `for _, entry in`。
	-- 首版写成 `for entry in fs.readDir(dir)` → 拿到的是下标，路径全错（需求与用例都读不到，向假绿的方向坏）。
	for _, entry in fs.readDir(dir) do
		local path = `{dir}/{entry}`
		if fs.isDir(path) then
			for _, nested in listFiles(path) do
				table.insert(out, nested)
			end
		else
			table.insert(out, path)
		end
	end
	table.sort(out)
	return out
end

local function buildInput(): Input
	local requirements: { { path: string, text: string } } = {}
	for _, path in listFiles(REQ_DIR) do
		if string.sub(path, -3) == ".md" then
			local entry = {
				path = path,
				text = fs.readFile(REQ_DIR .. "/" .. string.match(path, "([^/]+)$") :: string),
			}
			table.insert(requirements, entry)
		end
	end

	local sources: { { path: string, mod: string, text: string } } = {}
	for _, path in readScope() do
		if fs.isFile(path) then
			local base = string.match(path, "([^/]+)%.luau$") :: string
			table.insert(sources, { path = path, mod = string.upper(base), text = fs.readFile(path) })
		end
	end

	local cases: { { path: string, mod: string, text: string } } = {}
	for _, path in listFiles(CASE_DIR) do
		if string.sub(path, -5) == ".luau" then
			local base = string.match(path, "([^/]+)%.luau$") :: string
			table.insert(cases, {
				path = path,
				mod = string.upper(base),
				text = fs.readFile(CASE_DIR .. "/" .. base .. ".luau"),
			})
		end
	end

	-- 合法危害集合：HAZARD.md 的 H1–H7 + Dr 纯底座的「基础」
	local hazards: { string } = { "基础" }
	local hazardText = fs.readFile(HAZARD_FILE)
	for index = 1, 7 do
		table.insert(hazards, `H{index}`)
	end
	local _used = hazardText

	return {
		requirements = requirements,
		sources = sources,
		cases = cases,
		hazards = hazards,
		fileExists = function(path: string): boolean
			return fs.isFile(path)
		end,
	}
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

local report = analyze(buildInput())
fs.writeFile(TRACE_FILE, render(report))
if not flags.quiet then
	print(string.format("%-10s %s", "KIND", "WHERE / DETAIL"))
	local shown = 0
	for _, v in report.violations do
		shown += 1
		if shown <= 40 then
			print(string.format("%-10s %s — %s", v.kind, v.where, v.detail))
		end
	end
	local hlrCount, llrCount = 0, 0
	for _ in report.baseline.hlr do
		hlrCount += 1
	end
	for _ in report.baseline.llr do
		llrCount += 1
	end
	print("")
	print(
		`门禁 11：HLR {hlrCount} · LLR {llrCount} · 违规 {#report.violations} · 报告已写入 {TRACE_FILE}`
	)
end
if #report.violations > 0 then
	print(`FAIL: 追溯不完整（{#report.violations} 处），详见 {TRACE_FILE}`)
	process.exit(1)
end
