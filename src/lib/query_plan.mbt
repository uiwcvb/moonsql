///|
/// Logical operators used by the explain API.
pub enum PlanNode {
  TableScan(String)
  FilterNode(Expr, PlanNode)
  SortNode(OrderSpec, PlanNode)
  LimitNode(Int?, Int, PlanNode)
  ProjectNode(Projection, PlanNode)
  InsertNode(String, Int)
  CreateNode(String, Int)
  UpdateNode(String, Int, Expr?)
  DeleteNode(String, Expr?)
  DropNode(String)
} derive(Eq, Debug)

///|
/// Build a deterministic logical plan from a parsed statement.
pub fn plan_statement(statement : Statement) -> PlanNode {
  match statement {
    CreateTable(name, columns) => CreateNode(name, columns.length())
    Insert(name, rows) => InsertNode(name, rows.length())
    Select(projection, table, filter, order, limit, offset) => {
      let mut node = TableScan(table)
      match filter {
        None => ()
        Some(expression) => node = FilterNode(expression, node)
      }
      match order {
        None => ()
        Some(specification) => node = SortNode(specification, node)
      }
      if limit is Some(_) || offset != 0 {
        node = LimitNode(limit, offset, node)
      }
      ProjectNode(projection, node)
    }
    Update(name, assignments, filter) =>
      UpdateNode(name, assignments.length(), filter)
    Delete(name, filter) => DeleteNode(name, filter)
    DropTable(name) => DropNode(name)
  }
}

///|
/// Parse SQL and return a logical execution plan.
pub fn explain(sql : String) -> Result[PlanNode, SqlError] {
  parse(sql).map(plan_statement)
}

///|
/// Render a tree-shaped plan for command-line diagnostics.
pub fn render_plan(plan : PlanNode) -> String {
  let out = StringBuilder::new()
  render_plan_at(plan, out, 0)
  out.to_string()
}

///|
fn indent(out : StringBuilder, depth : Int) -> Unit {
  for _i = 0; _i < depth; _i = _i + 1 {
    out.write_string("  ")
  }
}

///|
fn render_plan_at(plan : PlanNode, out : StringBuilder, depth : Int) -> Unit {
  indent(out, depth)
  match plan {
    TableScan(table) => out.write_string("TableScan table=" + table + "\n")
    FilterNode(expression, child) => {
      out.write_string(
        "Filter expression=" + format_expression(expression) + "\n",
      )
      render_plan_at(child, out, depth + 1)
    }
    SortNode(order, child) => {
      out.write_string(
        "Sort column=" +
        order.column +
        (if order.descending {
          " direction=DESC\n"
        } else {
          " direction=ASC\n"
        }),
      )
      render_plan_at(child, out, depth + 1)
    }
    LimitNode(limit, offset, child) => {
      out.write_string("Limit")
      match limit {
        None => ()
        Some(value) => out.write_string(" count=" + value.to_string())
      }
      out.write_string(" offset=" + offset.to_string() + "\n")
      render_plan_at(child, out, depth + 1)
    }
    ProjectNode(projection, child) => {
      let columns_text = match projection {
        AllColumns => "*\n"
        NamedColumns(columns) => columns.join(",") + "\n"
      }
      out.write_string("Project columns=" + columns_text)
      render_plan_at(child, out, depth + 1)
    }
    InsertNode(table, rows) =>
      out.write_string(
        "Insert table=" + table + " rows=" + rows.to_string() + "\n",
      )
    CreateNode(table, columns) =>
      out.write_string(
        "CreateTable table=" + table + " columns=" + columns.to_string() + "\n",
      )
    UpdateNode(table, assignments, filter) => {
      out.write_string(
        "Update table=" +
        table +
        " assignments=" +
        assignments.to_string() +
        "\n",
      )
      match filter {
        None => ()
        Some(value) => {
          indent(out, depth + 1)
          out.write_string(
            "Filter expression=" + format_expression(value) + "\n",
          )
        }
      }
    }
    DeleteNode(table, filter) => {
      out.write_string("Delete table=" + table + "\n")
      match filter {
        None => ()
        Some(value) => {
          indent(out, depth + 1)
          out.write_string(
            "Filter expression=" + format_expression(value) + "\n",
          )
        }
      }
    }
    DropNode(table) => out.write_string("DropTable table=" + table + "\n")
  }
}

///|
/// Estimate relative work for comparing plans. This is not a time estimate.
pub fn estimate_plan_cost(plan : PlanNode, rows : Int) -> Int {
  match plan {
    TableScan(_) => rows
    FilterNode(_, child) => estimate_plan_cost(child, rows) + rows
    SortNode(_, child) =>
      estimate_plan_cost(child, rows) + rows * logarithmic_factor(rows)
    LimitNode(limit, offset, child) => {
      let requested = match limit {
        None => rows
        Some(value) => value
      }
      estimate_plan_cost(child, rows) + requested + offset
    }
    ProjectNode(_, child) => estimate_plan_cost(child, rows) + rows
    InsertNode(_, count) => count
    CreateNode(_, columns) => columns
    UpdateNode(_, assignments, _) => rows * assignments
    DeleteNode(_, _) => rows
    DropNode(_) => 1
  }
}

///|
fn logarithmic_factor(value : Int) -> Int {
  let mut factor = 1
  let mut remaining = value
  while remaining > 1 {
    remaining = remaining / 2
    factor = factor + 1
  }
  factor
}
