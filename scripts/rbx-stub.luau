--!nocheck
-- Roblox 全局桩层 —— 让 headless 环境能执行依赖 Roblox 数据类型/实例的代码。
--
-- 为什么需要：实测 Lune 0.11.1 缺 `task` / `Instance` / `Vector3` / `Vector2` / `CFrame` /
-- `Color3` / `Enum` / `Random` / `tick`（`buffer` 有）。缺了它们，Net 层与 Processing 的
-- SelfTest 只能被登记为 SKIP —— 也就是说那些代码**从未被任何环境执行过**。
--
-- 设计要点（两个容易踩的）：
--   ① `typeof`：真实 Luau 的 typeof 对普通表返回 "table"，而代码里到处是
--      `typeof(v) == "Vector3"` / `typoef(v) == "Instance"` 这类判定。所以桩值带一个
--      `__rbxType` 标记，并在 env 里**替换 typeof** 让它先看标记 —— 否则所有基于 typeof
--      的校验在桩环境下都会失败（看起来像产品 bug，其实是桩不够真）。
--   ② `Instance`：必须是**迷你实例树**（`Parent` 赋值要挂进父节点、`FindFirstChild`/
--      `WaitForChild`/`GetChildren` 要能查回来），否则 NetworkManager 的 "先建文件夹再找子节点"
--      这种正常用法会直接报 nil。
--
-- 用途边界：这些桩只用于**测试**。它们不模拟行为语义（不会真的发网络包），
-- 所以能覆盖的是"逻辑与数据流"，不是"引擎交互"。

local Stub = {}

-- ---------- 值类型 ----------
local function valueType(name: string, fields: { string }, extra: { [string]: any }?): any
	local meta = {
		__index = function(self, key)
			if extra ~= nil and extra[key] ~= nil then
				return extra[key]
			end
			return nil
		end,
		__tostring = function(self)
			local parts = {}
			for _, f in fields do
				table.insert(parts, tostring(self[f]))
			end
			return `{name}({table.concat(parts, ", ")})`
		end,
	}
	local T = {}
	T.__rbxType = name
	T.new = function(...)
		local args = table.pack(...)
		local v = { __rbxType = name }
		for index, f in fields do
			v[f] = args[index] or 0
		end
		return setmetatable(v, meta)
	end
	return T
end

Stub.Vector3 = valueType("Vector3", { "X", "Y", "Z" }, { zero = nil, one = nil })
Stub.Vector3.zero = Stub.Vector3.new(0, 0, 0)
Stub.Vector3.one = Stub.Vector3.new(1, 1, 1)
Stub.Vector3.xAxis = Stub.Vector3.new(1, 0, 0)
Stub.Vector3.yAxis = Stub.Vector3.new(0, 1, 0)
Stub.Vector3.zAxis = Stub.Vector3.new(0, 0, 1)
Stub.Vector2 = valueType("Vector2", { "X", "Y" })
Stub.Vector2.zero = Stub.Vector2.new(0, 0)
Stub.Color3 = valueType("Color3", { "R", "G", "B" })
Stub.Color3.fromRGB = function(r, g, b)
	return Stub.Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end
Stub.CFrame = valueType("CFrame", { "X", "Y", "Z" })
Stub.CFrame.new = function(x, y, z)
	local v = Stub.Vector3.new(x, y, z)
	return setmetatable({ __rbxType = "CFrame", X = v.X, Y = v.Y, Z = v.Z, Position = v }, getmetatable(v))
end
Stub.CFrame.identity = Stub.CFrame.new(0, 0, 0)

