--!strict
-- Dr.Core.Lifecycle.Configuration
-- Single interface for config section access. Backed by ReplicatedStorage/Configs/Deuterium
-- (manifest module `init.luau`). Read-only, frozen, loud-on-missing.

local ErrorHandler = require(script.Parent.Parent.Foundation.ErrorHandler)

local Configuration = {}

local _manifest: { [string]: any }? = nil
local _locked = false

-- Boot-time load. Manifest must return a table of sections; each section must be a table.
function Configuration.Load(): ()
	assert(not _locked, "[Dr.Configuration] Load after manifest frozen")
	-- 相对路径而非 game:GetService：行为等价，但模块因此在 headless 下也能被真正执行
	-- （loader 的虚拟节点提供 WaitForChild/IsA）。引擎 API 仍只应出现在 Dr.Runtime（I10）。
	local configs = script.Parent.Parent.Parent.Parent:WaitForChild("Configs", 5)
	local deuterium = configs and configs:WaitForChild("Deuterium", 5)
	assert(
		deuterium ~= nil and deuterium:IsA("ModuleScript"),
		"[Dr.Configuration] Configs/Deuterium manifest module missing"
	)

	local ok, manifest = pcall(require, deuterium)
	assert(ok, `[Dr.Configuration] manifest require failed: {tostring(manifest)}`)
	assert(type(manifest) == "table", "[Dr.Configuration] manifest must return a table")

	local clean: { [string]: any } = {}
	for name, section in manifest :: { [string]: any } do
		assert(type(name) == "string", "[Dr.Configuration] manifest key must be a string")
		assert(type(section) == "table", `[Dr.Configuration] section {name} must be a table`)
		-- 必须容许“已经冻结”的 section：官方 Luau 语义下 table.freeze 对已冻结的表**会抛错**
		-- （不是幂等；已用 context7 核实官方文档）。而我们的 Configs 模块自己就会冻结 section，
		-- 所以旧写法让 Configuration.Load() 对任何规范实现的配置模块**必然抛错**。
		clean[name] = if table.isfrozen(section) then section else table.freeze(section)
	end
	_manifest = table.freeze(clean)
	_locked = true
end

-- Section read. Unknown section = programmer error, not runtime jitter.
function Configuration.Section(name: string): any
	assert(_manifest ~= nil, "[Dr.Configuration] Section() before Load()")
	local section = _manifest[name]
	if section == nil then
		ErrorHandler.Raise("DR.CONFIG.MISSING", `unknown config section: {name}`, "Dr.Configuration")
	end
	return section
end

function Configuration.IsLoaded(): boolean
	return _locked
end

function Configuration.SectionNames(): { string }
	assert(_manifest ~= nil, "[Dr.Configuration] SectionNames() before Load()")
	local out = {}
	for name in _manifest :: { [string]: any } do
		table.insert(out, name)
	end
	table.sort(out)
	return table.freeze(out)
end

return table.freeze(Configuration)
