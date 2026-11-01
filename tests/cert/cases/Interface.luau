--!strict
-- covers: TC-INTERFACE-001, TC-INTERFACE-002, TC-INTERFACE-003, LLR-INTERFACE-001, HLR-INTERFACE-001
--
-- 认证线用例（见 cases/CoreTypes.luau 的文件头说明）。三类齐备：正常 / 边界 / 错误（SVP §3）。

return {
	{
		id = "TC-INTERFACE-001",
		kind = "正常",
		covers = { "LLR-INTERFACE-001", "HLR-INTERFACE-001" },
		run = function(t, M)
			local ok = M.Interface.Conform("Provider", {
				Name = "my-provider",
				Init = function() end,
				Priority = 10,
			}, { Name = "string", Init = "function", Priority = "number" })
			t.eq(ok, true, "全部字段相符时返回 true")

			-- 空 spec：恒真（没有字段要求）
			t.eq(M.Interface.Conform("Anything", {}, {}), true, "空 spec 恒真")
			t.eq(M.Interface.Conform("Anything", { x = 1 }, {}), true, "空 spec 不检查任何字段")
		end,
	},
	{
		id = "TC-INTERFACE-002",
		kind = "边界",
		covers = { "LLR-INTERFACE-001", "HLR-INTERFACE-001" },
		run = function(t, M)
			-- 边界 1：**只检查 spec 列出的字段** —— 多余字段不拒（已断言的已知行为，勿当成漏检）
			t.eq(
				M.Interface.Conform("P", { Name = "n", Extra = 999, More = {} }, { Name = "string" }),
				true,
				"未列出的字段必须被忽略"
			)

			-- 边界 2：字段缺失时 typeof(nil) == "nil"，spec 写 "nil" 即通过
			t.eq(M.Interface.Conform("P", {}, { Optional = "nil" }), true, "spec 写 nil 时缺字段可通过")
			t.eq(M.Interface.Conform("P", { Maybe = nil }, { Maybe = "nil" }), true, "显式 nil 通过")

			-- 边界 3：种类名来自 typeof（不是 type）—— table 与 userdata 的区分
			t.eq(M.Interface.Conform("P", { Bag = {} }, { Bag = "table" }), true, "table 判作 table")
		end,
	},
	{
		id = "TC-INTERFACE-003",
		kind = "错误",
		covers = { "LLR-INTERFACE-001", "HLR-INTERFACE-001" },
		run = function(t, M)
			-- 种类不符：必须抛结构化错误，且消息含 label.field 与期望/实际
			local code = t.raises(function()
				M.Interface.Conform("Provider", { Name = 42 }, { Name = "string" })
			end, "DR.CONTRACT.INTERFACE.FIELD", "种类不符必须抛错")
			t.eq(code, "DR.CONTRACT.INTERFACE.FIELD", "错误码固定")

			local _, err = pcall(M.Interface.Conform, "Provider", { Name = 42 }, { Name = "string" })
			t.ok(err ~= nil and string.find(err.message, "Provider.Name", 1, true) ~= nil, "消息含 label.field")
			t.ok(err ~= nil and string.find(err.message, "expected string", 1, true) ~= nil, "消息含期望种类")
			t.ok(err ~= nil and string.find(err.message, "got number", 1, true) ~= nil, "消息含实际种类")

			-- 前置条件：label 必须非空、value 必须是表
			t.throws(function()
				M.Interface.Conform("", { Name = "n" }, { Name = "string" })
			end, "空 label 必须被拒")
			t.throws(function()
				M.Interface.Conform("P", "not a table", {})
			end, "非表 value 必须被拒")
		end,
	},
}
