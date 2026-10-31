--!strict
-- Tri.Spike.TriSQL —— 纵切用最小 TriSQL 编译器 + 执行器（DAL E，非认证范围，验收后可删）。
--
-- 支持三条语句就够回答接缝问题：
--   CREATE TABLE t (id INT PRIMARY KEY, name TEXT)
--   INSERT INTO t VALUES (1, 'alice')
--   SELECT name FROM t WHERE id = 1
--
-- 它同时验证三件**跨项目**的事：
--   ① TritiumSQL 依赖 Deuterium 的 FOUNDATION 是否真的可行（错误语义走 DrError）
--   ② I11（SQL 只在编译期解析）：Compile 一次，Run 多次，解析计数不增
--   ③ ResultSet 接缝（INTEGRATION.md §2.4）的形状是否够用
--
-- shortcut: 无 JOIN/无 WHERE 范围/无投影多列/无类型强制；词法器按空白与标点切分，
--           不是真 lexer。这些都归 T4–T5。

local SpikeStore = require(script.Parent.SpikeStore)
local ErrorHandler = require(script.Parent.Parent.Parent.Parent.Deuterium.Core.Foundation.ErrorHandler)

export type Column = { name: string, type: string, pk: boolean }
export type ResultSet = { columns: { string }, rows: { { any } }, affected: number }
export type DrError = any

export type Prepared = {
	sql: string,
	kind: string,
	table: string,
	columns: { Column }, -- create / insert 用
	selectColumn: string?, -- select 用
	whereColumn: string?,
	whereValue: any,
	values: { any },
}

local TriSQL = {}

local _parseCount = 0
local _schemas: { [string]: { Column } } = {}

-- ---------- 词法 ----------
-- shortcut: 只处理空白切分 + 单引号字符串 + 逗号/括号；不处理转义与多行注释
local function tokenize(sql: string): { string }
	local tokens: { string } = {}
	local i = 1
	local n = #sql
	while i <= n do
		local ch = string.sub(sql, i, i)
		if ch == " " or ch == "\t" or ch == "\n" then
			i += 1
		elseif ch == "(" or ch == ")" or ch == "," or ch == "=" then
			table.insert(tokens, ch)
			i += 1
		elseif ch == "'" then
			local close = string.find(sql, "'", i + 1, true)
			assert(close ~= nil, "[TriSQL] 未闭合的字符串字面量")
			table.insert(tokens, string.sub(sql, i, close))
			i = close + 1
		else
			local word = string.match(sql, "^[%w_%.]+", i)
			assert(word ~= nil, `[TriSQL] 无法识别的字符: {ch}`)
			table.insert(tokens, word)
			i += #word
		end
	end
	return tokens
end

local function upper(text: string): string
	return string.upper(text)
end

-- 把 `( ... )` 之间的 token 取出来（含嵌套计数）
local function group(tokens: { string }, openIndex: number): ({ string }, number)
	local depth = 0
	local out: { string } = {}
	local i = openIndex
	while i <= #tokens do
		local token = tokens[i]
		if token == "(" then
			depth += 1
			if depth > 1 then
				table.insert(out, token)
			end
		elseif token == ")" then
			depth -= 1
			if depth == 0 then
				return out, i
			end
			table.insert(out, token)
		else
			table.insert(out, token)
		end
		i += 1
	end
	error("[TriSQL] 括号不匹配", 0)
end

local function splitCommas(tokens: { string }): { { string } }
	local groups: { { string } } = {}
	local current: { string } = {}
	for _, token in tokens do
		if token == "," then
			table.insert(groups, current)
			current = {}
		else
			table.insert(current, token)
		end
	end
	table.insert(groups, current)
	return groups
end

local function literal(token: string): any
	if string.sub(token, 1, 1) == "'" then
		return string.sub(token, 2, -2)
	end
	local asNumber = tonumber(token)
	if asNumber ~= nil then
		return asNumber
	end
	if upper(token) == "TRUE" then
		return true
	elseif upper(token) == "FALSE" then
		return false
	end
	return token
