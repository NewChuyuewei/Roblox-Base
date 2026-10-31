--!nocheck
-- Lune 宿主下的模块加载器：让 `require(script.Parent[.Parent]*.X)` 的模块能在无 Roblox
-- 的环境里加载。
--
-- v2（2026-10-25）：从"同级兄弟"升级为**虚拟实例树**。
-- 起因：认证范围的 `Types/Contract/*` 写的是 `script.Parent.Parent.Parent.Core.Foundation.ErrorHandler`
-- —— 三级上跳。v1 只能解析同级兄弟，于是**这些文件根本无法 headless 测试**。
-- 现在按仓库布局建出实例树，任意深度都成立。
--
-- 原理（全部经实测，见 docs/headless.md）：
--   1. 把 `src/ReplicatedStorage/**` 扫成一棵节点树（目录=可下钻的节点，.luau=模块）；
--   2. 每个模块 loadstring 后用 setfenv 注入 env，其中
--        script      = { Parent = <所在目录节点> }   —— 于是任意层 Parent 链可解析
--        require     = 恒等函数（script.Parent.X 求值出来已经是模块表）
--   3. 目录节点的 __index 负责：Parent 返回父节点；子目录返回节点；子模块**按需装载**（带缓存与环检测）。
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

-- ---------- 文件系统：扫成一棵节点树 ----------
-- node = { path = <目录或文件的仓库路径>, kind = "dir" | "module", children = {name->node}, }
-- 目录若有 init.luau，则该目录节点自身也是一个模块（Rojo 的 folder-module 语义）。

local parentOf: { [any]: any } = {}
local valueOf: { [any]: any } = {} -- 目录节点 -> 其 init.luau 装载结果

local function scan(dirPath: string): any
	local node = { path = dirPath, kind = "dir", children = {} }
	for _, entry in fs.readDir(dirPath) do
		local childPath = `{dirPath}/{entry}`
		if fs.isDir(childPath) then
			local child = scan(childPath)
			parentOf[child] = node
			node.children[entry] = child
		elseif string.sub(entry, -5) == ".luau" then
			local name = string.sub(entry, 1, -6)
			local child = { path = childPath, kind = "module" }
			parentOf[child] = node
			if name == "init" then
				-- folder-module：目录节点自己就是模块，children 仍要暴露
				node.kind = "module"
				node.modulePath = childPath
			else
				node.children[name] = child
			end
		end
	end
	-- 目录节点：Parent 与子节点都靠 __index 解析（用 side table 存父节点，避免与真实子名冲突）
	setmetatable(node, {
		__index = function(self, key)
			if key == "Parent" then
				return parentOf[self]
			end
			local child = self.children[key]
			if child == nil then
				return nil
			end
			return Loader.resolve(child)
		end,
	})
	return node
end

-- ---------- 装载（带缓存与环检测） ----------
local mountRoot: string? = nil
local mountedNode: any = nil
local cache: { [string]: any } = {}
local inProgress: { [string]: boolean } = {}

local function makeEnv(scriptNode: any): { [string]: any }
	local env: { [string]: any } = {}
	for _, name in COPIED do
		env[name] = GLB[name]
	end
	env.warn = GLB.warn or print
	env.script = scriptNode
	env.require = function(target: any): any
		return target
	end
	setmetatable(env, { __index = GLB })
	return env
end

-- 把节点解析成值：模块 -> 装载结果；目录 -> 节点自身（供继续下钻）
function Loader.resolve(node: any): any
	if node.kind == "dir" then
		return node
	end
	local path = node.path
	if cache[path] ~= nil then
		return cache[path]
	end
	if inProgress[path] then
		error(`[lune-loader] 循环依赖: {path}`, 0)
	end
	inProgress[path] = true
	local source = fs.readFile(path) :: string
	local chunk = assert(loadstring(source, path))
	setfenv(chunk, makeEnv({ Parent = parentOf[node] }))
	local result = chunk()
	inProgress[path] = nil
	cache[path] = result
	return result
end

-- 挂载仓库根（含 src/ReplicatedStorage）。重复调用是幂等的。
function Loader.mount(root: string?)
	local chosen = root or "src/ReplicatedStorage"
	if mountedNode ~= nil and mountRoot == chosen then
		return mountedNode
	end
	mountRoot = chosen
	mountedNode = scan(chosen)
	return mountedNode
end

-- 按仓库相对路径装载单个文件（自动挂载）。
function Loader.load(filePath: string): any
	Loader.mount()
	local rel = (string.gsub(filePath, "^" .. mountRoot .. "/", "")) :: string
	local node = mountedNode
	for segment in string.gmatch(rel, "[^/]+") do
		if node.children[segment] ~= nil then
			node = node.children[segment]
		elseif string.sub(segment, -5) == ".luau" then
			node = node.children[string.sub(segment, 1, -6)]
		else
			error(`[lune-loader] 找不到节点: {segment}（在 {rel}）`, 0)
		end
		if node == nil then
			error(`[lune-loader] 路径解析失败: {rel}`, 0)
		end
	end
	if node.kind == "dir" then
		return Loader.resolve(node)
	end
	return Loader.resolve(node)
end

-- 兼容旧的 chain 用法：按顺序装载同一目录下的一组模块（顺序即拓扑序）。
-- 返回 name -> module 的表。内部走同一棵虚拟树，因此上跳/下钻 require 都能解析。
function Loader.chain(dir: string, order: { string }): { [string]: any }
	local loaded: { [string]: any } = {}
	for _, name in order do
		loaded[name] = Loader.load(`{dir}/{name}.luau`)
	end
	return loaded
end

return Loader
