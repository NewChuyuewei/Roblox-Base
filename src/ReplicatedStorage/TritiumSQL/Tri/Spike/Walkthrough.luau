--!strict
-- Tri.Spike.Walkthrough —— Phase 0.5 端到端纵切（DAL E，非认证范围，验收后可删）。
--
-- 目的**不是**做出能用的数据库，而是让架构接缝暴露。链路：
--   SpikePort(内存 Port) → SpikeStore(内存页 + 索引) → TriSQL(Compile/Run) → 读回断言
-- 沿途刻意去撞四条冻结接缝：Port(I12 请求计数) · Codec(I9) · NamespaceCodec(≤50 键) ·
-- ResultSet/错误语义（DrError + SQLSTATE）。
--
-- 跑法：lune run tests/walkthrough.luau
-- 结论固化在 .plan/SEAMS.md。

local SpikeStore = require(script.Parent.SpikeStore)
local TriSQL = require(script.Parent.TriSQL)
local ErrorHandler = require(script.Parent.Parent.Parent.Parent.Deuterium.Core.Foundation.ErrorHandler)

local Walkthrough = {}

local function newReport()
	local failures: { string } = {}
	local checks = 0
	return {
		expect = function(cond: boolean, what: string)
			checks += 1
			if not cond then
				table.insert(failures, what)
			end
		end,
		failures = failures,
		count = function()
			return checks
		end,
	}
end

