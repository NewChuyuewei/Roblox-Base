--!strict
-- Tri.Spike.SpikeStore —— 纵切用的内存页 + 索引 + 行存储（DAL E，非认证范围，验收后可删）。
--
-- 它刻意把**页**放进 Port 里（而不是只放在进程内表里），因为纵切要回答的第一个问题就是
-- “页 IO 走端口时，请求次数是否可被计量”（I12）。所有页读写都经 `Port.SetAsync/GetAsync`。
--
-- 结构照抄规格（`TritiumSQL.md` §4.2 / §5）但**全部简化**：
--   Page = { pageId, tableId, partition, slots, freeSpace, nextPageId, lsn }
--   slot = { slotId, rowId, data, deleted }
--   索引 = 有序数组 + 线性定位（不是真 B+ 树）
--
-- shortcut: 索引不是 B+ 树；页不做真 4KB 字节布局（按槽位数量估算容量）；
--           无锁、无事务、无 WAL、无 MVCC。这些都归 T1–T3。

local SpikePort = require(script.Parent.SpikePort)

local SpikeStore = {}

-- ---------- 键空间（NamespaceCodec 接缝）----------
-- 规格：`tri:[db]:[table]:[partition]:[key_type]:[value]`；键名硬限 50（SCALE.md §1.3 已核实）
local Namespace = {}
function Namespace.Encode(
	db: string,
	tableName: string,
	partition: number,
	keyType: string,
	value: string
): string
	local key = `tri:{db}:{tableName}:p{partition}:{keyType}:{value}`
	assert(#key <= 50, `[Tri.Namespace] key too long ({#key} > 50)`)
	return key
end
SpikeStore.Namespace = Namespace

-- ---------- Codec 接缝 ----------
-- ⚠ 纵切发现的第一个缺口：I9 规定序列化只有一份实现 `Dr.Types.Transform.Codec`，而它属于
-- `D0.3`，**现在还不存在**。所以 spike 只能临时内联一份能用的。
-- 格式：`col<tab>类型<冒号>值<tab>col...`（平坦、可逆、易拆）
-- shortcut: 分隔符不做转义 —— 值里出现制表符直接结构化拒绝（响亮失败优于静默损坏）；
--           真实现归 I9 的 Codec（长度前缀 + 字节缓冲）。
local FIELD_SEP = "\t"

local Codec = {}

function Codec.Encode(row: { [string]: any }): string
	local cols: { any } = {}
	for k in row do
		table.insert(cols, k)
	end
	table.sort(cols, function(a, b)
		return tostring(a) < tostring(b)
	end)
	local parts: { string } = {}
	for _, k in cols do
		local v = row[k]
		local t = type(v)
		if t == "string" then
			assert(
				string.find(v, FIELD_SEP, 1, true) == nil,
				`[Tri.Codec] value contains separator at {tostring(k)}`
			)
			table.insert(parts, `{tostring(k)}{FIELD_SEP}s:{v}`)
		elseif t == "number" then
			table.insert(parts, `{tostring(k)}{FIELD_SEP}n:{tostring(v)}`)
		elseif t == "boolean" then
			table.insert(parts, `{tostring(k)}{FIELD_SEP}b:{if v then "1" else "0"}`)
		elseif t == "nil" then
			table.insert(parts, `{tostring(k)}{FIELD_SEP}z:`)
		else
			error(`[Tri.Codec] spike 只支持标量列，收到 {t}（列 {tostring(k)}）`, 0)
		end
	end
	return table.concat(parts, FIELD_SEP)
end

function Codec.Decode(text: string): { [string]: any }
	local row: { [string]: any } = {}
	local tokens: { string } = {}
	local start = 1
	while true do
		local at = string.find(text, FIELD_SEP, start, true)
		if at == nil then
			table.insert(tokens, string.sub(text, start))
			break
		end
		table.insert(tokens, string.sub(text, start, at - 1))
		start = at + #FIELD_SEP
	end
	local i = 1
	while i + 1 <= #tokens do
		local col = tokens[i]
		local tagged = tokens[i + 1]
		local kind = string.sub(tagged, 1, 1)
		local value = string.sub(tagged, 3)
		if kind == "s" then
			row[col] = value
		elseif kind == "n" then
			row[col] = tonumber(value)
		elseif kind == "b" then
			row[col] = value == "1"
		elseif kind == "z" then
			row[col] = nil
		end
		i += 2
	end
	return row
end
SpikeStore.Codec = Codec

-- ---------- 页 ----------
local PAGE_SLOT_CAPACITY = 32 -- 规格目标：4KB 页装 ≥32 典型行

export type Slot = { slotId: number, rowId: string, data: string, deleted: boolean }
export type Page = {
	pageId: string,
	tableId: string,
	partition: number,
	slots: { Slot },
	freeSpace: number,
	nextPageId: string?,
	lsn: number,
}

export type Instance = {
	insert: (tableName: string, rowId: string, row: { [string]: any }) -> (boolean, string?),
	findById: (tableName: string, rowId: string) -> { [string]: any }?,
	pageCount: () -> number,
	pageOf: (tableName: string, rowId: string) -> string?,
	indexLookups: () -> number,
	fullScans: () -> number,
	indexSize: () -> number,
	port: SpikePort.Instance,
}

local function pad(n: number): string
	local text = tostring(n)
	while #text < 4 do
		text = "0" .. text
	end
	return text
end

function SpikeStore.new(): Instance
	local port = SpikePort.new()
	local pages: { [string]: Page } = {}
	local locations: { [string]: { pageId: string, slotId: number } } = {}
	local index: { [string]: { string } } = {}
	local nextPageNo = 0
	local lookupCount, scanCount = 0, 0

	local function pageKey(tableName: string, pageId: string): string
		return Namespace.Encode("main", tableName, 0, "pg", pageId)
	end

	local function readPage(tableName: string, pageId: string): Page?
		local value = port.Port.GetAsync(pageKey(tableName, pageId))
		return (value :: any) :: Page?
	end

	local function writePage(tableName: string, page: Page): (boolean, string?)
		page.lsn += 1
		local ok, err = port.Port.SetAsync(pageKey(tableName, page.pageId), page)
		if not ok then
			page.lsn -= 1
			return false, err
		end
		return true, nil
	end

	local inst: Instance = {
		port = port,
		pageCount = function(): number
			return nextPageNo
		end,
		pageOf = function(tableName: string, rowId: string): string?
			local loc = locations[`{tableName}|{rowId}`]
			return if loc == nil then nil else loc.pageId
		end,
		indexLookups = function(): number
			return lookupCount
		end,
		fullScans = function(): number
			return scanCount
		end,
		indexSize = function(): number
			local n = 0
			for _, keys in index do
				n += #keys
			end
			return n
		end,
		insert = function(tableName: string, rowId: string, row: { [string]: any }): (boolean, string?)
			if locations[`{tableName}|{rowId}`] ~= nil then
				return false, "failed:DUPLICATE_KEY"
			end

			-- 找出第一张还有空位的页（spike：线性找，真实现走 free-space map）
			local target: Page? = nil
			for pageNo = 0, nextPageNo - 1 do
				local candidate = pages[pad(pageNo)]
				if candidate ~= nil and candidate.freeSpace > 0 then
					target = candidate
					break
				end
			end
			if target == nil then
				local fresh: Page = {
					pageId = pad(nextPageNo),
					tableId = tableName,
					partition = 0,
					slots = {},
					freeSpace = PAGE_SLOT_CAPACITY,
					nextPageId = nil,
					lsn = 0,
				}
				pages[fresh.pageId] = fresh
				nextPageNo += 1
				target = fresh
			end

			local page = target :: Page
			local slotId = #page.slots + 1
			table.insert(
				page.slots,
				table.freeze({ slotId = slotId, rowId = rowId, data = Codec.Encode(row), deleted = false })
			)
			page.freeSpace -= 1

			local ok, err = writePage(tableName, page)
			if not ok then
				-- 写失败必须回滚内存态，否则内存与“存储”会不一致
				table.remove(page.slots)
				page.freeSpace += 1
				return false, err
			end

			locations[`{tableName}|{rowId}`] = { pageId = page.pageId, slotId = slotId }

			local keys = index[tableName]
			if keys == nil then
				keys = {}
				index[tableName] = keys
			end
			table.insert(keys, rowId)
			table.sort(keys)
			-- 索引的持久化接缝（T2 才实现真 B+ 树）；这里也走 Port，因此请求次数可计量
			port.Port.SetAsync(Namespace.Encode("main", tableName, 0, "idx", "pk"), keys)
			return true, nil
		end,
		findById = function(tableName: string, rowId: string): { [string]: any }?
			-- 走索引：先查位置，再只读那一页（**不扫全表**）
			local loc = locations[`{tableName}|{rowId}`]
			if loc == nil then
				return nil
			end
			lookupCount += 1
			local page = readPage(tableName, loc.pageId)
			if page == nil then
				return nil
			end
			for _, slot in page.slots do
				if slot.slotId == loc.slotId then
					if slot.deleted then
						return nil
					end
					local decoded = Codec.Decode(slot.data)
					decoded.__rowId = slot.rowId
					decoded.__pageId = page.pageId
					return decoded
				end
			end
			return nil
		end,
	}

	return inst
end

SpikeStore.PAGE_SLOT_CAPACITY = PAGE_SLOT_CAPACITY

return table.freeze(SpikeStore)
