--!strict
-- covers: TC-ERRORHANDLER-001, TC-ERRORHANDLER-001b, TC-ERRORHANDLER-002, TC-ERRORHANDLER-003, TC-ERRORHANDLER-004, TC-ERRORHANDLER-005, LLR-ERRORHANDLER-001, LLR-ERRORHANDLER-002, LLR-ERRORHANDLER-003, LLR-ERRORHANDLER-004, LLR-ERRORHANDLER-005, LLR-ERRORHANDLER-006, HLR-ERRORHANDLER-001, HLR-ERRORHANDLER-002, HLR-ERRORHANDLER-003, HLR-ERRORHANDLER-004
--
-- 认证线用例（见 cases/CoreTypes.luau 的文件头说明）。三类齐备：正常 / 边界 / 错误（SVP §3）。

return {
	{
		id = "TC-ERRORHANDLER-001",
		kind = "正常",
		covers = { "LLR-ERRORHANDLER-001", "HLR-ERRORHANDLER-001" },
		run = function(t, M)
			local err = M.ErrorHandler.New("DR.A.B", "something failed", "Provider/Name.Init")
			t.eq(err.code, "DR.A.B", "code 原样保留")
			t.eq(err.message, "something failed", "message 原样保留")
			t.eq(err.source, "Provider/Name.Init", "source 原样保留")
			t.ok(table.isfrozen(err), "返回冻结表（下游不可改写 code）")
		end,
	},
	{
		id = "TC-ERRORHANDLER-001b",
		kind = "边界",
		covers = { "LLR-ERRORHANDLER-001", "LLR-ERRORHANDLER-002", "HLR-ERRORHANDLER-001" },
		run = function(t, M)
			-- 边界 1：空 code / 空 message 必须被断言拦住（否则下游无法 grep）
			t.throws(function()
				M.ErrorHandler.New("", "m")
			end, "空 code 必须被拒")
			t.throws(function()
				M.ErrorHandler.New("C", "")
			end, "空 message 必须被拒")

			-- 边界 2：IsDrError 的判别（形状层）
			t.eq(M.ErrorHandler.IsDrError({ code = "C", message = "m" }), true, "最小合法 DrError")
			t.eq(M.ErrorHandler.IsDrError({ code = "C", message = "m", extra = 1 }), true, "多字段仍合法")
			t.eq(M.ErrorHandler.IsDrError({ code = "C" }), false, "缺 message 不合法")
			t.eq(M.ErrorHandler.IsDrError({ message = "m" }), false, "缺 code 不合法")
			t.eq(M.ErrorHandler.IsDrError({ code = 1, message = "m" }), false, "code 类型错不合法")
			t.eq(M.ErrorHandler.IsDrError(nil), false, "nil 不合法")
			t.eq(M.ErrorHandler.IsDrError("a string"), false, "字符串不合法")
			t.eq(M.ErrorHandler.IsDrError(42), false, "数字不合法")
		end,
	},
	{
		id = "TC-ERRORHANDLER-002",
		kind = "正常",
		covers = { "LLR-ERRORHANDLER-004", "LLR-ERRORHANDLER-002", "HLR-ERRORHANDLER-002" },
		run = function(t, M)
			local err = M.ErrorHandler.New("DR.RENDER.ME", "boom", "Src")
			local rendered = M.ErrorHandler.Render(err)
			t.ok(string.find(rendered, "DR.RENDER.ME", 1, true) ~= nil, "渲染结果必须含 code（可 grep）")
			t.ok(string.find(rendered, "\n", 1, true) == nil, "渲染结果必须单行")
			t.eq(M.ErrorHandler.Render("plain"), "plain", "字符串直通")

			-- 边界：source 缺省时渲染 ?；nil 输入渲染 "nil"；都不许抛
			local bare = M.ErrorHandler.New("DR.NO.SRC", "no source")
			t.ok(string.find(M.ErrorHandler.Render(bare), "?", 1, true) ~= nil, "缺 source 渲染 ?")
			t.eq(M.ErrorHandler.Render(nil), "nil", "nil 渲染成 'nil'")
			t.eq(M.ErrorHandler.Render(42), "42", "数字走 tostring")
			t.ok(pcall(M.ErrorHandler.Render, {}) == true, "任意表输入不得抛")
		end,
	},
	{
		id = "TC-ERRORHANDLER-003",
		kind = "正常",
		covers = { "LLR-ERRORHANDLER-006", "LLR-ERRORHANDLER-005", "HLR-ERRORHANDLER-003" },
		run = function(t, M)
			local good = M.ErrorHandler.Try(function() end, "DR.FALLBACK", "Src")
			t.eq(good.ok, true, "成功")
			t.eq(good.err, nil, "成功时 err = nil")
			t.ok(table.isfrozen(good), "Result 冻结")

			-- Raise 抛出的必须是 DrError（而不是裸字符串）
			t.raises(function()
				M.ErrorHandler.Raise("DR.RAISED", "raised message", "Src")
			end, "DR.RAISED", "Raise 必须抛 DrError")

			-- Try 必须吞掉 Raise 的抛出并给出 ok=false
			local bad = M.ErrorHandler.Try(function()
				M.ErrorHandler.Raise("DR.INNER", "inner", "Src")
			end, "DR.FALLBACK", "Src")
			t.eq(bad.ok, false, "失败")
			t.eq(bad.err.code, "DR.INNER", "我方错误必须保留原 code（不被 fallback 覆盖）")
		end,
	},
	{
		id = "TC-ERRORHANDLER-004",
		kind = "错误",
		covers = { "LLR-ERRORHANDLER-003", "LLR-ERRORHANDLER-006", "HLR-ERRORHANDLER-001", "HLR-ERRORHANDLER-003" },
		run = function(t, M)
			-- 已是我方错误：必须**原引用**返回（不重包装、不丢 code）
			local original = M.ErrorHandler.New("DR.ORIG", "orig", "Src")
			t.eq(M.ErrorHandler.Normalize(original, "DR.FALLBACK", "Src"), original, "DrError 原样返回（同一引用）")

			-- 外来值：补 fallbackCode，原始信息进 message
			local foreign = M.ErrorHandler.Normalize("a bare string", "DR.FOREIGN", "Src")
			t.eq(foreign.code, "DR.FOREIGN", "外来值用 fallbackCode")
			t.ok(string.find(foreign.message, "a bare string", 1, true) ~= nil, "原始信息不得丢失")
			t.eq(foreign.source, "Src", "source 透传")

			-- 边界：抛出的值是 nil 时也要给出合法 DrError
			local fromNil = M.ErrorHandler.Try(function()
				error(nil)
			end, "DR.NILTHROW", "Src")
			t.eq(fromNil.ok, false, "抛 nil 也算失败")
			t.ok(M.ErrorHandler.IsDrError(fromNil.err), "抛 nil 也要归一成合法 DrError")

			-- Try 不得向外抛（HLR-ERRORHANDLER-003 的实质）
			t.ok(
				pcall(M.ErrorHandler.Try, function()
					error("boom")
				end, "DR.C", "Src") == true,
				"Try 必须不向外抛"
			)
		end,
	},
	{
		id = "TC-ERRORHANDLER-005",
		kind = "边界",
		covers = { "HLR-ERRORHANDLER-004" },
		run = function(t, M)
			-- I16 的可观察形式：认证线用例**在无引擎桩下**跑，模块仍可装载且导出可调用。
			-- （加载期的引擎依赖由门禁 10 的依赖闭包检查负责；这里负责“确实没装桩”。）
			t.eq(M.meta.engineStub, false, "认证线必须在**无引擎桩**下运行（装了桩则本用例失去意义）")
			t.eq(_G.game, nil, "运行进程里不得存在 game")
			for _, name in { "New", "IsDrError", "Normalize", "Render", "Raise", "Try" } do
				t.eq(type(M.ErrorHandler[name]), "function", `导出 {name} 必须是函数`)
			end
		end,
	},
}
