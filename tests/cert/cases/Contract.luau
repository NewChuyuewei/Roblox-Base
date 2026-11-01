--!strict
-- covers: TC-CONTRACT-001, TC-CONTRACT-001b, TC-CONTRACT-002, TC-CONTRACT-003, TC-CONTRACT-004, LLR-CONTRACT-001, LLR-CONTRACT-002, LLR-CONTRACT-003, HLR-CONTRACT-001, HLR-CONTRACT-002, HLR-CONTRACT-003
--
-- 认证线用例（见 cases/CoreTypes.luau 的文件头说明）。三类齐备：正常 / 边界 / 错误（SVP §3）。

-- 断言“抛出且抛出的是 DrError”这件事由 runner 的 harness 负责（t.raises）：
-- 用例本身不 require、不判定形状，只描述激励与期望。

return {
	{
		id = "TC-CONTRACT-001",
		kind = "正常",
		covers = { "LLR-CONTRACT-001", "HLR-CONTRACT-001", "HLR-CONTRACT-002" },
		run = function(t, M)
			-- 条件为真：必须无副作用返回（不抛、不返回值）
			t.ok(pcall(M.Contract.Precondition, true, "OK", "应当通过") == true, "Precondition(true) 不得抛错")
			t.ok(pcall(M.Contract.Invariant, true, "OK", "应当通过") == true, "Invariant(true) 不得抛错")
		end,
	},
	{
		id = "TC-CONTRACT-001b",
		kind = "边界",
		covers = { "LLR-CONTRACT-001", "LLR-CONTRACT-002", "HLR-CONTRACT-001" },
		run = function(t, M)
			-- 边界：code 传空串时前缀仍然成立（本模块不做额外校验，前缀语义不依赖内容）
			local code = t.raises(function()
				M.Contract.Precondition(false, "", "空 code")
			end, "DR.CONTRACT.PRECONDITION.", "空前缀仍成立")
			-- 边界：message 为空串不影响抛出
			t.throws(function()
				M.Contract.Precondition(false, "X", "")
			end, "空 message 仍必须抛出")
		end,
	},
	{
		id = "TC-CONTRACT-002",
		kind = "错误",
		covers = { "LLR-CONTRACT-001", "LLR-CONTRACT-002", "HLR-CONTRACT-001", "HLR-CONTRACT-002" },
		run = function(t, M)
			local pre = t.raises(function()
				M.Contract.Precondition(false, "MISSING", "缺参数")
			end, "DR.CONTRACT.PRECONDITION.MISSING", "前置条件错误码（责任方=调用方）")
			local inv = t.raises(function()
				M.Contract.Invariant(false, "BROKEN", "不变量破了")
			end, "DR.CONTRACT.INVARIANT.BROKEN", "不变量错误码（责任方=我方）")
			-- HLR-CONTRACT-002 的实质：两者必须可区分
			t.ok(pre ~= inv, "两类契约错误码必须不同")
		end,
	},
	{
		id = "TC-CONTRACT-003",
		kind = "正常",
		covers = { "LLR-CONTRACT-003", "HLR-CONTRACT-003" },
		run = function(t, M)
			-- 非 Instance 的普通类型断言
			t.ok(pcall(M.Contract.IsA, 42, "number", "NUM") == true, "number 通过")
			t.ok(pcall(M.Contract.IsA, "s", "string", "STR") == true, "string 通过")
			-- nil 必须被判成 "nil"（不能因为伪 Instance 分支而通过）
			t.ok(pcall(M.Contract.IsA, nil, "nil", "NIL") == true, "nil 对 kind=nil 通过")
			-- headless 下的伪 Instance：带 ClassName 的表 / userdata 都算 Instance
			t.ok(pcall(M.Contract.IsA, { ClassName = "Folder" }, "Instance", "INST") == true, "带 ClassName 的表算 Instance")
		end,
	},
	{
		id = "TC-CONTRACT-004",
		kind = "错误",
		covers = { "LLR-CONTRACT-003", "HLR-CONTRACT-001", "HLR-CONTRACT-003" },
		run = function(t, M)
			t.raises(function()
				M.Contract.IsA(42, "string", "MISMATCH", "应当不符")
			end, "DR.CONTRACT.TYPE.MISMATCH", "形状错误码前缀")
			-- 边界：nil **不得**被伪 Instance 分支接住
			t.raises(function()
				M.Contract.IsA(nil, "Instance", "NILNOTINST", "nil 不是 Instance")
			end, "DR.CONTRACT.TYPE.NILNOTINST", "nil 不能通过 Instance 断言（typeof(nil) == 'nil'）")
			-- 消息必须同时给出期望与实际（可判定性要求）
			local _, err = pcall(M.Contract.IsA, 42, "string", "MSG")
			t.ok(err ~= nil and string.find(err.message, "expected string", 1, true) ~= nil, "消息含 expected")
			t.ok(err ~= nil and string.find(err.message, "got number", 1, true) ~= nil, "消息含 got")
		end,
	},
}
