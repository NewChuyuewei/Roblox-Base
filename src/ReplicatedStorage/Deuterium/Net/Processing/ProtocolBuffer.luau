--!strict
-- Dr.Net.Processing.ProtocolBuffer
-- Schema registry. Defines are permanent; Get is one hash read; unknown schema
-- = fatal programming error with the schema name in the message.

local Serializer = require(script.Parent.Serializer)
local ErrorHandler = require(script.Parent.Parent.Parent.Core.Foundation.ErrorHandler)

local ProtocolBuffer = {}

local _schemas: { [string]: Serializer.Schema } = {}
local _locked = false

function ProtocolBuffer.Define(schema: Serializer.Schema): ()
	assert(not _locked, "[Dr.ProtocolBuffer] Define after Lock")
	assert(
		type(schema) == "table" and type(schema.name) == "string" and #schema.name > 0,
		"[Dr.ProtocolBuffer] schema needs a name"
	)
	assert(
		type(schema.fields) == "table" and #schema.fields > 0,
		`[Dr.ProtocolBuffer] schema {schema.name} needs fields`
	)
	assert(_schemas[schema.name] == nil, `[Dr.ProtocolBuffer] duplicate schema: {schema.name}`)
	local seen: { [string]: boolean } = {}
	for _, field in schema.fields do
		assert(type(field.name) == "string" and #field.name > 0, "[Dr.ProtocolBuffer] field name required")
		assert(not seen[field.name], `[Dr.ProtocolBuffer] duplicate field {field.name} in {schema.name}`)
		seen[field.name] = true
	end
	-- 同 Configuration.luau 的坑：官方 Luau 语义下 table.freeze 对**已冻结**的表会抛错。
	-- schema 是调用方传进来的（边界输入），必须容许已冻结（I17：先验后用）。
	_schemas[schema.name] = if table.isfrozen(schema) then schema else table.freeze(schema)
end

function ProtocolBuffer.Lock(): ()
	if not _locked then
		table.freeze(_schemas)
		_locked = true
	end
end

function ProtocolBuffer.Get(name: string): Serializer.Schema
	local schema = _schemas[name]
	if schema == nil then
		ErrorHandler.Raise("DR.NET.PROTO.MISSING", `schema not found: {name}`, "Dr.ProtocolBuffer")
	end
	return schema :: Serializer.Schema
end

function ProtocolBuffer.Has(name: string): boolean
	return _schemas[name] ~= nil
end

function ProtocolBuffer.IsLocked(): boolean
	return _locked
end

return table.freeze(ProtocolBuffer)
