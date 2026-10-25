--!strict
-- Dr.Net.Core.ConnectionPool
-- Central ledger for every RBXScriptConnection the framework takes.
-- Destroy() on teardown releases them all; forgotten disconnects are the #1
-- production memory leak source, so this pool is mandatory, observed, and queryable.

local ConnectionPool = {}

local _conns: { RBXScriptConnection } = {}

function ConnectionPool.Give(conn: RBXScriptConnection): RBXScriptConnection
	assert(typeof(conn) == "RBXScriptConnection", "[Dr.ConnectionPool] Give expects RBXScriptConnection")
	table.insert(_conns, conn)
	return conn
end

function ConnectionPool.Discard(conn: RBXScriptConnection): boolean
	local idx = table.find(_conns, conn)
	if idx == nil then
		return false
	end
	table.remove(_conns, idx)
	conn:Disconnect()
	return true
end

function ConnectionPool.Count(): number
	local n = 0
	for _, conn in _conns do
		if conn.Connected then
			n += 1
		end
	end
	return n
end

-- Safety net for ShutdownManager: release everything still connected.
function ConnectionPool.DisconnectAll(): number
	local n = 0
	for _, conn in _conns do
		if conn.Connected then
			conn:Disconnect()
			n += 1
		end
	end
	table.clear(_conns)
	return n
end

return table.freeze(ConnectionPool)
