--!strict
-- Dr.Net.Core.NetworkManager
-- Owns the root remote folder and the channel registry.
-- Policy: channels are declared ONCE (Construct-time). Runtime "channel not found" is fatal,
-- never silent — a misspelled channel is a programming error, not a network condition.

local RunContext = require(script.Parent.Parent.Parent.Runtime.Environment.RunContext)
local ServiceLocator = require(script.Parent.Parent.Parent.Runtime.Platform.ServiceLocator)

-- 懒取 ReplicatedStorage：加载期不碰引擎。原来在这一行直接取服务，使整条 Net 链（本模块 +
-- Channel/MultiChannel/UnreliableChannel/ClientBridge/ServerBridge/SelfTest，共 7 个）在 headless
-- 下全部无法装载；这是全量装载巡检最后一批失败（见 docs/headless.md 的指标）。
local _replicatedStorage: ReplicatedStorage? = nil
local function replicatedStorage(): ReplicatedStorage
	if _replicatedStorage == nil then
		_replicatedStorage = ServiceLocator.Get("ReplicatedStorage") :: ReplicatedStorage
	end
	return _replicatedStorage :: ReplicatedStorage
end

local NetworkManager = {}

local REMOTE_ROOT_NAME = "DrRemotes"

local _root: Folder? = nil
local _channels: { [string]: RemoteEvent? } = {}
local _declared = false

local function assertNotDeclared(): ()
	assert(not _declared, "[Dr.NetworkManager] DeclareChannels called after lock")
end

local function rootFolder(): Folder
	if _root == nil then
		_root = replicatedStorage():FindFirstChild(REMOTE_ROOT_NAME) :: Folder?
		if _root == nil then
			local f = Instance.new("Folder")
			f.Name = REMOTE_ROOT_NAME
			f.Parent = replicatedStorage()
			_root = f
		end
	end
	return _root :: Folder
end

-- Construct-time: declare the full channel list. Idempotent within Construct.
function NetworkManager.DeclareChannels(names: { string }): ()
	assertNotDeclared()
	assert(RunContext.IsServer(), "[Dr.NetworkManager] DeclareChannels is server-only")
	for _, name in names do
		assert(
			type(name) == "string" and #name > 0,
			"[Dr.NetworkManager] channel name must be non-empty string"
		)
		assert(_channels[name] == nil, `[Dr.NetworkManager] duplicate channel: {name}`)
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = rootFolder()
		_channels[name] = remote
	end
end

function NetworkManager.Lock(): ()
	if not _declared then
		table.freeze(_channels)
		_declared = true
	end
end

-- [P0] one hash read after warm-up. Server returns the live RemoteEvent;
-- client waits (once) for it to arrive — after that, it's cached forever.
function NetworkManager.GetChannel(name: string): RemoteEvent
	local remote = _channels[name]
	if remote ~= nil then
		return remote
	end
	-- After the server has locked its declarations the registry is authoritative:
	-- a miss is a programming error and must fail instantly, not stall 10s on WaitForChild.
	if _declared and RunContext.IsServer() then
		error(`[Dr.NetworkManager] unknown channel after Lock: {name}`, 2)
	end
	-- client cold path
	local folder = replicatedStorage():FindFirstChild(REMOTE_ROOT_NAME)
	assert(folder ~= nil, "[Dr.NetworkManager] DrRemotes folder missing on client - is the server booted?")
	local child = folder:WaitForChild(name, 10)
	assert(child ~= nil and child:IsA("RemoteEvent"), `[Dr.NetworkManager] channel not available: {name}`)
	_channels[name] = child :: RemoteEvent
	return child :: RemoteEvent
end

function NetworkManager.HasChannel(name: string): boolean
	return _channels[name] ~= nil
end

function NetworkManager.ChannelNames(): { string }
	local out = {}
	for name in _channels do
		table.insert(out, name)
	end
	table.sort(out)
	return table.freeze(out)
end

-- Test-only escape hatch.
function NetworkManager.Reset(): ()
	assert(RunContext.IsStudio(), "[Dr.NetworkManager] Reset is Studio-only")
	local root = rootFolder()
	root:ClearAllChildren()
	_channels = {}
	_declared = false
end

return table.freeze(NetworkManager)
