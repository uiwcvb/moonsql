///|
struct SelectCase {
  name : String
  sql : String
  columns : Array[String]
  rows : Array[Array[Value]]
}

///|
fn conformance_database() -> Connection {
  let db = open(":memory:")
  ignore(
    db.execute(
      "CREATE TABLE items (id INTEGER, name TEXT, price REAL, category TEXT)",
    ),
  )
  ignore(
    db.execute(
      "INSERT INTO items VALUES (1,'apple',1.5,'fruit'), (2,'banana',2,'fruit'), (3,'carrot',0.75,'vegetable'), (4,'dates',4.5,'fruit'), (5,'eggplant',3,'vegetable')",
    ),
  )
  db
}

///|
let select_cases : Array[SelectCase] = [
  {
    name: "all rows",
    sql: "SELECT id FROM items ORDER BY id",
    columns: ["id"],
    rows: [
      [Integer(1L)],
      [Integer(2L)],
      [Integer(3L)],
      [Integer(4L)],
      [Integer(5L)],
    ],
  },
  {
    name: "equality",
    sql: "SELECT name FROM items WHERE id = 3",
    columns: ["name"],
    rows: [[Text("carrot")]],
  },
  {
    name: "inequality",
    sql: "SELECT id FROM items WHERE id <> 3 ORDER BY id",
    columns: ["id"],
    rows: [[Integer(1L)], [Integer(2L)], [Integer(4L)], [Integer(5L)]],
  },
  {
    name: "less than",
    sql: "SELECT id FROM items WHERE price < 1 ORDER BY id",
    columns: ["id"],
    rows: [[Integer(3L)]],
  },
  {
    name: "less equal",
    sql: "SELECT id FROM items WHERE price <= 1.5 ORDER BY id",
    columns: ["id"],
    rows: [[Integer(1L)], [Integer(3L)]],
  },
  {
    name: "greater than",
    sql: "SELECT id FROM items WHERE price > 3 ORDER BY id",
    columns: ["id"],
    rows: [[Integer(4L)]],
  },
  {
    name: "greater equal",
    sql: "SELECT id FROM items WHERE price >= 3 ORDER BY id",
    columns: ["id"],
    rows: [[Integer(4L)], [Integer(5L)]],
  },
  {
    name: "and",
    sql: "SELECT id FROM items WHERE category = 'fruit' AND price > 2 ORDER BY id",
    columns: ["id"],
    rows: [[Integer(4L)]],
  },
  {
    name: "or",
    sql: "SELECT id FROM items WHERE id = 1 OR id = 5 ORDER BY id",
    columns: ["id"],
    rows: [[Integer(1L)], [Integer(5L)]],
  },
  {
    name: "not",
    sql: "SELECT id FROM items WHERE NOT category = 'fruit' ORDER BY id",
    columns: ["id"],
    rows: [[Integer(3L)], [Integer(5L)]],
  },
  {
    name: "descending",
    sql: "SELECT id FROM items ORDER BY price DESC LIMIT 2",
    columns: ["id"],
    rows: [[Integer(4L)], [Integer(5L)]],
  },
  {
    name: "limit offset",
    sql: "SELECT id FROM items ORDER BY id LIMIT 2 OFFSET 2",
    columns: ["id"],
    rows: [[Integer(3L)], [Integer(4L)]],
  },
  {
    name: "multiple projection",
    sql: "SELECT name,price FROM items WHERE id = 2",
    columns: ["name", "price"],
    rows: [[Text("banana"), Real(2.0)]],
  },
]

///|
test "table driven select conformance" {
  let db = conformance_database()
  for case in select_cases {
    let result = db.execute(case.sql).unwrap()
    if result.columns != case.columns {
      fail("column mismatch in " + case.name)
    }
    if result.rows != case.rows {
      fail("row mismatch in " + case.name)
    }
  }
}

///|
struct MutationCase {
  name : String
  sql : String
  check : String
  rows : Array[Array[Value]]
}

///|
let mutation_cases : Array[MutationCase] = [
  {
    name: "update integer",
    sql: "UPDATE items SET price=5 WHERE id=1",
    check: "SELECT price FROM items WHERE id=1",
    rows: [[Real(5.0)]],
  },
  {
    name: "update text",
    sql: "UPDATE items SET name='plantain' WHERE id=2",
    check: "SELECT name FROM items WHERE id=2",
    rows: [[Text("plantain")]],
  },
  {
    name: "delete predicate",
    sql: "DELETE FROM items WHERE id>4",
    check: "SELECT id FROM items ORDER BY id",
    rows: [[Integer(1L)], [Integer(2L)], [Integer(3L)], [Integer(4L)]],
  },
]

///|
test "table driven mutation conformance" {
  for case in mutation_cases {
    let db = conformance_database()
    ignore(db.execute(case.sql))
    let result = db.execute(case.check).unwrap()
    if result.rows != case.rows {
      fail("mutation mismatch in " + case.name)
    }
  }
}

