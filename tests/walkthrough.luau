--!nocheck
-- Phase 0.5 端到端纵切的独立入口（CI 也通过 tests/run.luau 的同名套件跑它）。
--
--   lune run tests/walkthrough.luau
--
-- 链路：SpikePort(内存 Port) → SpikeStore(内存页+索引) → TriSQL(Compile/Run) → 读回断言
-- 它只证明**接缝成立**，不证明引擎可用；结论见 .plan/SEAMS.md。

local Loader = require("../scripts/lune-loader")
local process = require("@lune/process")

local okLoad, walkthrough = pcall(Loader.load, "src/ReplicatedStorage/TritiumSQL/Tri/Spike/Walkthrough.luau")
if not okLoad or type(walkthrough) ~= "table" or type(walkthrough.Run) ~= "function" then
	print(`[walkthrough] 装载失败: {tostring(walkthrough)}`)
	process.exit(1)
end

local ok, summary = walkthrough.Run()
print(`[walkthrough] 结论: {tostring(summary)}`)
process.exit(if ok then 0 else 1)