end

-- ---------- 编译（I11：只在这里解析一次）----------
function TriSQL.Compile(sql: string): (Prepared?, DrError?)
	_parseCount += 1
	local tokens = tokenize(sql)
	local head = upper(tokens[1] or "")
	local prepared: Prepared = {
		sql = sql,
		kind = head,
		table = "",
		columns = {},
		values = {},
		whereValue = nil,
	}

	if head == "CREATE" and upper(tokens[2] or "") == "TABLE" then
		prepared.kind = "create"
		prepared.table = tokens[3] or ""
		local openAt = table.find(tokens, "(")
		if prepared.table == "" or openAt == nil then
			return nil, ErrorHandler.New("42601", `CREATE TABLE 语法错误: {sql}`, "TriSQL.Compile")
		end
		local body = group(tokens, openAt)
		for _, colTokens in splitCommas(body) do
			local name = colTokens[1]
			local colType = upper(colTokens[2] or "")
			local pk = false
			for _, token in colTokens do
				if upper(token) == "PRIMARY" then
					pk = true
				end
			end
			if name == nil or colType == "" then
				return nil, ErrorHandler.New("42601", `列定义不完整: {sql}`, "TriSQL.Compile")
			end
			local column: Column = { name = name, type = colType, pk = pk }
			table.insert(prepared.columns, table.freeze(column))
		end
		return table.freeze(prepared), nil
	end

	if head == "INSERT" then
		prepared.kind = "insert"
		prepared.table = tokens[3] or ""
		local openAt = table.find(tokens, "(")
		if prepared.table == "" or openAt == nil then
			return nil, ErrorHandler.New("42601", `INSERT 语法错误: {sql}`, "TriSQL.Compile")
		end
		local body = group(tokens, openAt)
		for _, one in splitCommas(body) do
			table.insert(prepared.values, literal(one[1] or ""))
		end
		return table.freeze(prepared), nil
	end

	if head == "SELECT" then
		prepared.kind = "select"
		prepared.selectColumn = tokens[2]
		prepared.table = tokens[4] or ""
		if upper(tokens[3] or "") ~= "FROM" then
			return nil,
				ErrorHandler.New(
					"42601",
					`SELECT 必须是 SELECT <col> FROM <table>: {sql}`,
					"TriSQL.Compile"
				)
		end
		if upper(tokens[5] or "") == "WHERE" then
			-- WHERE <col> = <literal>
			if tokens[6] == nil or tokens[7] ~= "=" or tokens[8] == nil then
				return nil,
					ErrorHandler.New(
						"42601",
						`本 spike 只支持 WHERE <col> = <literal>: {sql}`,
						"TriSQL.Compile"
					)
			end
			prepared.whereColumn = tokens[6]
			prepared.whereValue = literal(tokens[8])
		end
		return table.freeze(prepared), nil
	end

	-- 这里刻意用结构化错误（而不是抛），因为语句来自外部输入
	return nil, ErrorHandler.New("42601", `不支持的语句: {sql}`, "TriSQL.Compile")
end

function TriSQL.parseCount(): number
	return _parseCount
end

function TriSQL.schema(tableName: string): { Column }?
	return _schemas[tableName]
end

-- ---------- 执行（不再解析）----------
local function typeOk(colType: string, value: any): boolean
	if colType == "INT" or colType == "BIGINT" then
		return type(value) == "number"
	elseif colType == "TEXT" or colType == "VARCHAR" or colType == "JSON" then
		return type(value) == "string"
	elseif colType == "BOOL" or colType == "BOOLEAN" then
		return type(value) == "boolean"
	end
	-- 未知类型：spike 不做隐式转换，直接拒绝（TYPES.md 的转换矩阵归 T4）
	return false
end

