///|
test "plan table scan" {
  let plan = explain("SELECT * FROM users").unwrap()
  let rendered = render_plan(plan)
  assert_true(rendered.contains("Project columns=*"))
  assert_true(rendered.contains("TableScan table=users"))
}

///|
test "plan filter" {
  let rendered = render_plan(explain("SELECT * FROM users WHERE id=1").unwrap())
  assert_true(rendered.contains("Filter expression=id = 1"))
}

///|
test "plan sort" {
  let rendered = render_plan(
    explain("SELECT * FROM users ORDER BY id DESC").unwrap(),
  )
  assert_true(rendered.contains("Sort column=id direction=DESC"))
}

///|
test "plan limit offset" {
  let rendered = render_plan(
    explain("SELECT * FROM users LIMIT 3 OFFSET 2").unwrap(),
  )
  assert_true(rendered.contains("Limit count=3 offset=2"))
}

///|
test "plan create" {
  assert_true(
    render_plan(explain("CREATE TABLE t (id INTEGER, name TEXT)").unwrap()).contains(
      "columns=2",
    ),
  )
}

///|
test "plan insert" {
  assert_true(
    render_plan(explain("INSERT INTO t VALUES (1),(2),(3)").unwrap()).contains(
      "rows=3",
    ),
  )
}

///|
test "plan update" {
  let rendered = render_plan(explain("UPDATE t SET id=2 WHERE id=1").unwrap())
  assert_true(rendered.contains("Update table=t assignments=1"))
  assert_true(rendered.contains("Filter expression=id = 1"))
}

///|
test "plan delete" {
  let rendered = render_plan(explain("DELETE FROM t WHERE id=1").unwrap())
  assert_true(rendered.contains("Delete table=t"))
}

///|
test "plan drop" {
  assert_eq(
    render_plan(explain("DROP TABLE t").unwrap()),
    "DropTable table=t\n",
  )
}

///|
test "scan plan cost" {
  assert_true(
    estimate_plan_cost(explain("SELECT * FROM t").unwrap(), 100) >= 100,
  )
}

///|
test "sort costs more than scan" {
  let scan = estimate_plan_cost(explain("SELECT * FROM t").unwrap(), 100)
  let sort = estimate_plan_cost(
    explain("SELECT * FROM t ORDER BY id").unwrap(),
    100,
  )
  assert_true(sort > scan)
}

///|
test "insert cost tracks rows" {
  assert_eq(
    estimate_plan_cost(explain("INSERT INTO t VALUES (1),(2)").unwrap(), 0),
    2,
  )
}
