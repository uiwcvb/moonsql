///|
/// Deterministic SQL formatter for AST diagnostics and tooling.
pub fn format_statement(statement : Statement) -> String {
  match statement {
    CreateTable(name, columns) => {
      let out = StringBuilder::new()
      out.write_string("CREATE TABLE ")
      out.write_string(name)
      out.write_string(" (")
      for i = 0; i < columns.length(); i = i + 1 {
        if i > 0 {
          out.write_string(", ")
        }
        out.write_string(columns[i].name)
        out.write_char(' ')
        out.write_string(format_data_type(columns[i].data_type))
      }
      out.write_char(')')
      out.to_string()
    }
    Insert(name, rows) => {
      let out = StringBuilder::new()
      out.write_string("INSERT INTO ")
      out.write_string(name)
      out.write_string(" VALUES ")
      for i = 0; i < rows.length(); i = i + 1 {
        if i > 0 {
          out.write_string(", ")
        }
        out.write_char('(')
        for j = 0; j < rows[i].length(); j = j + 1 {
          if j > 0 {
            out.write_string(", ")
          }
          out.write_string(format_value(rows[i][j]))
        }
        out.write_char(')')
      }
      out.to_string()
    }
    Select(projection, name, filter, order, limit, offset) => {
      let out = StringBuilder::new()
      out.write_string("SELECT ")
      out.write_string(format_projection(projection))
      out.write_string(" FROM ")
      out.write_string(name)
      match filter {
        None => ()
        Some(expression) => {
          out.write_string(" WHERE ")
          out.write_string(format_expression(expression))
        }
      }
      match order {
        None => ()
        Some(spec) => {
          out.write_string(" ORDER BY ")
          out.write_string(spec.column)
          out.write_string(if spec.descending { " DESC" } else { " ASC" })
        }
      }
      match limit {
        None => ()
        Some(value) => {
          out.write_string(" LIMIT ")
          out.write_string(value.to_string())
        }
      }
      if offset != 0 {
        out.write_string(" OFFSET ")
        out.write_string(offset.to_string())
      }
      out.to_string()
    }
    Update(name, assignments, filter) => {
      let out = StringBuilder::new()
      out.write_string("UPDATE ")
      out.write_string(name)
      out.write_string(" SET ")
      for i = 0; i < assignments.length(); i = i + 1 {
        if i > 0 {
          out.write_string(", ")
        }
        out.write_string(assignments[i].0)
        out.write_string(" = ")
        out.write_string(format_value(assignments[i].1))
      }
      match filter {
        None => ()
        Some(expression) => {
          out.write_string(" WHERE ")
          out.write_string(format_expression(expression))
        }
      }
      out.to_string()
    }
    Delete(name, filter) => {
      let out = StringBuilder::new()
      out.write_string("DELETE FROM ")
      out.write_string(name)
      match filter {
        None => ()
        Some(expression) => {
          out.write_string(" WHERE ")
          out.write_string(format_expression(expression))
        }
      }
      out.to_string()
    }
    DropTable(name) => "DROP TABLE " + name
  }
}

///|
pub fn format_sql(sql : String) -> Result[String, SqlError] {
  parse(sql).map(format_statement)
}

///|
fn format_data_type(data_type : DataType) -> String {
  match data_type {
    IntegerType => "INTEGER"
    TextType => "TEXT"
    RealType => "REAL"
  }
}

///|
fn format_projection(projection : Projection) -> String {
  match projection {
    AllColumns => "*"
    NamedColumns(columns) => columns.join(", ")
  }
}

///|
fn format_value(value : Value) -> String {
  match value {
    Null => "NULL"
    Integer(value) => value.to_string()
    Real(value) => value.to_string()
    Text(value) => "'" + value.replace_all(old="'", new="''") + "'"
  }
}

///|
fn binary_symbol(operator : BinaryOp) -> String {
  match operator {
    Eq => "="
    Ne => "<>"
    Lt => "<"
    Gt => ">"
    Le => "<="
    Ge => ">="
    And => "AND"
    Or => "OR"
  }
}

///|
fn precedence(expression : Expr) -> Int {
  match expression {
    Binary(_, Or, _) => 1
    Binary(_, And, _) => 2
    Binary(_, _, _) => 3
    NotExpr(_) => 4
    _ => 5
  }
}

///|
fn format_child(expression : Expr, parent_precedence : Int) -> String {
  let text = format_expression(expression)
  if precedence(expression) < parent_precedence {
    "(" + text + ")"
  } else {
    text
  }
}

///|
/// Format expressions while preserving boolean precedence.
pub fn format_expression(expression : Expr) -> String {
  match expression {
    Literal(value) => format_value(value)
    ColumnRef(name) => name
    NotExpr(inner) => "NOT " + format_child(inner, 4)
    Binary(left, operator, right) => {
      let level = precedence(expression)
      format_child(left, level) +
      " " +
      binary_symbol(operator) +
      " " +
      format_child(right, level)
    }
  }
}

///|
/// Multiline AST outline useful in error reports and REPL `.ast`.
pub fn outline_statement(statement : Statement) -> String {
  let out = StringBuilder::new()
  match statement {
    CreateTable(name, columns) => {
      out.write_string("CreateTable\n")
      out.write_string("  name: " + name + "\n")
      out.write_string("  columns:\n")
      for column in columns {
        out.write_string(
          "    - " +
          column.name +
          ": " +
          format_data_type(column.data_type) +
          "\n",
        )
      }
    }
    Insert(name, rows) => {
      out.write_string("Insert\n")
      out.write_string("  table: " + name + "\n")
      out.write_string("  rows: " + rows.length().to_string() + "\n")
    }
    Select(projection, name, filter, order, limit, offset) => {
      out.write_string("Select\n")
      out.write_string("  projection: " + format_projection(projection) + "\n")
      out.write_string("  table: " + name + "\n")
      match filter {
        None => ()
        Some(value) =>
          out.write_string("  filter: " + format_expression(value) + "\n")
      }
      match order {
        None => ()
        Some(value) =>
          out.write_string(
            "  order: " +
            value.column +
            (if value.descending { " DESC\n" } else { " ASC\n" }),
          )
      }
      match limit {
        None => ()
        Some(value) => out.write_string("  limit: " + value.to_string() + "\n")
      }
      out.write_string("  offset: " + offset.to_string() + "\n")
    }
    Update(name, assignments, filter) => {
      out.write_string("Update\n")
      out.write_string("  table: " + name + "\n")
      out.write_string(
        "  assignments: " + assignments.length().to_string() + "\n",
      )
      match filter {
        None => ()
        Some(value) =>
          out.write_string("  filter: " + format_expression(value) + "\n")
      }
    }
    Delete(name, filter) => {
      out.write_string("Delete\n")
      out.write_string("  table: " + name + "\n")
      match filter {
        None => ()
        Some(value) =>
          out.write_string("  filter: " + format_expression(value) + "\n")
      }
    }
    DropTable(name) => {
      out.write_string("DropTable\n")
      out.write_string("  name: " + name + "\n")
    }
  }
  out.to_string()
}