function Walkthrough.Run(): (boolean, string)
	local r = newReport()
	local store = SpikeStore.new()
	local port = store.port

	-- ① Compile 期：CREATE TABLE
	local create, err = TriSQL.Compile("CREATE TABLE t (id INT PRIMARY KEY, name TEXT)")
	r.expect(create ~= nil, `CREATE TABLE 必须编译通过（{ErrorHandler.Render(err)}）`)
	r.expect(err == nil, "CREATE 不应返回错误")
	local created = create :: TriSQL.Prepared
	r.expect(created.kind == "create", "编译产物 kind=create")
	r.expect(#created.columns == 2, `解析出 2 列（实到 {#created.columns}）`)
	r.expect(created.columns[1].pk == true, "id 是主键")
	r.expect(created.columns[2].type == "TEXT", "name 是 TEXT")

	-- ② Run 期：建表
	local res, runErr = TriSQL.Run(created, store)
	r.expect(res ~= nil, `建表必须成功（{ErrorHandler.Render(runErr)}）`)
	r.expect(TriSQL.schema("t") ~= nil, "schema 已登记")

	-- ③ INSERT：编译 + 执行，并**计量端口请求数**（I12 接缝）
	local requestsBefore = port.RequestCount()
	local insert, ierr = TriSQL.Compile("INSERT INTO t VALUES (1, 'alice')")
	r.expect(insert ~= nil, `INSERT 必须编译通过（{ErrorHandler.Render(ierr)}）`)
	local inserted, insertErr = TriSQL.Run(insert :: TriSQL.Prepared, store)
	r.expect(
		inserted ~= nil and inserted.affected == 1,
		`INSERT 影响 1 行（{ErrorHandler.Render(insertErr)}）`
	)
	local requestsAfterInsert = port.RequestCount()
	-- 1 次页写 + 1 次索引写；这就是“请求次数可计量”的证据
	r.expect(
		requestsAfterInsert - requestsBefore == 2,
		`INSERT 应产生 2 次端口请求（页+索引），实到 {requestsAfterInsert - requestsBefore}`
	)

	-- ④ SELECT 走索引，且**不扫全表**
	local select, serr = TriSQL.Compile("SELECT name FROM t WHERE id = 1")
	r.expect(select ~= nil, `SELECT 必须编译通过（{ErrorHandler.Render(serr)}）`)
	local rows, selectErr = TriSQL.Run(select :: TriSQL.Prepared, store)
	r.expect(rows ~= nil, `SELECT 必须成功（{ErrorHandler.Render(selectErr)}）`)
	local result = rows :: any
	r.expect(#result.rows == 1, `命中 1 行（实到 {#result.rows}）`)
	r.expect(
		result.rows[1][1] == "alice",
		`读回的值必须是 alice（实到 {tostring(result.rows[1][1])}）`
	)
	r.expect(#result.columns == 1 and result.columns[1] == "name", "ResultSet 的列名是 name")
	r.expect(store.indexLookups() >= 1, "点查必须走索引")
	r.expect(store.fullScans() == 0, "点查**不得**退化成全扫")

	-- ⑤ 缺失主键：空结果集，仍不扫全表（注意要用**不存在**的 id —— 我第一版误用了 id=1）
	local absentSelect, absentErr = TriSQL.Compile("SELECT name FROM t WHERE id = 999")
	r.expect(absentSelect ~= nil, `缺失主键查询应能编译（{ErrorHandler.Render(absentErr)}）`)
	local missing, _ = TriSQL.Run(absentSelect :: TriSQL.Prepared, store)
	r.expect(#(missing :: any).rows == 0, "缺失主键返回空集")
	r.expect(store.fullScans() == 0, "缺失主键不得触发全扫")

	-- ⑥ I11：编译一次、执行多次，解析计数不增
	local parsesAfterCompiles = TriSQL.parseCount()
	for _ = 1, 3 do
		TriSQL.Run(select :: TriSQL.Prepared, store)
	end
	r.expect(TriSQL.parseCount() == parsesAfterCompiles, "Run 不得再解析（I11）")

	-- ⑦ 页：32 行装满一页，第 33 行触发新页
	local store2 = SpikeStore.new()
	TriSQL.Run(TriSQL.Compile("CREATE TABLE bulk (id INT PRIMARY KEY, name TEXT)") :: any, store2)
	local capacity = SpikeStore.PAGE_SLOT_CAPACITY
	for i = 1, capacity do
		TriSQL.Run(TriSQL.Compile(`INSERT INTO bulk VALUES ({i}, 'n{i}')`) :: any, store2)
	end
	r.expect(store2.pageCount() == 1, `{capacity} 行应装满 1 页（实到 {store2.pageCount()}）`)
	local overflow = TriSQL.Compile(`INSERT INTO bulk VALUES ({capacity + 1}, 'n{capacity + 1}')`)
	TriSQL.Run(overflow :: any, store2)
	r.expect(store2.pageCount() == 2, `第 {capacity + 1} 行应开新页（实到 {store2.pageCount()}）`)
	local last = TriSQL.Compile(`SELECT name FROM bulk WHERE id = {capacity + 1}`)
	local lastRows, lastErr = TriSQL.Run(last :: any, store2)
	r.expect(
		lastRows ~= nil and #(lastRows :: any).rows == 1,
		`新页里的行必须读得回来（{ErrorHandler.Render(lastErr)}）`
	)

	-- ⑧ 负例：类型不符 / 主键冲突 / 未定义表 / 未知列 —— 且错误必须是 DrError（跨项目错误接缝）
	local wrongType, _ = TriSQL.Compile("INSERT INTO t VALUES (2, 42)")
	local _, typeErr = TriSQL.Run(wrongType :: any, store)
	r.expect(typeErr ~= nil, "类型不符必须失败")
	r.expect(
		ErrorHandler.IsDrError(typeErr),
		"错误必须是 DrError（TritiumSQL→Dr.FOUNDATION 接缝）"
	)
	r.expect(
		tostring((typeErr :: any).code) == "42804",
		`类型错误码应为 42804（实到 {tostring((typeErr :: any).code)}）`
	)

	local dup, _ = TriSQL.Compile("INSERT INTO t VALUES (1, 'bob')")
	local _, dupErr = TriSQL.Run(dup :: any, store)
	r.expect(tostring((dupErr :: any).code) == "23505", "主键冲突应为 23505")

	local noTable, _ = TriSQL.Compile("SELECT name FROM nope WHERE id = 1")
	local _, noTableErr = TriSQL.Run(noTable :: any, store)
	r.expect(tostring((noTableErr :: any).code) == "42P01", "未定义表应为 42P01")

	local noCol, _ = TriSQL.Compile("SELECT nope FROM t WHERE id = 1")
	local _, noColErr = TriSQL.Run(noCol :: any, store)
	r.expect(tostring((noColErr :: any).code) == "42703", "未知列应为 42703")

	local badSql, badErr = TriSQL.Compile("DROP TABLE t")
	r.expect(badSql == nil and badErr ~= nil, "不支持的语句必须在**编译期**被拒")

	-- ⑨ 键长：所有落在端口里的键都必须 ≤ 50（SCALE.md §1.3 是硬限）
	local tooLong = nil
	for _, key in port.Keys() do
		if #key > 50 then
			tooLong = key
		end
	end
	r.expect(tooLong == nil, `端口里的键必须 ≤50 字符（违规: {tostring(tooLong)}）`)

	-- ⑩ 失败注入：写失败后内存态必须回滚（不留半写行）
	local store3 = SpikeStore.new()
	TriSQL.Run(TriSQL.Compile("CREATE TABLE f (id INT PRIMARY KEY, name TEXT)") :: any, store3)
	store3.port.FailNextWrite("INJECTED")
	local one, _ = TriSQL.Compile("INSERT INTO f VALUES (7, 'x')")
	local _, injectedErr = TriSQL.Run(one :: any, store3)
	r.expect(injectedErr ~= nil, "注入的写失败必须上抛")
	r.expect(store3.indexSize() == 0, "写失败不得留下索引项")
	local retry = TriSQL.Run(one :: any, store3)
	r.expect(retry ~= nil, "失败后重试应当成功（内存态已回滚）")

	local total = r.count()
	local failures = r.failures
	print(`[Tri.Walkthrough] {total - #failures}/{total} 断言通过`)
	if #failures > 0 then
		for _, f in failures do
			print(`  断言失败: {f}`)
		end
	end
	return #failures == 0, `{total - #failures}/{total}`
end

return table.freeze(Walkthrough)
