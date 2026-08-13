///|
/// Lexer tests: 20 named cases.
test "lex create" {
  let tokens = lex("CREATE TABLE t (id INTEGER)").unwrap()
  assert_eq(tokens.length(), 8)
}

///|
test "lex string escaping" {
  let tokens = lex("'it''s'").unwrap()
  assert_eq(tokens[0].kind, StringLiteral("it's"))
}

///|
test "lex integer" {
  let tokens = lex("42").unwrap()
  assert_eq(tokens[0].kind, IntegerLiteral(42L))
}

///|
test "lex real" {
  let tokens = lex("3.5").unwrap()
  assert_eq(tokens[0].kind, RealLiteral(3.5))
}

///|
test "lex operators" {
  let tokens = lex("= <> < > <= >=").unwrap()
  assert_eq(tokens.length(), 7)
}

///|
test "lex line column" {
  let tokens = lex("\nSELECT").unwrap()
  assert_eq(tokens[0].line, 2)
  assert_eq(tokens[0].column, 1)
}

///|
test "lex case insensitive keyword" {
  let tokens = lex("select").unwrap()
  assert_eq(tokens[0].kind, Keyword("SELECT"))
}

///|
test "lex identifier case preserved" {
  let tokens = lex("Camel").unwrap()
  assert_eq(tokens[0].kind, Identifier("Camel"))
}

///|
test "lex underscore" {
  let tokens = lex("a_b2").unwrap()
  assert_eq(tokens[0].kind, Identifier("a_b2"))
}

///|
test "lex punctuation" {
  let tokens = lex("(),*;").unwrap()
  assert_eq(tokens.length(), 6)
}

///|
test "lex unterminated" {
  assert_true(lex("'oops") is Err(_))
}

///|
test "lex unexpected" {
  assert_true(lex("@") is Err(_))
}

///|
test "lex insert keywords" {
  let t = lex("INSERT INTO VALUES").unwrap()
  assert_eq(t.length(), 4)
}

///|
test "lex order keywords" {
  let t = lex("ORDER BY ASC DESC").unwrap()
  assert_eq(t.length(), 5)
}

///|
test "lex bool keywords" {
  let t = lex("AND OR NOT").unwrap()
  assert_eq(t.length(), 4)
}

///|
test "lex type keywords" {
  let t = lex("INTEGER TEXT REAL").unwrap()
  assert_eq(t.length(), 4)
}

///|
test "lex whitespace" {
  let t = lex(" \t\r SELECT").unwrap()
  assert_eq(t[0].column, 5)
}

///|
test "lex empty" {
  let t = lex("").unwrap()
  assert_eq(t.length(), 1)
}

///|
test "lex negative rejected" {
  assert_true(lex("-1") is Err(_))
}

///|
test "lex quote position" {
  let t = lex("  'x'").unwrap()
  assert_eq(t[0].column, 3)
}

///|
/// Parser tests: 15 named cases.
test "parse create" {
  assert_true(
    parse("CREATE TABLE t (id INTEGER, name TEXT, score REAL)") is Ok(_),
  )
}

///|
test "parse insert one" {
  assert_true(parse("INSERT INTO t VALUES (1, 'a', 1.5)") is Ok(_))
}

///|
test "parse insert many" {
  assert_true(parse("INSERT INTO t VALUES (1), (2), (3)") is Ok(_))
}

///|
test "parse select star" {
  assert_true(parse("SELECT * FROM t") is Ok(_))
}

///|
test "parse select columns" {
  assert_true(parse("SELECT a,b FROM t") is Ok(_))
}

///|
test "parse where compare" {
  assert_true(parse("SELECT * FROM t WHERE a >= 2") is Ok(_))
}

///|
test "parse where boolean" {
  assert_true(
    parse("SELECT * FROM t WHERE NOT a = 1 OR b <> 2 AND c < 3") is Ok(_),
  )
}

///|
test "parse order asc" {
  assert_true(parse("SELECT * FROM t ORDER BY a ASC") is Ok(_))
}

///|
test "parse order desc" {
  assert_true(parse("SELECT * FROM t ORDER BY a DESC") is Ok(_))
}

///|
test "parse limit offset" {
  assert_true(parse("SELECT * FROM t LIMIT 2 OFFSET 1") is Ok(_))
}

///|
test "parse update" {
  assert_true(parse("UPDATE t SET a = 2, b = 'x' WHERE a = 1") is Ok(_))
}

///|
test "parse delete" {
  assert_true(parse("DELETE FROM t WHERE a = 1") is Ok(_))
}

///|
test "parse drop" {
  assert_true(parse("DROP TABLE t;") is Ok(_))
}

///|
test "parse bad type" {
  assert_true(parse("CREATE TABLE t (a BLOB)") is Err(_))
}

///|
test "parse trailing garbage" {
  assert_true(parse("SELECT * FROM t xyz") is Err(_))
}

///|
/// Executor tests: 15 named cases (50 total).
fn fixture() -> Connection {
  let db = open(":memory:")
  ignore(db.execute("CREATE TABLE users (id INTEGER, name TEXT, score REAL)"))
  ignore(
    db.execute(
      "INSERT INTO users VALUES (1,'Ada',9), (2,'Bob',7.5), (3,'Cy',8)",
    ),
  )
  db
}

