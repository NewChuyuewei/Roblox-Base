--!strict
-- Dr.Net.Processing.Serializer
-- Schema-driven binary codec. A schema is a FROZEN ordered field list; pack/unpack
-- precomputes the field layout at Define time and never re-walks the spec at runtime
-- (static > dynamic, per the framework invariant).

local ErrorHandler = require(script.Parent.Parent.Parent.Core.Foundation.ErrorHandler)

export type FieldType =
	"u8"
	| "u16"
	| "u32"
	| "i8"
	| "i16"
	| "i32"
	| "f32"
	| "f64"
	| "bool"
	| "string"
	| "vec3"

export type Field = {
	name: string,
	type: FieldType,
	maxLen: number?, -- strings only; enforced on pack
}

export type Schema = {
	name: string,
	fields: { Field },
}

-- Byte sizes for the fixed-width kinds; string/vec3 computed separately.
local FIXED_SIZE: { [FieldType]: number } = {
	u8 = 1,
	u16 = 2,
	u32 = 4,
	i8 = 1,
	i16 = 2,
	i32 = 4,
	f32 = 4,
	f64 = 8,
	bool = 1,
}

local Serializer = {}

local function fieldByteSize(field: Field, value: any): number
	if field.type == "string" then
		return 4 + #value -- u32 length prefix + bytes
	elseif field.type == "vec3" then
		return 12 -- 3 × f32
	end
	return FIXED_SIZE[field.type :: FieldType]
		or error(`[Dr.Serializer] no size for field type: {field.type}`)
end

local function validateValue(field: Field, value: any)
	if value == nil then
		ErrorHandler.Raise("DR.NET.SER.NULLFIELD", `{field.name} is nil`, "Dr.Serializer")
	end
	if field.type == "string" then
		if type(value) ~= "string" then
			ErrorHandler.Raise("DR.NET.SER.TYPE", `{field.name} expected string`, "Dr.Serializer")
		end
		if field.maxLen ~= nil and #value > (field.maxLen :: number) then
			ErrorHandler.Raise(
				"DR.NET.SER.LEN",
				`{field.name} exceeds maxLen {field.maxLen}`,
				"Dr.Serializer"
			)
		end
	elseif field.type == "vec3" then
		if typeof(value) ~= "Vector3" then
			ErrorHandler.Raise("DR.NET.SER.TYPE", `{field.name} expected Vector3`, "Dr.Serializer")
		end
	elseif field.type == "bool" then
		if type(value) ~= "boolean" then
			ErrorHandler.Raise("DR.NET.SER.TYPE", `{field.name} expected boolean`, "Dr.Serializer")
		end
	else
		if type(value) ~= "number" then
			ErrorHandler.Raise(
				"DR.NET.SER.TYPE",
				`{field.name} expected number, got {type(value)}`,
				"Dr.Serializer"
			)
		end
	end
end

