--!nocheck
-- headless 测试入口 —— CI 的 test 阶段跑这个。
--
-- 两类 suite：
--   selftest —— 装载一组模块后跑它们的 SelfTest.RunAll()
--   checks   —— 装载一组模块后跑内联断言（用于**还没有 SelfTest 的认证范围文件**）
--
-- 引擎相关的 SelfTest 会被明确列为 SKIP 并给出理由（它们需要 game，只能在 Studio 跑）。
-- **SKIP 不是通过** —— 这里如实打印数量，免得"CI 绿"被误读成"全部都测了"。
--
-- 运行：lune run tests/run.luau

local Loader = require("../scripts/lune-loader")
local process = require("@lune/process")

local RS = "src/ReplicatedStorage"

local SUITES = {
	{
		name = "Dr.Diagnostics.Logging",
		kind = "selftest",
		dir = RS .. "/Deuterium/Diagnostics/Logging",
		order = { "StructuredLog", "LogSink", "Logger", "Debug", "SelfTest" },
	},
	{
		-- 认证范围的第一批 headless 测试。这些文件用三级上跳 require
		-- （script.Parent.Parent.Parent.Core.Foundation.ErrorHandler），
		-- loader v1 无法解析 —— 所以它们此前**从未被任何环境执行过**。
		name = "certified: Dr.Core.Foundation + Dr.Types.Contract",
		kind = "checks",
		modules = {
			RS .. "/Deuterium/Core/Foundation/CoreTypes.luau",
			RS .. "/Deuterium/Core/Foundation/ErrorHandler.luau",
			RS .. "/Deuterium/Core/Foundation/Contract.luau",
			RS .. "/Deuterium/Types/Contract/Interface.luau",
		},
		run = function(m)
			local failures = {}
			local function expect(cond, what)
				if not cond then
					table.insert(failures, what)
				end
			end

			local ErrorHandler, Contract, Interface = m.ErrorHandler, m.Contract, m.Interface

			-- ErrorHandler
			expect(ErrorHandler.IsDrError(ErrorHandler.New("DR.T", "m")), "New 产出的就是 DrError")
			expect(not ErrorHandler.IsDrError("naked string"), "字符串不是 DrError")
			expect(table.isfrozen(ErrorHandler.New("DR.T", "m")), "DrError 冻结")
			expect(ErrorHandler.Render("plain") == "plain", "字符串原样透传")
			expect(ErrorHandler.Render(ErrorHandler.New("DR.T", "m", "Src")) == "[DR.T] m @ Src", "Render 格式")
			expect(ErrorHandler.Render(ErrorHandler.New("DR.T", "m")) == "[DR.T] m @ ?", "Render 无 source 用 ?")
			expect(ErrorHandler.Normalize("boom", "DR.FALLBACK").code == "DR.FALLBACK", "外来错误套 fallback code")
			local r = ErrorHandler.Try(function()
				error("x")
			end, "DR.TRY")
			expect(r.ok == false and r.err ~= nil, "Try 捕获并结构化")
			expect(ErrorHandler.Try(function() end, "DR.TRY").ok == true, "Try 成功路径")

			-- Contract（抛错 → 用 pcall 断言）
			expect(pcall(Contract.Precondition, true, "C", "m") == true, "前置条件通过时不抛")
			expect(pcall(Contract.Precondition, false, "C", "m") == false, "前置条件失败时抛")
			expect(pcall(Contract.Invariant, false, "C", "m") == false, "不变量失败时抛")
			expect(pcall(Contract.IsA, "s", "string", "C") == true, "IsA 匹配")
			expect(pcall(Contract.IsA, 1, "string", "C") == false, "IsA 不匹配时抛")

			-- Interface.Conform（三级上跳 require 真的解析成功了，才可能跑到这里）
			local spec = { Name = "string", Init = "function" }
			expect(Interface.Conform("t", { Name = "ok", Init = function() end }, spec) == true, "形状匹配")
			expect(pcall(Interface.Conform, "t", { Name = "ok" }, spec) == false, "缺字段必须抛")
			expect(pcall(Interface.Conform, "t", { Name = "ok", Init = function() end, Extra = 1 }, spec) == true, "多字段当前不报错（已知行为）")
			expect(pcall(Interface.Conform, "t", "not a table", spec) == false, "值不是表必须抛")
			-- typeof(nil) == "nil"，所以缺少的字段报的是 "nil" 而不是崩溃
			local okErr = pcall(Interface.Conform, "t", {}, { Name = "string" })
			expect(okErr == false, "全缺字段必须抛")

			if #failures > 0 then
				for _, f in failures do
					print(`  断言失败: {f}`)
				end
			end
			return #failures == 0, `{#failures} 条断言失败`
		end,
	},
}