///|
test "execute create" {
  let db = open(":memory:")
  assert_true(db.execute("CREATE TABLE t (id INTEGER)") is Ok(_))
}

///|
test "execute duplicate create" {
  let db = open(":memory:")
  ignore(db.execute("CREATE TABLE t (id INTEGER)"))
  assert_true(db.execute("CREATE TABLE t (id INTEGER)") is Err(_))
}

///|
test "execute insert" {
  let db = fixture()
  let r = db.execute("SELECT * FROM users").unwrap()
  assert_eq(r.rows.length(), 3)
}

///|
test "execute projection" {
  let db = fixture()
  let r = db.execute("SELECT name FROM users LIMIT 1").unwrap()
  assert_eq(r.columns, ["name"])
  assert_eq(r.rows[0], [Text("Ada")])
}

///|
test "execute where eq" {
  let db = fixture()
  let r = db.execute("SELECT * FROM users WHERE id = 2").unwrap()
  assert_eq(r.rows.length(), 1)
}

///|
test "execute where range" {
  let db = fixture()
  let r = db.execute("SELECT * FROM users WHERE score >= 8").unwrap()
  assert_eq(r.rows.length(), 2)
}

///|
test "execute and or" {
  let db = fixture()
  let r = db.execute("SELECT * FROM users WHERE id = 1 OR id = 3").unwrap()
  assert_eq(r.rows.length(), 2)
}

///|
test "execute not" {
  let db = fixture()
  let r = db.execute("SELECT * FROM users WHERE NOT id = 1").unwrap()
  assert_eq(r.rows.length(), 2)
}

///|
test "execute order desc" {
  let db = fixture()
  let r = db.execute("SELECT id FROM users ORDER BY score DESC").unwrap()
  assert_eq(r.rows[0], [Integer(1L)])
}

///|
test "execute offset" {
  let db = fixture()
  let r = db
    .execute("SELECT id FROM users ORDER BY id LIMIT 1 OFFSET 1")
    .unwrap()
  assert_eq(r.rows[0], [Integer(2L)])
}

///|
test "execute update" {
  let db = fixture()
  ignore(db.execute("UPDATE users SET name='Bobby' WHERE id=2"))
  let r = db.execute("SELECT name FROM users WHERE id=2").unwrap()
  assert_eq(r.rows[0], [Text("Bobby")])
}

///|
test "execute delete" {
  let db = fixture()
  ignore(db.execute("DELETE FROM users WHERE id <> 1"))
  let r = db.execute("SELECT * FROM users").unwrap()
  assert_eq(r.rows.length(), 1)
}

///|
test "execute drop" {
  let db = fixture()
  assert_true(db.execute("DROP TABLE users") is Ok(_))
  assert_true(db.execute("SELECT * FROM users") is Err(_))
}

///|
test "execute type error" {
  let db = open(":memory:")
  ignore(db.execute("CREATE TABLE t (id INTEGER)"))
  assert_true(db.execute("INSERT INTO t VALUES ('bad')") is Err(_))
}

///|
test "execute close" {
  let db = fixture()
  db.close()
  assert_true(db.execute("SELECT * FROM users") is Err(_))
}

///|
test "repl help" {
  let db = open(":memory:")
  let s = db.run_line(".help").unwrap()
  assert_true(s.length() > 0)
}

///|
test "repl tables" {
  let db = fixture()
  assert_eq(db.run_line(".tables"), Ok("users"))
}

///|
test "repl schema" {
  let db = fixture()
  assert_true(db.run_line(".schema users") is Ok(_))
}

///|
test "repl ast" {
  let db = fixture()
  assert_true(db.run_line(".ast SELECT * FROM users") is Ok(_))
}

///|
test "repl select" {
  let db = fixture()
  let s = db.run_line("SELECT name FROM users LIMIT 1").unwrap()
  assert_true(s.length() > 0)
}

///|
test "btree ten thousand rows end to end" {
  let tree = BTree::new()
  for i = 0; i < 10000; i = i + 1 {
    ignore(
      tree.append([Integer(i.to_int64()), Text("row"), Real(i.to_double())]),
    )
  }
  let rows = tree.rows()
  assert_eq(rows.length(), 10000)
  assert_eq(rows[0].1[0], Integer(0L))
  assert_eq(rows[9999].1[0], Integer(9999L))
}

///|
test "binary pager ten thousand rows roundtrip" {
  let tables : Map[String, Table] = Map([])
  let tree = BTree::new()
  for i = 0; i < 10000; i = i + 1 {
    ignore(tree.append([Integer(i.to_int64()), Text("payload")]))
  }
  tables["large"] = {
    columns: [
      { name: "id", data_type: IntegerType },
      { name: "name", data_type: TextType },
    ],
    rows: tree,
  }
  let bytes = encode_database(tables).unwrap()
  assert_true(bytes.length() % PAGE_SIZE == 0)
  let restored = decode_database(bytes).unwrap()
  assert_eq(restored["large"].rows.rows().length(), 10000)
}

///|
test "binary pager header magic" {
  let tables : Map[String, Table] = Map([])
  let bytes = encode_database(tables).unwrap()
  assert_eq(bytes.length(), PAGE_SIZE * 2)
  assert_eq(@encoding_utf8.decode(bytes[:8]), "MOONSQL1")
}