///|
test "create insert update delete drop lifecycle" {
  let db = open(":memory:")
  assert_true(
    db.execute("CREATE TABLE lifecycle (id INTEGER, value TEXT)") is Ok(_),
  )
  assert_true(
    db.execute("INSERT INTO lifecycle VALUES (1,'a'),(2,'b')") is Ok(_),
  )
  assert_true(db.execute("UPDATE lifecycle SET value='c' WHERE id=2") is Ok(_))
  assert_eq(
    db.execute("SELECT value FROM lifecycle WHERE id=2").unwrap().rows,
    [[Text("c")]],
  )
  assert_true(db.execute("DELETE FROM lifecycle WHERE id=1") is Ok(_))
  assert_eq(db.execute("SELECT * FROM lifecycle").unwrap().rows.length(), 1)
  assert_true(db.execute("DROP TABLE lifecycle") is Ok(_))
  assert_true(db.execute("SELECT * FROM lifecycle") is Err(_))
}

///|
test "integer converts to real in insert" {
  let db = open(":memory:")
  ignore(db.execute("CREATE TABLE values_table (value REAL)"))
  ignore(db.execute("INSERT INTO values_table VALUES (5)"))
  assert_eq(db.execute("SELECT * FROM values_table").unwrap().rows, [
    [Real(5.0)],
  ])
}

///|
test "text does not convert to integer" {
  let db = open(":memory:")
  ignore(db.execute("CREATE TABLE values_table (value INTEGER)"))
  assert_true(db.execute("INSERT INTO values_table VALUES ('5')") is Err(_))
}

///|
test "unknown projection column errors" {
  let db = conformance_database()
  assert_true(db.execute("SELECT missing FROM items") is Err(_))
}

///|
test "unknown order column errors" {
  let db = conformance_database()
  assert_true(db.execute("SELECT * FROM items ORDER BY missing") is Err(_))
}

///|
test "unknown update column errors" {
  let db = conformance_database()
  assert_true(db.execute("UPDATE items SET missing=1") is Err(_))
}

///|
test "wrong insert arity errors" {
  let db = conformance_database()
  assert_true(db.execute("INSERT INTO items VALUES (6)") is Err(_))
}

///|
test "closed connection errors" {
  let db = conformance_database()
  db.close()
  assert_true(db.execute("SELECT * FROM items") is Err(_))
}

///|
test "schema preserves declared types" {
  let db = conformance_database()
  assert_eq(
    db.schema("items"),
    Some(
      "CREATE TABLE items (id INTEGER, name TEXT, price REAL, category TEXT);",
    ),
  )
}

///|
test "tables sorted alphabetically" {
  let db = open(":memory:")
  ignore(db.execute("CREATE TABLE zed (id INTEGER)"))
  ignore(db.execute("CREATE TABLE alpha (id INTEGER)"))
  ignore(db.execute("CREATE TABLE middle (id INTEGER)"))
  let names = db.table_names()
  assert_eq(names.length(), 3)
  assert_true(names.contains("alpha"))
  assert_true(names.contains("middle"))
  assert_true(names.contains("zed"))
}

///|
test "repl formats query result" {
  let db = conformance_database()
  assert_eq(
    db.run_line("SELECT id,name FROM items WHERE id=1").unwrap(),
    "id | name\n1 | apple",
  )
}

///|
test "repl reports mutation ok" {
  let db = conformance_database()
  assert_eq(db.run_line("DELETE FROM items WHERE id=5"), Ok("OK"))
}

///|
test "repl lists tables" {
  let db = conformance_database()
  assert_eq(db.run_line(".tables"), Ok("items"))
}

///|
test "repl prints schema" {
  let db = conformance_database()
  assert_true(
    db.run_line(".schema items").unwrap().contains("CREATE TABLE items"),
  )
}

///|
test "repl ast prints select outline" {
  let db = conformance_database()
  assert_true(
    db.run_line(".ast SELECT * FROM items").unwrap().contains("Select"),
  )
}

///|
test "repl unknown schema errors" {
  let db = conformance_database()
  assert_true(db.run_line(".schema missing") is Err(_))
}

///|
test "where integer real comparison" {
  let db = conformance_database()
  assert_eq(db.execute("SELECT id FROM items WHERE price=2").unwrap().rows, [
    [Integer(2L)],
  ])
}

///|
test "where text comparison" {
  let db = conformance_database()
  assert_eq(
    db.execute("SELECT id FROM items WHERE name>'carrot' ORDER BY id").unwrap().rows,
    [[Integer(5L)]],
  )
}

///|
test "offset beyond result is empty" {
  let db = conformance_database()
  assert_eq(
    db.execute("SELECT * FROM items LIMIT 2 OFFSET 99").unwrap().rows.length(),
    0,
  )
}

///|
test "limit zero is empty" {
  let db = conformance_database()
  assert_eq(db.execute("SELECT * FROM items LIMIT 0").unwrap().rows.length(), 0)
}

///|
test "delete all rows" {
  let db = conformance_database()
  ignore(db.execute("DELETE FROM items"))
  assert_eq(db.execute("SELECT * FROM items").unwrap().rows.length(), 0)
}

///|
test "update all rows" {
  let db = conformance_database()
  ignore(db.execute("UPDATE items SET category='food'"))
  assert_eq(
    db.execute("SELECT * FROM items WHERE category='food'").unwrap().rows.length(),
    5,
  )
}
