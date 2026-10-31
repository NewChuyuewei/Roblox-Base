--!strict
-- Tri.Spike.SpikePort —— 纵切用内存 Port（DAL E，非认证范围，验收后可删）。
--
-- 目的：**验证冻结接缝**。`INTEGRATION.md` §2.1 把 Port 定型为唯一引擎触点，本文件按那个
-- 形状原样实现一遍内存版，看它是否真的够用。
-- 顺带把三态语义（I12）落实：`"queued"` / `"throttled"` / `"failed:<code>"`，
-- 成功返回 nil 作为错误位。
--
-- shortcut: 纯内存、无延迟、无真实配额；只做“请求计数 + 可注入失败”。
--           真实 DataStore 语义在 T0–T1 的 StandaloneBinding 里实现。

export type Stats = {
	requests: number,
	budget: number,
	queued: number,
}

export type Port = {
	GetAsync: (key: string) -> (any?, string?),
	SetAsync: (key: string, value: any) -> (boolean, string?),
	UpdateAsync: (key: string, transform: (any?) -> any?) -> (any?, string?),
	RemoveAsync: (key: string) -> (boolean, string?),
	Stats: () -> Stats,
	SetLimit: (base: number, perPlayer: number) -> (),
}

local SpikePort = {}

export type Instance = {
	Port: Port,
	-- 测试观测面（不属于冻结接缝，只给 spike 断言用）
	Keys: () -> { string },
	RequestCount: () -> number,
	ReadCount: () -> number,
	WriteCount: () -> number,
	FailNextWrite: (code: string?) -> (),
	Sizes: () -> { [string]: number },
}

local function new(): Instance
	local data: { [string]: any } = {}
	local sizes: { [string]: number } = {}
	local requests, reads, writes = 0, 0, 0
	local failWrite: string? = nil
	local budget = 60

	local port: Port = {
		GetAsync = function(key: string): (any?, string?)
			requests += 1
			reads += 1
			return data[key], nil
		end,
		SetAsync = function(key: string, value: any): (boolean, string?)
			requests += 1
			writes += 1
			if failWrite ~= nil then
				local code = failWrite
				failWrite = nil
				return false, `failed:{code}`
			end
			if #key > 50 then
				-- 键长硬限（SCALE.md §1.3 已核实）：返回结构化失败而不是截断
				return false, "failed:KEY_TOO_LONG"
			end
			data[key] = value
			sizes[key] = if type(value) == "string" then #value else -1
			return true, nil
		end,
		UpdateAsync = function(key: string, transform: (any?) -> any?): (any?, string?)
			requests += 1
			writes += 1
			if failWrite ~= nil then
				local code = failWrite
				failWrite = nil
				return nil, `failed:{code}`
			end
			local next_ = transform(data[key])
			data[key] = next_
			return next_, nil
		end,
		RemoveAsync = function(key: string): (boolean, string?)
			requests += 1
			writes += 1
			data[key] = nil
			sizes[key] = nil
			return true, nil
		end,
		Stats = function(): Stats
			return { requests = requests, budget = budget, queued = 0 }
		end,
		SetLimit = function(base: number, _perPlayer: number): ()
			budget = base
		end,
	}

	return {
		Port = port,
		Keys = function()
			local out: { string } = {}
			for k in data do
				table.insert(out, k)
			end
			table.sort(out)
			return out
		end,
		RequestCount = function()
			return requests
		end,
		ReadCount = function()
			return reads
		end,
		WriteCount = function()
			return writes
		end,
		FailNextWrite = function(code: string?)
			failWrite = code or "INJECTED"
		end,
		Sizes = function()
			return sizes
		end,
	}
end

SpikePort.new = new

return table.freeze(SpikePort)
