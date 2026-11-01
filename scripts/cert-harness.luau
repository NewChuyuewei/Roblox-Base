--!strict
-- 认证线用例的**共享** harness（C4 抽出）。
--
-- 为什么必须共享：验证运行器（`tests/cert/run.luau`）与覆盖工具（`scripts/coverage.luau`）
-- 必须跑**同一套断言语义**。否则"覆盖到的行"与"被验证的行为"会悄悄分叉 ——
-- 那是覆盖证据里最危险的一类假绿。
--
-- 用例协议（`tests/cert/cases/<MOD>.luau`）：
--   返回 { { id, kind, covers = {...}, run = function(t, M) end }, ... }
--   t.ok(cond, label) / t.eq(actual, expected, label) / t.throws(fn, label) / t.raises(fn, codePrefix, label)

local fs = require("@lune/fs")

local Harness = {}

Harness.CASE_DIR = "tests/cert/cases"

export type Harness = {
	checks: number,
	failures: { string },
	ok: (any, string) -> (),
	eq: (any, any, string) -> (),
	throws: (() -> (), string) -> any,
	raises: (() -> (), string?, string) -> string,
}

function Harness.new(): Harness
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
		assert(type(label) == "string" and #label > 0, "t.eq 必须带 label（三参）")
		t.checks += 1
		if actual ~= expected then
			fail(label, `期望 {tostring(expected)}，得到 {tostring(actual)}`)
		end
	end
	-- 只要求"抛了"（用于 assert 类前置条件）
	function t.throws(fn: () -> (), label: string): any
		t.checks += 1
		local ok, err = pcall(fn)
		if ok then
			fail(label, "期望抛出，但没有抛")
		end
		return err
	end
	-- 要求"抛出的是 DrError"（形状：表 + string code + string message），并校验 code 前缀
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

-- 用例文件是纯函数模块（不 require 任何东西），所以直接 loadstring 即可 ——
-- 不必让 loader 再挂一个根（一个进程只能挂一个根，而认证模块在 src/ReplicatedStorage、
-- 用例在 tests/cert/cases）。共享这份加载逻辑也避免两处解析口径不同。
function Harness.loadCases(name: string): { any }
	local path = `{Harness.CASE_DIR}/{name}.luau`
	local chunk = assert(loadstring(fs.readFile(path) :: string, path))
	return chunk()
end

-- 跑一个模块的全部用例；返回逐用例结果与累计断言数（不算 pass/fail 判定，调用方决定）。
export type CaseResult = { id: string, kind: string, covers: { string }, pass: boolean }
function Harness.runCases(cases: { any }, M: any): ({ CaseResult }, Harness)
	local t = Harness.new()
	local results: { CaseResult } = {}
	for _, case in cases do
		local before = #t.failures
		local okRun, err = pcall(case.run, t, M)
		if not okRun then
			table.insert(t.failures, `{case.id} — 用例自身抛错: {tostring(err)}`)
		end
		table.insert(results, {
			id = case.id,
			kind = case.kind,
			covers = case.covers,
			pass = #t.failures == before,
		})
	end
	return results, t
end

return table.freeze(Harness)
