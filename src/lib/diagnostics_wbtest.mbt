///|
test "diagnostic expected code" {
  let error : SqlError = { message: "expected identifier", line: 2, column: 4 }
  assert_eq(error.diagnostic().code, "SQL001")
}

///|
test "diagnostic table code" {
  let error : SqlError = { message: "no such table: t", line: 1, column: 1 }
  assert_eq(error.diagnostic().code, "SQL101")
}

///|
test "diagnostic column code" {
  let error : SqlError = { message: "unknown column: x", line: 1, column: 2 }
  assert_eq(error.diagnostic().code, "SQL102")
}

///|
test "diagnostic type code" {
  let error : SqlError = { message: "type mismatch for id", line: 1, column: 3 }
  assert_eq(error.diagnostic().code, "SQL201")
}

///|
test "diagnostic storage code" {
  let error : SqlError = {
    message: "storage error: invalid magic",
    line: 1,
    column: 1,
  }
  assert_eq(error.diagnostic().code, "SQL301")
}

///|
test "diagnostic closed code" {
  let error : SqlError = { message: "connection is closed", line: 1, column: 1 }
  assert_eq(error.diagnostic().code, "SQL401")
}

///|
test "diagnostic unexpected code" {
  let error : SqlError = { message: "unexpected character", line: 1, column: 1 }
  assert_eq(error.diagnostic().code, "SQL001")
}

///|
test "render diagnostic source caret" {
  let error : SqlError = { message: "expected identifier", line: 1, column: 8 }
  let rendered = render_sql_error(error, "SELECT FROM")
  assert_true(rendered.contains("error[SQL001]"))
  assert_true(rendered.contains("SELECT FROM"))
  assert_true(rendered.contains("^"))
}

///|
test "render multiline diagnostic" {
  let error : SqlError = { message: "unexpected character", line: 2, column: 3 }
  let rendered = render_sql_error(error, "SELECT *\n  @")
  assert_true(rendered.contains("2:3"))
  assert_true(rendered.contains("  @"))
}

///|
test "lint unbounded select" {
  let diagnostics = lint_sql("SELECT * FROM t").unwrap()
  assert_true(diagnostics.iter().any(fn(item) { item.code == "SQLL03" }))
}

///|
test "lint bounded select clean" {
  let diagnostics = lint_sql("SELECT * FROM t LIMIT 10").unwrap()
  assert_false(diagnostics.iter().any(fn(item) { item.code == "SQLL03" }))
}

///|
test "lint large offset" {
  let diagnostics = lint_sql("SELECT * FROM t LIMIT 1 OFFSET 10001").unwrap()
  assert_true(diagnostics.iter().any(fn(item) { item.code == "SQLL04" }))
}

///|
test "lint full sort" {
  let diagnostics = lint_sql("SELECT * FROM t ORDER BY id").unwrap()
  assert_true(diagnostics.iter().any(fn(item) { item.code == "SQLL05" }))
}

///|
test "lint update all" {
  let diagnostics = lint_sql("UPDATE t SET id=1").unwrap()
  assert_true(diagnostics.iter().any(fn(item) { item.code == "SQLL06" }))
}

///|
test "lint delete all" {
  let diagnostics = lint_sql("DELETE FROM t").unwrap()
  assert_true(diagnostics.iter().any(fn(item) { item.code == "SQLL07" }))
}

///|
test "lint drop warning" {
  let diagnostics = lint_sql("DROP TABLE t").unwrap()
  assert_true(diagnostics.iter().any(fn(item) { item.code == "SQLL08" }))
}

///|
test "lint filtered delete clean" {
  let diagnostics = lint_sql("DELETE FROM t WHERE id=1").unwrap()
  assert_false(diagnostics.iter().any(fn(item) { item.code == "SQLL07" }))
}