function TriSQL.Run(prepared: Prepared, store: SpikeStore.Instance): (ResultSet?, DrError?)
	if prepared.kind == "create" then
		if _schemas[prepared.table] ~= nil then
			return nil, ErrorHandler.New("42P07", `表已存在: {prepared.table}`, "TriSQL.Run")
		end
		local pkCount = 0
		for _, col in prepared.columns do
			if col.pk then
				pkCount += 1
			end
		end
		if pkCount ~= 1 then
			return nil,
				ErrorHandler.New("42P16", `需要且仅需要一个主键: {prepared.table}`, "TriSQL.Run")
		end
		_schemas[prepared.table] = prepared.columns
		local ddl: any = table.freeze({ columns = {}, rows = {}, affected = 0 })
		return ddl, nil
	end

	local schema = _schemas[prepared.table]
	if schema == nil then
		return nil, ErrorHandler.New("42P01", `未定义的表: {prepared.table}`, "TriSQL.Run")
	end

	if prepared.kind == "insert" then
		if #prepared.values ~= #schema then
			return nil,
				ErrorHandler.New(
					"42601",
					`列数不匹配: 期望 {#schema}，得到 {#prepared.values}`,
					"TriSQL.Run"
				)
		end
		local row: { [string]: any } = {}
		local pkValue: any = nil
		for index, col in schema do
			local value = prepared.values[index]
			if value == nil and col.type ~= "TEXT" then
				return nil, ErrorHandler.New("23502", `{col.name} 不可为空`, "TriSQL.Run")
			end
			if not typeOk(col.type, value) then
				return nil, ErrorHandler.New("42804", `{col.name} 期望 {col.type}`, "TriSQL.Run")
			end
			row[col.name] = value
			if col.pk then
				pkValue = value
			end
		end
		local ok, err = store.insert(prepared.table, tostring(pkValue), row)
		if not ok then
			-- 唯一键冲突走 SQLSTATE 23505
			local code = if err == "failed:DUPLICATE_KEY" then "23505" else "58030"
			return nil, ErrorHandler.New(code, `{prepared.table} 插入失败: {tostring(err)}`, "TriSQL.Run")
		end
		local written: any = table.freeze({ columns = {}, rows = {}, affected = 1 })
		return written, nil
	end

	if prepared.kind == "select" then
		-- 语义分析：列必须存在（Analyzer 接缝）
		local hasSelect, hasWhere, whereCol: any = false, false, nil
		for _, col in schema do
			if col.name == prepared.selectColumn then
				hasSelect = true
			end
			if col.name == prepared.whereColumn then
				hasWhere = true
				whereCol = col
			end
		end
		if not hasSelect then
			return nil,
				ErrorHandler.New("42703", `列不存在: {tostring(prepared.selectColumn)}`, "TriSQL.Run")
		end
		if prepared.whereColumn ~= nil and not hasWhere then
			return nil,
				ErrorHandler.New("42703", `列不存在: {tostring(prepared.whereColumn)}`, "TriSQL.Run")
		end
		if whereCol ~= nil and not whereCol.pk then
			-- spike 只支持按主键走索引；非主键列应走全扫，而全扫还没写
			return nil, ErrorHandler.New("0A000", `spike 只支持按主键定位`, "TriSQL.Run")
		end

		-- 形状说明：先落成局部再 return（`return table.freeze({...}) :: any, nil` 会让 stylua 失去幂等）
		local found = store.findById(prepared.table, tostring(prepared.whereValue))
		if found == nil then
			local empty: any =
				table.freeze({ columns = { prepared.selectColumn :: string }, rows = {}, affected = 0 })
			return empty, nil
		end
		local hit: any = table.freeze({
			columns = { prepared.selectColumn :: string },
			rows = { { found[prepared.selectColumn :: string] } },
			affected = 0,
		})
		return hit, nil
	end

	return nil, ErrorHandler.New("0A000", `无法执行: {prepared.kind}`, "TriSQL.Run")
end

return table.freeze(TriSQL)
