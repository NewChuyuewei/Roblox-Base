--!nocheck
-- headless 测试入口 —— CI 的 test 阶段跑这个。
--
-- 它只跑**能在无引擎环境里加载**的 SelfTest。引擎相关的 SelfTest 会被明确列为 SKIP
-- 并给出理由（它们需要 game，只能在 Studio 跑）。**SKIP 不是通过** —— 这里如实打印
-- 数量，免得"CI 绿"被误读成"全部都测了"。
--
-- 运行：lune run tests/run.luau

local Loader = require("../scripts/lune-loader")
local process = require("@lune/process")

-- 每个 suite：dir + 拓扑序（依赖在前，SelfTest 在最后）
local SUITES: { { name: string, dir: string, order: { string } } } = {
	{
		name = "Dr.Diagnostics.Logging",
		dir = "src/ReplicatedStorage/Deuterium/Diagnostics/Logging",
		order = { "StructuredLog", "LogSink", "Logger", "Debug", "SelfTest" },
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
print("headless 测试（Lune + 拓扑序 loader）")
print(("="):rep(72))

local passed, failed = 0, 0
for _, suite in SUITES do
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
		print(`[FAIL] {suite.name} —— RunAll()={tostring(result)}{if okRun then "" else " 抛错: " .. tostring(result)}`)
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
