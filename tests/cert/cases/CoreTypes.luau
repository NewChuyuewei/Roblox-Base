--!strict
-- covers: TC-CORETYPES-001, TC-CORETYPES-002, TC-CORETYPES-003, LLR-CORETYPES-001, LLR-CORETYPES-002, HLR-CORETYPES-001, HLR-CORETYPES-002
--
-- 认证线用例（`docs/cert/verify/CORETYPES.md` 由 tests/cert/run.luau 生成）。
-- **不得**混入产品线测试（CERT.md §9.2）：这里不走 Dr.Testing/TestKit，也不进 tests/run.luau。
--
-- CoreTypes 是纯类型模块，没有运行时值可测；因此这里测的是**形状契约的实例**：
-- 用 ErrorHandler 造出的真实值去满足/违反 DrError、Result 的形状。

return {
	{
		id = "TC-CORETYPES-001",
		kind = "正常",
		covers = { "LLR-CORETYPES-001", "HLR-CORETYPES-001" },
		run = function(t, M)
			local err = M.ErrorHandler.New("DR.TEST.CODE", "boom", "TC/CoreTypes")
			t.eq(type(err.code), "string", "DrError.code 必须是 string")
			t.ok(#err.code > 0, "DrError.code 非空")
			t.eq(type(err.message), "string", "DrError.message 必须是 string")
			t.ok(#err.message > 0, "DrError.message 非空")
			t.ok(type(err.source) == "string" or err.source == nil, "DrError.source 是 string 或 nil")
			t.ok(table.isfrozen(err), "DrError 实例是冻结表（不可被下游改写）")
		end,
	},
	{
		id = "TC-CORETYPES-002",
		kind = "正常",
		covers = { "LLR-CORETYPES-002", "HLR-CORETYPES-002" },
		run = function(t, M)
			local ok = M.ErrorHandler.Try(function() end, "DR.FALLBACK", "TC/CoreTypes")
			t.eq(ok.ok, true, "成功路径 ok = true")
			t.eq(ok.err, nil, "成功路径 err = nil")

			local bad = M.ErrorHandler.Try(function()
				error("nope")
			end, "DR.FALLBACK", "TC/CoreTypes")
			t.eq(bad.ok, false, "失败路径 ok = false")
			t.ok(bad.err ~= nil, "失败路径必须带 err")
			t.ok(M.ErrorHandler.IsDrError(bad.err), "失败路径的 err 是 DrError")
			t.ok(table.isfrozen(bad), "Result 实例是冻结表")
		end,
	},
	{
		id = "TC-CORETYPES-003",
		kind = "边界",
		covers = { "LLR-CORETYPES-001", "LLR-CORETYPES-002", "HLR-CORETYPES-001", "HLR-CORETYPES-002" },
		run = function(t, M)
			-- 边界 1：source 缺省时字段仍存在且为 nil（形状不因缺省而变形）
			local noSource = M.ErrorHandler.New("DR.TEST.NOSRC", "no source")
			t.eq(noSource.source, nil, "缺省 source 必须是 nil")
			t.ok(M.ErrorHandler.IsDrError(noSource), "缺省 source 的实例仍是合法 DrError")

			-- 边界 2：失败值不是 DrError 时，Normalize 必须补出合法形状
			local foreign = M.ErrorHandler.Normalize("a plain string", "DR.FOREIGN", "TC/CoreTypes")
			t.ok(M.ErrorHandler.IsDrError(foreign), "外来值归一化后是 DrError")
			t.eq(foreign.code, "DR.FOREIGN", "归一化使用 fallbackCode")
			t.ok(string.find(foreign.message, "a plain string", 1, true) ~= nil, "原始信息不得丢失")

			-- 边界 3：ok = true 与 err ~= nil 的组合**不得**出现（HLR-CORETYPES-002 的后置条件）
			local combos = 0
			for _, err in { nil, noSource, foreign } do
				local r = M.ErrorHandler.Try(function() end, "DR.X")
				if r.ok == true and r.err ~= nil then
					combos += 1
				end
				local _unused = err
			end
			t.eq(combos, 0, "不得出现 ok = true 且 err ~= nil")
		end,
	},
}
