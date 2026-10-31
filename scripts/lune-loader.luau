--!nocheck
-- Lune 宿主下的模块加载器：让 `require(script.Parent[.Parent]*.X)` 的模块能在无 Roblox
-- 的环境里加载并执行。
--
-- 版本演进（每一步都有实测依据，见 docs/headless.md）：
--   v1 只支持"同级兄弟" -> 认证范围的 Types/Contract/*（三级上跳）无法加载
--   v2 建**虚拟实例树** -> 任意深度可解析（认证范围首次被 headless 执行）
--   v3（本版）另外解决两件事，让"从未被执行过"的核心模块也能测：
--      a) `require` 从"恒等"改为**解析节点**：`require(script.Parent.X)` 里 X 是节点，
--         要解析成装载结果（否则 folder-module 的 init 拿不到）
--      b) 虚拟节点提供**实例方法**（WaitForChild/FindFirstChild/IsA/GetDescendants），
--         因为 Configuration/FeatureFlags/ModuleLoader 等 9 个文件用它们做存在性检查
--      c) 可选**引擎桩**：`{ engineStub = true }` 时注入一个最小 `game`，使
--         RunContext 这类加载期就用引擎的模块也能被装载（默认关闭 —— 需要暴露
--         引擎依赖的套件必须在不加桩的模式下跑，否则会把依赖藏起来）
--
-- 两个必须记住的坑（Lune 特有）：
--   * `_G` **不是**全局环境表 -> 必须显式拷标准库名字
--   * 没有 `warn` 全局 -> 必须提供，否则"失败路径"会炸成 nil call 并掩盖真错误

local fs = require("@lune/fs")
local RbxStub = require("./rbx-stub")
local process = require("@lune/process")

local Loader = {}

-- 找仓库根：从 cwd 逐级上溯，直到看见 default.project.json。
-- 为什么必须这样：fs 的路径是相对**进程 cwd** 的，而调用方可能从任意目录运行
-- （实测踩过：在 scripts/ 下运行时挂载 "src/ReplicatedStorage" 报 os error 3）。
local function findRoot(): string
	local dir = (process.cwd :: string):gsub("\\", "/")
	local candidate = dir
	for _ = 1, 8 do
		if fs.isFile(candidate .. "/default.project.json") then
			return candidate
		end
		local up = candidate:match("^(.*)/[^/]+$")
		if up == nil or up == candidate or up == "" then
			break
		end
		candidate = up
	end
	return dir
end

local REPO_ROOT = findRoot()

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

-- 当前装载选项（engineStub）。必须在 _resolve_ 里也能拿到：
-- 被依赖的模块是经 env.require -> resolve 加载的，如果不传递，只有顶层模块拿到桩，
-- 它的依赖依然会在 RunContext:8 报 “attempt to index nil with GetService”（实测）。
local currentOpts: { engineStub: boolean? } = {}
local mountRoot: string = "src/ReplicatedStorage"
local mountedNode: any = nil
local cache: { [string]: any } = {}
local inProgress: { [string]: boolean } = {}
local parentOf: { [any]: any } = {}

-- ---------- 虚拟实例树 ----------
-- node = { __node = true, path, kind = "dir"|"module", children = { name -> node } }
-- 目录若有 init.luau 则 kind = "module"（folder-module，Rojo 语义）。

local function resolve(node: any): any
	if node == nil then
		return nil
	end
	if node.kind ~= "module" then
		return node -- 普通目录：继续下钻用
	end
	local path = node.modulePath
	if cache[path] ~= nil then
		return cache[path]
	end
	if inProgress[path] then
		error(`[lune-loader] 循环依赖: {path}`, 0)
	end
	inProgress[path] = true
	-- pcall 包围：任何失败都必须清掉 inProgress，否则一次失败会永久污染后续所有装载
	-- （实测：sweep 里表现为大面积的“假循环依赖”）。
	local ok, value = pcall(function()
		local chunk = assert(loadstring(fs.readFile(`{REPO_ROOT}/{path}`) :: string, path))
		setfenv(chunk, Loader.env(node, currentOpts))
		return chunk()
	end)
	inProgress[path] = nil
	if not ok then
		error(value, 0)
	end
	cache[path] = value
	return value
end

-- __index 只做**纯查表**：不得触发 fs 读取 —— Lune 的 fs 会 yield，而**元方法里禁止跨边界
-- yield**（实测栈：__index -> childLookup -> resolve -> fs.readFile -> 报
-- “attempt to yield across metamethod/C-call boundary”）。
-- 装载统一由 env.require / Loader.load 这两个普通函数调用完成。
local function childLookup(node: any, key: any): any
	if key == "Parent" then
		return parentOf[node]
	end
	return node.children[key]
end

local function makeNode(path: string, kind: string): any
	local node = { __node = true, path = path, kind = kind, children = {} }
	setmetatable(node, {
		__index = function(self, key)
			-- 实例方法：代码里做存在性检查/类型检查用（9 个文件在用）
			if key == "WaitForChild" then
				return function(_, name: string, _timeout: number?)
					local c = self.children[name]
					if c == nil then
						error(`[lune-loader] WaitForChild 找不到 {name}（在 {self.path}）`, 0)
					end
					return c
				end
			elseif key == "FindFirstChild" then
				return function(_, name: string)
					return self.children[name]
				end
			elseif key == "IsA" then
				return function(_, className: string)
					if className == "ModuleScript" then
						return self.kind == "module"
					elseif className == "Folder" then
						return self.kind == "dir"
					end
					return false
				end
			elseif key == "GetDescendants" or key == "GetChildren" then
				return function()
					local out = {}
					for _, c in self.children do
						table.insert(out, c)
					end
					return out
				end
			end
			return childLookup(self, key)
		end,
	})
	return node
end

local function scan(dirPath: string): any
	local node = makeNode(dirPath, "dir")
	for _, entry in fs.readDir(`{REPO_ROOT}/{dirPath}`) do
		local childPath = `{dirPath}/{entry}`
		if fs.isDir(`{REPO_ROOT}/{childPath}`) then
			local child = scan(childPath)
			parentOf[child] = node
			node.children[entry] = child
		elseif string.sub(entry, -5) == ".luau" then
			local name = string.sub(entry, 1, -6)
			local child = makeNode(childPath, "module")
			child.modulePath = childPath
			parentOf[child] = node
			if name == "init" then
				node.kind = "module"
				node.modulePath = childPath
			else
				node.children[name] = child
			end
		end
	end
	return node
end

-- ---------- 环境 ----------
-- 构造一个模块的 globals 环境。scriptNode 即该模块的 script。
function Loader.env(scriptNode: any, opts: { engineStub: boolean? }?): { [string]: any }
	-- `script` 必须是**节点本身**，不能是 `{ Parent = parentOf[node] }` 这种手写小表：
	-- ① 普通模块的 `script.Parent` 本来就走节点的 __index → parentOf ✓ 等价；
	-- ② folder-module（init.luau）需要 `script.Child` 访问自己的子节点（例：
	--    Configs/Deuterium/init.luau 里的 `require(script.FeatureFlags)`）—— 手写小表取不到，
	--    后果不明显：清单静默变成空表，直到 Configuration.Section("FeatureFlags") 才报
	--    DR.CONFIG.MISSING（实测踩到）。
	local env: { [string]: any } = {}
	for _, name in COPIED do
		env[name] = GLB[name]
	end
	env.warn = GLB.warn or print
	env.script = scriptNode
	-- require：节点 -> 解析成装载结果；已是值 -> 原样返回
	env.require = function(target: any): any
		if type(target) == "table" and target.__node == true then
			return resolve(target)
		end
		return target
	end
	if opts ~= nil and opts.engineStub == true then
		RbxStub.apply(env, opts, Loader.mount())
	end
	setmetatable(env, { __index = GLB })
	return env
end

-- ---------- 对外接口 ----------
function Loader.mount(root: string?): any
	if root ~= nil then
		mountRoot = root
	end
	if mountedNode == nil then
		-- scan 全程用**仓库相对路径**，只在 fs 调用处拼 REPO_ROOT（避免双重前缀）
		mountedNode = scan(mountRoot)
	end
	return mountedNode
end

-- 按仓库相对路径装载。opts.engineStub = true 时注入最小 game 桩。
function Loader.load(filePath: string, opts: { engineStub: boolean? }?): any
	Loader.mount()
	currentOpts = opts or {} -- 供 resolve 传递（见 currentOpts 的声明）
	local rel = (string.gsub(filePath, "^" .. mountRoot .. "/", "")) :: string
	local node = mountedNode
	for segment in string.gmatch(rel, "[^/]+") do
		local name = if string.sub(segment, -5) == ".luau" then string.sub(segment, 1, -6) else segment
		node = (name == "init") and node or node.children[name]
		if node == nil then
			error(`[lune-loader] 路径解析失败: {rel}（在 {segment} 处）`, 0)
		end
	end
	if node.kind ~= "module" then
		error(`[lune-loader] 不是一个模块: {rel}`, 0)
	end
	local path = node.modulePath
	if cache[path] ~= nil then
		return cache[path]
	end
	if inProgress[path] then
		error(`[lune-loader] 循环依赖: {path}`, 0)
	end
	inProgress[path] = true
	-- 同上：pcall 包围，失败必须清 inProgress。
	-- （实测：只修 resolve 不修 load，顶层模块装载失败后 inProgress 永久残留，
	--   后续任何引用它的模块都会报“假循环依赖”。）
	local ok, value = pcall(function()
		local chunk = assert(loadstring(fs.readFile(`{REPO_ROOT}/{path}`) :: string, path))
		setfenv(chunk, Loader.env(node, currentOpts))
		return chunk()
	end)
	inProgress[path] = nil
	if not ok then
		error(value, 0)
	end
	cache[path] = value
	return value
end

-- 兼容旧用法：按顺序装载同一目录下的一组模块（顺序即拓扑序）。
function Loader.chain(dir: string, order: { string }): { [string]: any }
	local loaded: { [string]: any } = {}
	for _, name in order do
		loaded[name] = Loader.load(`{dir}/{name}.luau`)
	end
	return loaded
end

-- 列出挂载树里所有模块的仓库相对路径（用于全量装载巡检）
function Loader.listModules(): { string }
	Loader.mount()
	local out: { string } = {}
	local function walk(node: any)
		if node.kind == "module" and node.modulePath ~= nil then
			table.insert(out, node.modulePath)
		end
		for _, child in node.children do
			walk(child)
		end
	end
	walk(mountedNode)
	table.sort(out)
	return out
end

-- 清空缓存（同一进程里重复装载不同配置时用）
function Loader.reset(): ()
	cache = {}
	inProgress = {}
	mountedNode = nil
end

return Loader