function Serializer.Pack(schema: Schema, values: { [string]: any }): buffer
	local total = 0
	for _, field in schema.fields do
		local value = values[field.name]
		validateValue(field, value)
		total += fieldByteSize(field, value)
	end

	local out = buffer.create(total)
	local cursor = 0
	for _, field in schema.fields do
		local value = values[field.name]
		if field.type == "string" then
			buffer.writeu32(out, cursor, #value)
			cursor += 4
			buffer.writestring(out, cursor, value, #value)
			cursor += #value
		elseif field.type == "vec3" then
			buffer.writef32(out, cursor, value.X)
			buffer.writef32(out, cursor + 4, value.Y)
			buffer.writef32(out, cursor + 8, value.Z)
			cursor += 12
		elseif field.type == "bool" then
			buffer.writeu8(out, cursor, if value then 1 else 0)
			cursor += 1
		else
			local size = fieldByteSize(field, value)
			if field.type == "u8" then
				buffer.writeu8(out, cursor, value)
			elseif field.type == "u16" then
				buffer.writeu16(out, cursor, value)
			elseif field.type == "u32" then
				buffer.writeu32(out, cursor, value)
			elseif field.type == "i8" then
				buffer.writei8(out, cursor, value)
			elseif field.type == "i16" then
				buffer.writei16(out, cursor, value)
			elseif field.type == "i32" then
				buffer.writei32(out, cursor, value)
			elseif field.type == "f32" then
				buffer.writef32(out, cursor, value)
			elseif field.type == "f64" then
				buffer.writef64(out, cursor, value)
			else
				ErrorHandler.Raise(
					"DR.NET.SER.UNKNOWNTYPE",
					`unknown field type: {field.type}`,
					"Dr.Serializer"
				)
			end
			cursor += size
		end
	end
	return out
end

function Serializer.Unpack(schema: Schema, buf: buffer): { [string]: any }
	local out: { [string]: any } = {}
	local cursor = 0
	local len = buffer.len(buf)
	for _, field in schema.fields do
		if cursor >= len then
			ErrorHandler.Raise(
				"DR.NET.SER.SHORT",
				`{schema.name}: ran out at field {field.name}`,
				"Dr.Serializer"
			)
		end
		if field.type == "string" then
			-- 先判界再读（其余字段都是这个顺序）：否则截断的缓冲会抛裸的 buffer 越界错误，
			-- 而不是结构化错误（调用方据此分不清“数据坏了”与“代码 bug”）。
			if cursor + 4 > len then
				ErrorHandler.Raise(
					"DR.NET.SER.TRUNC",
					`{schema.name}: truncated length prefix at field {field.name}`,
					"Dr.Serializer"
				)
			end
			local byteLen = buffer.readu32(buf, cursor)
			cursor += 4
			if field.maxLen ~= nil and byteLen > (field.maxLen :: number) then
				ErrorHandler.Raise(
					"DR.NET.SER.FLOODING",
					`{field.name}: declared {byteLen}B > maxLen`,
					"Dr.Serializer"
				)
			end
			if cursor + byteLen > len then
				ErrorHandler.Raise(
					"DR.NET.SER.TRUNC",
					`{field.name}: string overruns buffer`,
					"Dr.Serializer"
				)
			end
			out[field.name] = buffer.readstring(buf, cursor, byteLen)
			cursor += byteLen
		elseif field.type == "vec3" then
			if cursor + 12 > len then
				ErrorHandler.Raise("DR.NET.SER.TRUNC", `{field.name}: vec3 overruns buffer`, "Dr.Serializer")
			end
			out[field.name] = Vector3.new(
				buffer.readf32(buf, cursor),
				buffer.readf32(buf, cursor + 4),
				buffer.readf32(buf, cursor + 8)
			)
			cursor += 12
		elseif field.type == "bool" then
			out[field.name] = buffer.readu8(buf, cursor) ~= 0
			cursor += 1
		else
			local size = FIXED_SIZE[field.type :: FieldType]
			if size == nil then
				ErrorHandler.Raise(
					"DR.NET.SER.UNKNOWNTYPE",
					`unknown field type: {field.type}`,
					"Dr.Serializer"
				)
			end
			if cursor + size > len then -- bounds check BEFORE read
				ErrorHandler.Raise(
					"DR.NET.SER.TRUNC",
					`{field.name}: numeric overruns buffer`,
					"Dr.Serializer"
				)
			end
			if field.type == "u8" then
				out[field.name] = buffer.readu8(buf, cursor)
			elseif field.type == "u16" then
				out[field.name] = buffer.readu16(buf, cursor)
			elseif field.type == "u32" then
				out[field.name] = buffer.readu32(buf, cursor)
			elseif field.type == "i8" then
				out[field.name] = buffer.readi8(buf, cursor)
			elseif field.type == "i16" then
				out[field.name] = buffer.readi16(buf, cursor)
			elseif field.type == "i32" then
				out[field.name] = buffer.readi32(buf, cursor)
			elseif field.type == "f32" then
				out[field.name] = buffer.readf32(buf, cursor)
			elseif field.type == "f64" then
				out[field.name] = buffer.readf64(buf, cursor)
			end
			cursor += size
		end
	end
	-- Trailing garbage is a contract violation, not a shrug.
	if cursor ~= len then
		ErrorHandler.Raise(
			"DR.NET.SER.TRAILING",
			`{schema.name}: {len - cursor}B trailing garbage`,
			"Dr.Serializer"
		)
	end
	return out
end

return table.freeze(Serializer)
