///|
test "integrity empty database" {
  let db = open(":memory:")
  let report = db.integrity_check()
  assert_true(report.ok)
  assert_eq(report.messages.length(), 0)
}

///|
test "integrity fixture" {
  let db = fixture()
  let report = db.integrity_check()
  assert_true(report.ok)
  assert_true(report.checks >= 10)
}

///|
test "database stats empty" {
  let db = open(":memory:")
  let stats = db.stats()
  assert_eq(stats.tables, 0)
  assert_eq(stats.rows, 0)
  assert_eq(stats.estimated_pages, 2)
}

///|
test "database stats fixture" {
  let stats = fixture().stats()
  assert_eq(stats.tables, 1)
  assert_eq(stats.rows, 3)
  assert_eq(stats.table_stats[0].name, "users")
  assert_eq(stats.table_stats[0].columns, 3)
}

///|
test "page directory empty" {
  let pages = open(":memory:").page_directory().unwrap()
  assert_eq(pages.length(), 2)
  assert_eq(pages[0].kind, "superblock")
  assert_eq(pages[1].kind, "catalog")
}

///|
test "page directory fixture leaf" {
  let pages = fixture().page_directory().unwrap()
  assert_eq(pages.length(), 3)
  assert_eq(pages[2].kind, "leaf")
  assert_eq(pages[2].entries, 3)
}

///|
test "page directory creates internal root" {
  let tables : Map[String, Table] = Map([])
  let tree = BTree::new()
  let payload = "01234567890123456789012345678901234567890123456789"
  for i = 0; i < 500; i = i + 1 {
    ignore(tree.append([Integer(i.to_int64()), Text(payload)]))
  }
  tables["wide"] = {
    columns: [
      { name: "id", data_type: IntegerType },
      { name: "payload", data_type: TextType },
    ],
    rows: tree,
  }
  let db : Connection = {
    path: ":memory:",
    tables,
    closed: false,
    dirty: true,
    storage_error: None,
  }
  let pages = db.page_directory().unwrap()
  assert_true(pages.length() > 4)
  assert_true(pages.iter().any(fn(page) { page.kind == "internal" }))
}

///|
test "page dump contains metadata" {
  let dump = fixture().dump_pages().unwrap()
  assert_true(dump.contains("kind=superblock"))
  assert_true(dump.contains("kind=catalog"))
  assert_true(dump.contains("kind=leaf"))
}

///|
test "roundtrip empty" {
  let report = open(":memory:").verify_roundtrip()
  assert_true(report.ok)
}

///|
test "roundtrip fixture" {
  let report = fixture().verify_roundtrip()
  assert_true(report.ok)
  assert_true(report.checks >= 5)
}

///|
test "roundtrip updated fixture" {
  let db = fixture()
  ignore(db.execute("UPDATE users SET name='Updated' WHERE id=1"))
  ignore(db.execute("DELETE FROM users WHERE id=3"))
  let report = db.verify_roundtrip()
  assert_true(report.ok)
}

///|
test "bad magic rejected" {
  let bytes = encode_database(Map([])).unwrap().to_array()
  bytes[0] = (0 : Int).to_byte()
  assert_true(decode_database(Bytes::from_array(bytes)) is Err(_))
}

///|
test "truncated file rejected" {
  let bytes = Bytes::make(PAGE_SIZE, (0 : Int).to_byte())
  assert_true(decode_database(bytes) is Err(_))
}

///|
test "unaligned file rejected" {
  let bytes = Bytes::make(PAGE_SIZE * 2 + 1, (0 : Int).to_byte())
  assert_true(decode_database(bytes) is Err(_))
}

///|
test "page count mismatch rejected" {
  let bytes = encode_database(Map([])).unwrap().to_array()
  bytes[12] = (99 : Int).to_byte()
  assert_true(decode_database(Bytes::from_array(bytes)) is Err(_))
}

///|
test "multiple tables roundtrip" {
  let db = open(":memory:")
  ignore(db.execute("CREATE TABLE a (id INTEGER)"))
  ignore(db.execute("CREATE TABLE b (name TEXT, score REAL)"))
  ignore(db.execute("INSERT INTO a VALUES (1), (2)"))
  ignore(db.execute("INSERT INTO b VALUES ('x', 1.5), ('y', 2)"))
  let report = db.verify_roundtrip()
  assert_true(report.ok)
  assert_eq(db.stats().tables, 2)
}

///|
test "unicode text roundtrip" {
  let db = open(":memory:")
  ignore(db.execute("CREATE TABLE words (id INTEGER, value TEXT)"))
  ignore(db.execute("INSERT INTO words VALUES (1, '月兔数据库')"))
  assert_true(db.verify_roundtrip().ok)
}

///|
test "null roundtrip" {
  let db = open(":memory:")
  ignore(db.execute("CREATE TABLE values_table (id INTEGER, value TEXT)"))
  ignore(db.execute("INSERT INTO values_table VALUES (1, NULL)"))
  assert_true(db.verify_roundtrip().ok)
}

///|
test "real roundtrip" {
  let db = open(":memory:")
  ignore(db.execute("CREATE TABLE measures (value REAL)"))
  ignore(db.execute("INSERT INTO measures VALUES (3.14159)"))
  assert_true(db.verify_roundtrip().ok)
}

///|
test "page size is exactly 4096" {
  assert_eq(PAGE_SIZE, 4096)
  let bytes = encode_database(Map([])).unwrap()
  assert_eq(bytes.length(), 8192)
}
///|
test "resolve_args defaults to moonsql.mdb" {
  assert_eq(resolve_args(["moonsql"]), Ok("moonsql.mdb"))
}

///|
test "resolve_args accepts --file" {
  assert_eq(resolve_args(["moonsql", "--file", "data.db"]), Ok("data.db"))
}

///|
test "resolve_args rejects unknown and dangling --file" {
  assert_true(resolve_args(["moonsql", "--wat"]) is Err(_))
  assert_true(resolve_args(["moonsql", "--file"]) is Err(_))
}
