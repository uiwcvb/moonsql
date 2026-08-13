///|
test "format create table" {
  assert_eq(
    format_sql("create table users(id integer,name text,score real)").unwrap(),
    "CREATE TABLE users (id INTEGER, name TEXT, score REAL)",
  )
}

///|
test "format insert one row" {
  assert_eq(
    format_sql("insert into t values(1,'x',2.5)").unwrap(),
    "INSERT INTO t VALUES (1, 'x', 2.5)",
  )
}

///|
test "format insert multiple rows" {
  assert_eq(
    format_sql("insert into t values(1),(2),(3)").unwrap(),
    "INSERT INTO t VALUES (1), (2), (3)",
  )
}

///|
test "format escaped string" {
  assert_eq(
    format_sql("insert into t values('it''s')").unwrap(),
    "INSERT INTO t VALUES ('it''s')",
  )
}

///|
test "format select star" {
  assert_eq(format_sql("select*from t").unwrap(), "SELECT * FROM t")
}

///|
test "format select projection" {
  assert_eq(
    format_sql("select id,name from users").unwrap(),
    "SELECT id, name FROM users",
  )
}

///|
test "format select where" {
  assert_eq(
    format_sql("select * from t where id>=2").unwrap(),
    "SELECT * FROM t WHERE id >= 2",
  )
}

///|
test "format select boolean precedence" {
  assert_eq(
    format_sql("select * from t where a=1 or b=2 and c=3").unwrap(),
    "SELECT * FROM t WHERE a = 1 OR b = 2 AND c = 3",
  )
}

///|
test "format select parenthesized boolean" {
  assert_eq(
    format_sql("select * from t where (a=1 or b=2) and c=3").unwrap(),
    "SELECT * FROM t WHERE (a = 1 OR b = 2) AND c = 3",
  )
}

///|
test "format select not" {
  assert_eq(
    format_sql("select * from t where not id=1").unwrap(),
    "SELECT * FROM t WHERE NOT (id = 1)",
  )
}

///|
test "format order ascending explicit" {
  assert_eq(
    format_sql("select * from t order by id asc").unwrap(),
    "SELECT * FROM t ORDER BY id ASC",
  )
}

///|
test "format order ascending default" {
  assert_eq(
    format_sql("select * from t order by id").unwrap(),
    "SELECT * FROM t ORDER BY id ASC",
  )
}

///|
test "format order descending" {
  assert_eq(
    format_sql("select * from t order by id desc").unwrap(),
    "SELECT * FROM t ORDER BY id DESC",
  )
}

///|
test "format limit" {
  assert_eq(
    format_sql("select * from t limit 10").unwrap(),
    "SELECT * FROM t LIMIT 10",
  )
}

///|
test "format limit offset" {
  assert_eq(
    format_sql("select * from t limit 10 offset 5").unwrap(),
    "SELECT * FROM t LIMIT 10 OFFSET 5",
  )
}

///|
test "format update" {
  assert_eq(
    format_sql("update t set name='x',score=3 where id=1").unwrap(),
    "UPDATE t SET name = 'x', score = 3 WHERE id = 1",
  )
}

///|
test "format delete" {
  assert_eq(
    format_sql("delete from t where id<>1").unwrap(),
    "DELETE FROM t WHERE id <> 1",
  )
}

///|
test "format drop table" {
  assert_eq(format_sql("drop table t").unwrap(), "DROP TABLE t")
}

///|
test "format null" {
  assert_eq(
    format_sql("insert into t values(null)").unwrap(),
    "INSERT INTO t VALUES (NULL)",
  )
}

///|
test "outline create" {
  let outline = debug_ast("CREATE TABLE t (id INTEGER, name TEXT)").unwrap()
  assert_true(outline.contains("CreateTable"))
  assert_true(outline.contains("id: INTEGER"))
}

///|
test "outline insert" {
  let outline = debug_ast("INSERT INTO t VALUES (1), (2)").unwrap()
  assert_true(outline.contains("Insert"))
  assert_true(outline.contains("rows: 2"))
}

///|
test "outline select" {
  let outline = debug_ast(
    "SELECT id FROM t WHERE id > 1 ORDER BY id DESC LIMIT 3 OFFSET 1",
  ).unwrap()
  assert_true(outline.contains("Select"))
  assert_true(outline.contains("projection: id"))
  assert_true(outline.contains("order: id DESC"))
  assert_true(outline.contains("limit: 3"))
  assert_true(outline.contains("offset: 1"))
}

///|
test "outline update" {
  let outline = debug_ast("UPDATE t SET id=2 WHERE id=1").unwrap()
  assert_true(outline.contains("Update"))
  assert_true(outline.contains("assignments: 1"))
}

///|
test "outline delete" {
  let outline = debug_ast("DELETE FROM t WHERE id=1").unwrap()
  assert_true(outline.contains("Delete"))
  assert_true(outline.contains("filter: id = 1"))
}

///|
test "outline drop" {
  let outline = debug_ast("DROP TABLE t").unwrap()
  assert_true(outline.contains("DropTable"))
}

///|
test "format is idempotent create" {
  let once = format_sql("create table t(id integer,name text)").unwrap()
  assert_eq(format_sql(once).unwrap(), once)
}

///|
test "format is idempotent select" {
  let once = format_sql(
    "select id,name from t where id>=2 order by name desc limit 4 offset 2",
  ).unwrap()
  assert_eq(format_sql(once).unwrap(), once)
}

///|
test "format is idempotent update" {
  let once = format_sql("update t set id=2,name='x' where id=1").unwrap()
  assert_eq(format_sql(once).unwrap(), once)
}

///|
test "format accepts canonical statement" {
  assert_true(format_sql("SELECT * FROM t") is Ok(_))
}

///|
test "outline accepts canonical statement" {
  assert_true(debug_ast("DROP TABLE t") is Ok(_))
}