-- ---------- 迷你实例树 ----------
local INSTANCE_METHODS = {}
local function instanceMethods(node: any): any
	local meta = {
		__index = function(self, key)
			if key == "ClassName" then
				return self.__className
			end
			if INSTANCE_METHODS[key] ~= nil then
				return INSTANCE_METHODS[key]
			end
			-- 常见 RBXScriptSignal：给一个可 Connect/Fire 的假信号。
			-- 名单由实跑失败清单逼出来（InstanceTracker 要 .Destroying）。
			local SIGNALS = {
				Event = true,
				OnServerEvent = true,
				OnClientEvent = true,
				Destroying = true,
				Destroyed = true,
				AncestryChanged = true,
				Changed = true,
			}
			if SIGNALS[key] == true then
				local signal = {
					_conns = {},
					Connect = function(s, fn)
						table.insert(s._conns, fn)
						return { Disconnect = function() end, Connected = true }
					end,
					Fire = function(s, ...)
						for _, fn in s._conns do
							fn(...)
						end
					end,
				}
				self[key] = signal
				return signal
			end
			return nil
		end,
		__newindex = function(self, key, value)
			if key == "Parent" then
				local old = rawget(self, "__parent")
				if old ~= nil and old.__children ~= nil then
					local idx = table.find(old.__children, self)
					if idx ~= nil then
						table.remove(old.__children, idx)
					end
				end
				rawset(self, "__parent", value)
				if value ~= nil and value.__children ~= nil then
					table.insert(value.__children, self)
				end
				return
			end
			rawset(self, key, value)
		end,
	}
	return setmetatable(node, meta)
end

function INSTANCE_METHODS.IsA(self: any, className: string): boolean
	return self.__className == className
end
function INSTANCE_METHODS.FindFirstChild(self: any, name: string): any
	for _, c in self.__children do
		if c.Name == name then
			return c
		end
	end
	return nil
end
function INSTANCE_METHODS.WaitForChild(self: any, name: string, _timeout: number?): any
	local found = INSTANCE_METHODS.FindFirstChild(self, name)
	if found == nil then
		error(`[rbx-stub] WaitForChild 找不到 {name}（在 {self.__className}）`, 0)
	end
	return found
end
function INSTANCE_METHODS.GetChildren(self: any): { any }
	return table.clone(self.__children)
end
function INSTANCE_METHODS.GetDescendants(self: any): { any }
	local out = {}
	local function walk(n: any)
		for _, c in n.__children do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end
function INSTANCE_METHODS.Destroy(self: any): ()
	-- Roblox 语义：Destroy 先触发 Destroying（此时实例仍可访问）再断开父子并触发 Destroyed。
	-- 不触发它，InstanceTracker 的“Destroy 后自动脱落”用例就永远过不了（实跑踩到）。
	local destroying = rawget(self, "Destroying")
	if destroying ~= nil then
		destroying:Fire()
	end
	if rawget(self, "__parent") ~= nil then
		self.Parent = nil
	end
	local destroyed = rawget(self, "Destroyed")
	if destroyed ~= nil then
		destroyed:Fire()
	end
end
-- 下面这些由实跑失败清单逼出来（NetworkManager/LocalBridge/LegacyBridge/PhysicsProxy）：
function INSTANCE_METHODS.ClearAllChildren(self: any): ()
	self.__children = {}
end
function INSTANCE_METHODS.GetFullName(self: any): string
	local parts = { self.Name }
	local p = rawget(self, "__parent")
	while p ~= nil do
		table.insert(parts, 1, tostring(p.Name))
		p = rawget(p, "__parent")
	end
	return table.concat(parts, ".")
end
function INSTANCE_METHODS.FindFirstChildOfClass(self: any, className: string): any
	for _, c in self.__children do
		if c.__className == className then
			return c
		end
	end
	return nil
end
function INSTANCE_METHODS.GetAttribute(self: any, name: string): any
	return (rawget(self, "__attrs") or {})[name]
end
function INSTANCE_METHODS.SetAttribute(self: any, name: string, value: any): ()
	self.__attrs = rawget(self, "__attrs") or {}
	self.__attrs[name] = value
end
function INSTANCE_METHODS.Clone(self: any): any
	local copy = Stub.Instance.new(self.__className)
	copy.Name = self.Name
	return copy
