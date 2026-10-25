--!nocheck
-- Lune 宿主下的模块加载器：让 `require(script.Parent.X)` 的模块能在无 Roblox 的环境里加载。
--
-- 原理（全部经实测，见 docs/headless.md）：
--   1. 按**拓扑序**加载（依赖先加载）——这个顺序本来就要算，DependencyInjector 就是干这个的；
--   2. 每个模块：loadstring(源码) -> setfenv(chunk, env)；
--   3. env 里放 script = { Parent = <已载入的兄弟模块表> }，并把 require 换成恒等函数
--      （因为 script.Parent.X 求值出来已经是模块表本身）。
--
-- 两个必须记住的坑：
--   * Lune 里 `_G` **不是**全局环境表（`{__index=_G}` 取不到 string/table）-> 必须显式拷名字；
--   * Lune 没有 `warn` 全局 -> 必须提供，否则"测试失败"会炸成 nil call 而掩盖真错误。

local fs = require("@lune/fs")

local Loader = {}

local GLB: any = getfenv(1)
local COPIED = {
	"print",
	"warn",
	"type",
	"typeof",
	"tostring",
	"tonumber",
	"pairs",
	"ipairs",
	"next",
	"select",
	"pcall",
	"xpcall",
	"error",
	"assert",
	"rawget",
	"rawset",
	"rawequal",
	"setmetatable",
	"getmetatable",
	"string",
	"table",
	"math",
	"os",
	"coroutine",
	"utf8",
	"bit32",
	"buffer",
	"debug",
}

local function makeEnv(siblings: { [string]: any }): { [string]: any }
	local env: { [string]: any } = {}
	for _, name in COPIED do
		env[name] = GLB[name]
	end
	env.warn = GLB.warn or print
	env.script = { Parent = siblings }
	env.require = function(target: any): any
		return target
	end
	setmetatable(env, { __index = GLB })
	return env
end

-- 加载单个模块。path 为仓库相对路径（含 .luau）。
function Loader.load(path: string, siblings: { [string]: any }?): any
	local source = fs.readFile(path) :: string
	local chunk = assert(loadstring(source, path))
	setfenv(chunk, makeEnv(siblings or {}))
	return chunk()
end

-- 按顺序加载一组模块，自动把已载入的兄弟模块喂给后续模块。
-- order 必须是拓扑序（被依赖者在前）；返回 name -> module 的表。
function Loader.chain(dir: string, order: { string }): { [string]: any }
	local loaded: { [string]: any } = {}
	for _, name in order do
		loaded[name] = Loader.load(`{dir}/{name}.luau`, loaded)
	end
	return loaded
end

return Loader
