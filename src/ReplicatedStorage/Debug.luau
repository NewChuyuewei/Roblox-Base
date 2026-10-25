--!strict
-- 遗留 require 垫片（DAL E，非认证范围）。
--
-- 18 个既有模块写的是 `require(ReplicatedStorage.Debug)`，所以 `ReplicatedStorage`
-- 下必须有一个叫 Debug 的 ModuleScript。
--
-- 为什么不能直接把 `Deuterium/Diagnostics/Logging/Debug.luau` 映射两次：
-- 那样会在 `ReplicatedStorage.Debug` 下产生一个**副本**，而该副本的 `script.Parent`
-- 是 `ReplicatedStorage`，于是它自身的 `require(script.Parent.Logger)` 会去找
-- `ReplicatedStorage.Logger` —— 运行时必然失败（保留相对 require 是 I16 与 headless
-- loader 的前提，所以不能靠改成绝对路径来绕过）。
-- luau-lsp 的类型检查在 2026-10-25 首次真跑时就报出了这条：
--   TypeError: Unknown require: game/ReplicatedStorage/Logger
--
-- 正解：这一层单独放一个**用绝对路径**的垫片（它不在认证范围，可以用 game:GetService），
-- 真正的实现只在 Deuterium 树里映射一次。垫片不改任何既有调用方。

local Logging = game:GetService("ReplicatedStorage"):WaitForChild("Deuterium"):WaitForChild("Diagnostics"):WaitForChild(
	"Logging"
)

return require(Logging.Debug)