end
-- BindableEvent/RemoteEvent 风格：Fire 即触发自己的 Event 信号
function INSTANCE_METHODS.Fire(self: any, ...: any): ()
	local signal = self.Event
	if signal ~= nil then
		signal:Fire(...)
	end
end
INSTANCE_METHODS.FireServer = INSTANCE_METHODS.Fire
INSTANCE_METHODS.FireAllClients = INSTANCE_METHODS.Fire
INSTANCE_METHODS.FireAll = INSTANCE_METHODS.Fire
INSTANCE_METHODS.FireClient = INSTANCE_METHODS.Fire
function INSTANCE_METHODS.Raycast(_self: any, _origin: any, _direction: any, _params: any): any
	return nil -- 桩环境下永不命中；让 boolean-first 返回值的用例可跑
end

Stub.Instance = {}
Stub.Instance.new = function(className: string): any
	return instanceMethods({
		__rbxType = "Instance",
		__className = className,
		__children = {},
		Name = className,
	})
end

-- 让虚拟树节点也能当实例用（ReplicatedStorage 在桩模式下就是这个）
function Stub.markAsInstance(node: any, className: string): ()
	node.__rbxType = "Instance"
	node.__className = className
	if node.__children == nil then
		node.__children = {}
		for _, c in node.children or {} do
			table.insert(node.__children, c)
		end
	end
end

-- ---------- Enum / task / typeof ----------
Stub.Enum = setmetatable({}, {
	__index = function(_, enumName)
		return setmetatable({}, {
			__index = function(_, member)
				return { Name = member, EnumType = enumName, Value = 0 }
			end,
		})
	end,
})

local realTypeof = typeof
Stub.typeof = function(v: any): string
	local t = realTypeof(v)
	if t == "table" and type(v) == "table" and rawget(v, "__rbxType") ~= nil then
		return rawget(v, "__rbxType")
	end
	return t
end

-- ---------- 组装 ----------
-- mount：ReplicatedStorage 的虚拟树根（由 loader 提供）
function Stub.apply(env: { [string]: any }, opts: { studio: boolean? }?, mount: any): ()
	local studio = opts ~= nil and opts.studio == true
	env.instance_studio = studio

	env.Vector3 = Stub.Vector3
	env.Vector2 = Stub.Vector2
	env.Color3 = Stub.Color3
	env.CFrame = Stub.CFrame
	env.Instance = Stub.Instance
	env.Enum = Stub.Enum
	env.typeof = Stub.typeof
	env.tick = function(): number
		return os.time()
	end

	local okTask, taskLib = pcall(require, "@lune/task")
	env.task = if okTask
		then taskLib
		else {
			wait = function() end,
			spawn = function(fn, ...)
				return fn(...)
			end,
			defer = function(fn, ...)
				return fn(...)
			end,
			delay = function(_, fn, ...)
				return fn(...)
			end,
			cancel = function() end,
		}

	if mount ~= nil then
		Stub.markAsInstance(mount, "ReplicatedStorage")
	end

	local runService = {
		IsServer = function()
			return studio
		end,
		IsStudio = function()
			return studio
		end,
		IsRunMode = function()
			return studio
		end,
		IsClient = function()
			return not studio
		end,
	}
	env.game = {
		GetService = function(_, serviceName: string)
			if serviceName == "ReplicatedStorage" then
				return mount
			elseif serviceName == "RunService" then
				return runService
			end
			-- 名字校验：真 Roblox 对垃圾名字报错，而 ServiceLocator 的 SelfTest 正是断言
			-- “空名字必须报错”。桩不报错会让那条用例假失败。
			if type(serviceName) ~= "string" or serviceName:match("^%a[%w]*$") == nil then
				error(string.format("[rbx-stub] invalid service name: %s", tostring(serviceName)), 0)
			end
			return instanceMethods({
				__rbxType = "Instance",
				__className = serviceName,
				__children = {},
				Name = serviceName,
			})
		end,
	}
end

return Stub