-- 需要 game、只能在 Studio 跑的 SelfTest（此处只登记，不跑）
local ENGINE_BOUND = {
	"src/ReplicatedStorage/Deuterium/Core/Container/SelfTest.luau",
	"src/ReplicatedStorage/Deuterium/Core/Lifecycle/SelfTest.luau",
	"src/ReplicatedStorage/Deuterium/Core/Reflection/SelfTest.luau",
	"src/ReplicatedStorage/Deuterium/Net/Core/SelfTest.luau",
	"src/ReplicatedStorage/Deuterium/Net/Processing/SelfTest.luau",
	"src/ReplicatedStorage/Deuterium/Net/Security/SelfTest.luau",
	"src/ReplicatedStorage/Deuterium/Runtime/Environment/SelfTest.luau",
	"src/ReplicatedStorage/Deuterium/Runtime/Interop/SelfTest.luau",
	"src/ReplicatedStorage/Deuterium/Runtime/Platform/SelfTest.luau",
	"src/ReplicatedStorage/Deuterium/Testing/SelfTest.luau",
}

print(("="):rep(72))
print("headless 测试（Lune + 虚拟实例树 loader）")
print(("="):rep(72))

local passed, failed = 0, 0
for _, suite in SUITES do
	if suite.kind == "selftest" then
		local okLoad, loaded = pcall(function()
			return Loader.chain(suite.dir, suite.order)
		end)
		if not okLoad then
			failed += 1
			print(`[FAIL] {suite.name} —— 加载失败: {tostring(loaded)}`)
			continue
		end
		local selfTest = loaded.SelfTest
		if selfTest == nil or type(selfTest.RunAll) ~= "function" then
			failed += 1
			print(`[FAIL] {suite.name} —— 没有 SelfTest.RunAll`)
			continue
		end
		local okRun, result = pcall(selfTest.RunAll)
		if okRun and result == true then
			passed += 1
			print(`[PASS] {suite.name}`)
		else
			failed += 1
			print(`[FAIL] {suite.name} —— RunAll()={tostring(result)}`)
		end
	else
		local byName = {}
		local okLoad, err = pcall(function()
			for _, path in suite.modules do
				local name = string.match(path, "([^/]+)%.luau$")
				byName[name] = Loader.load(path)
			end
		end)
		if not okLoad then
			failed += 1
			print(`[FAIL] {suite.name} —— 加载失败: {tostring(err)}`)
			continue
		end
		local okRun, good, detail = pcall(suite.run, byName)
		if okRun and good == true then
			passed += 1
			print(`[PASS] {suite.name}`)
		else
			failed += 1
			print(`[FAIL] {suite.name} —— {if okRun then tostring(detail) else "抛错: " .. tostring(good)}`)
		end
	end
end

print(("="):rep(72))
print(`结果：PASS {passed} · FAIL {failed} · SKIP {#ENGINE_BOUND}（需 Studio）`)
if #ENGINE_BOUND > 0 then
	print("")
	print("以下 SelfTest 未被执行（它们 require game，headless 下必然失败）：")
	for _, path in ENGINE_BOUND do
		print(`  SKIP  {path}`)
	end
	print("这是**覆盖缺口**，不是通过。认证线的目标是在受控底座上消除这类依赖（I19）。")
end
print(("="):rep(72))

if failed > 0 or passed == 0 then
	process.exit(1)
end
