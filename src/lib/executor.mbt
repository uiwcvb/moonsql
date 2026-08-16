///|
/// Version of the moonsql engine, kept in sync with moon.mod's `version`.
pub fn version() -> String {
  "0.1.0"
}

///|
/// Resolve the database path from CLI args. `Err("version")`/`Err("help")`
/// request the banner, other errors are usage mistakes.
pub fn resolve_args(args : Array[String]) -> Result[String, String] {
  let mut path = "moonsql.mdb"
  let mut i = 1
  while i < args.length() {
    match args[i] {
      "--version" | "-v" => return Err("version")
      "--help" | "-h" => return Err("help")
      "--file" =>
          if i + 1 < args.length() {
            path = args[i + 1]
            i = i + 1
          } else {
            return Err("missing path after --file")
          }
        ;
      other => return Err("unknown argument: " + other)
    }
    i = i + 1
  }
  return Ok(path)
}

///|
struct Table {
  columns : Array[Column]
  rows : BTree
}

///|
pub struct Connection {
  path : String
  mut tables : Map[String, Table]
  mut closed : Bool
  mut dirty : Bool
  mut storage_error : String?
}

///|
pub fn open(path : String) -> Connection {
  let db : Connection = {
    path,
    tables: Map([]),
    closed: false,
    dirty: false,
    storage_error: None,
  }
  if path != ":memory:" && @fs.path_exists(path) {
    let bytes = @fs.read_file_to_bytes(path) catch {
      _ => {
        db.storage_error = Some("unable to read database file")
        Bytes::new(0)
      }
    }
    if bytes.length() > 0 {
      match decode_database(bytes) {
        Ok(tables) => db.tables = tables
        Err(message) => db.storage_error = Some(message)
      }
    }
  }
  db
}

///|
pub fn Connection::close(self : Connection) -> Unit {
  if self.closed {
    return
  }
  if self.path != ":memory:" && self.dirty {
    match encode_database(self.tables) {
      Err(message) => self.storage_error = Some(message)
      Ok(bytes) =>
        @fs.write_bytes_to_file(self.path, bytes) catch {
          _ => self.storage_error = Some("unable to write database file")
        }
    }
  }
  self.closed = true
}

///|
fn table_index(table : Table, name : String) -> Int? {
  for i = 0; i < table.columns.length(); i = i + 1 {
    if table.columns[i].name == name {
      return Some(i)
    }
  }
  None
}

///|
fn eval(
  expr : Expr,
  table : Table,
  row : Array[Value],
) -> Result[Value, SqlError] {
  match expr {
    Literal(v) => Ok(v)
    ColumnRef(name) =>
      match table_index(table, name) {
        Some(i) => Ok(row[i])
        None => Err({ message: "unknown column: " + name, line: 1, column: 1 })
      }
    NotExpr(inner) =>
      Ok(
        Integer(if truthy(eval(inner, table, row).unwrap()) { 0L } else { 1L }),
      )
    Binary(left, And, right) =>
      Ok(
        Integer(
          if truthy(eval(left, table, row).unwrap()) &&
            truthy(eval(right, table, row).unwrap()) {
            1L
          } else {
            0L
          },
        ),
      )
    Binary(left, Or, right) =>
      Ok(
        Integer(
          if truthy(eval(left, table, row).unwrap()) ||
            truthy(eval(right, table, row).unwrap()) {
            1L
          } else {
            0L
          },
        ),
      )
    Binary(left, op, right) => {
      let c = value_compare(
        eval(left, table, row).unwrap(),
        eval(right, table, row).unwrap(),
      )
      let yes = match op {
        Eq => c == 0
        Ne => c != 0
        Lt => c < 0
        Gt => c > 0
        Le => c <= 0
        Ge => c >= 0
        _ => false
      }
      Ok(Integer(if yes { 1L } else { 0L }))
    }
  }
}

///|
fn truthy(v : Value) -> Bool {
  match v {
    Integer(x) => x != 0L
    Real(x) => x != 0.0
    Text(x) => x.length() > 0
    Null => false
  }
}

///|
fn matches(
  filter : Expr?,
  table : Table,
  row : Array[Value],
) -> Result[Bool, SqlError] {
  match filter {
    None => Ok(true)
    Some(e) => Ok(truthy(eval(e, table, row).unwrap()))
  }
}

///|
fn empty_result() -> QueryResult {
  { columns: [], rows: [] }
}

///|
fn Connection::get_table(
  self : Connection,
  name : String,
) -> Result[Table, SqlError] {
  match self.tables.get(name) {
    Some(t) => Ok(t)
    None => Err({ message: "no such table: " + name, line: 1, column: 1 })
  }
}

///|
pub fn Connection::execute(
  self : Connection,
  sql : String,
) -> Result[QueryResult, SqlError] {
  if self.closed {
    return Err({ message: "connection is closed", line: 1, column: 1 })
  }
  match self.storage_error {
    Some(message) =>
      return Err({ message: "storage error: " + message, line: 1, column: 1 })
    None => ()
  }
  let statement = parse(sql).unwrap()
  let target = match statement {
    Insert(name, _)
    | Select(_, name, _, _, _, _)
    | Update(name, _, _)
    | Delete(name, _) => Some(name)
    _ => None
  }
  match target {
    Some(name) if !self.tables.contains(name) =>
      return Err({ message: "no such table: " + name, line: 1, column: 1 })
    _ => ()
  }
  let result = match statement {
    CreateTable(name, columns) => {
      if self.tables.contains(name) {
        return Err({
          message: "table already exists: " + name,
          line: 1,
          column: 1,
        })
      }
      self.tables[name] = { columns, rows: BTree::new() }
      Ok(empty_result())
    }
    Insert(name, new_rows) => {
      let table = self.get_table(name).unwrap()
      for raw in new_rows {
        if raw.length() != table.columns.length() {
          return Err({ message: "column count mismatch", line: 1, column: 1 })
        }
        let row : Array[Value] = []
        for i = 0; i < raw.length(); i = i + 1 {
          match coerce(raw[i], table.columns[i].data_type) {
            Some(v) => row.push(v)
            None =>
              return Err({
                message: "type mismatch for " + table.columns[i].name,
                line: 1,
                column: 1,
              })
          }
        }
        ignore(table.rows.append(row))
      }
      Ok(empty_result())
    }
    Select(projection, name, filter, order, limit, offset) => {
      let table = self.get_table(name).unwrap()
      let indices : Array[Int] = []
      let columns : Array[String] = []
      match projection {
        AllColumns =>
          for i = 0; i < table.columns.length(); i = i + 1 {
            indices.push(i)
            columns.push(table.columns[i].name)
          }
        NamedColumns(names) =>
          for n in names {
            match table_index(table, n) {
              Some(i) => {
                indices.push(i)
                columns.push(n)
              }
              None =>
                return Err({
                  message: "unknown column: " + n,
                  line: 1,
                  column: 1,
                })
            }
          }
      }
      let selected : Array[Array[Value]] = []
      for pair in table.rows.rows() {
        let (_, row) = pair
        if matches(filter, table, row).unwrap() {
          selected.push(row)
        }
      }
      match order {
        Some(spec) =>
          match table_index(table, spec.column) {
            Some(index) =>
              selected.sort_by(fn(a, b) {
                let c = value_compare(a[index], b[index])
                if spec.descending {
                  -c
                } else {
                  c
                }
              })
            None =>
              return Err({
                message: "unknown ORDER BY column",
                line: 1,
                column: 1,
              })
          }
        None => ()
      }
      let result_rows : Array[Array[Value]] = []
      let stop = match limit {
        Some(n) => offset + n
        None => selected.length()
      }
      for i = offset; i < selected.length() && i < stop; i = i + 1 {
        let out : Array[Value] = []
        for index in indices {
          out.push(selected[i][index])
        }
        result_rows.push(out)
      }
      Ok({ columns, rows: result_rows })
    }
    Update(name, assignments, filter) => {
      let table = self.get_table(name).unwrap()
      let kept = table.rows.rows()
      for pair in kept {
        let (_, row) = pair
        if matches(filter, table, row).unwrap() {
          for assignment in assignments {
            let (column, raw) = assignment
            match table_index(table, column) {
              Some(i) =>
                match coerce(raw, table.columns[i].data_type) {
                  Some(v) => row[i] = v
                  None =>
                    return Err({
                      message: "type mismatch for " + column,
                      line: 1,
                      column: 1,
                    })
                }
              None =>
                return Err({
                  message: "unknown column: " + column,
                  line: 1,
                  column: 1,
                })
            }
          }
        }
      }
      table.rows.replace(kept)
      Ok(empty_result())
    }
    Delete(name, filter) => {
      let table = self.get_table(name).unwrap()
      let kept : Array[(Int64, Array[Value])] = []
      for pair in table.rows.rows() {
        let (_, row) = pair
        if !matches(filter, table, row).unwrap() {
          kept.push(pair)
        }
      }
      table.rows.replace(kept)
      Ok(empty_result())
    }
    DropTable(name) => {
      if !self.tables.contains(name) {
        return Err({ message: "no such table: " + name, line: 1, column: 1 })
      }
      self.tables.remove(name)
      Ok(empty_result())
    }
  }
  if result is Ok(_) {
    match statement {
      Select(_, _, _, _, _, _) => ()
      _ => self.dirty = true
    }
  }
  result
}

///|
pub fn Connection::table_names(self : Connection) -> Array[String] {
  let names = self.tables.keys().to_array()
  names.sort()
  names
}

///|
fn type_name(t : DataType) -> String {
  match t {
    IntegerType => "INTEGER"
    TextType => "TEXT"
    RealType => "REAL"
  }
}

///|
pub fn Connection::schema(self : Connection, name : String) -> String? {
  match self.tables.get(name) {
    None => None
    Some(table) => {
      let b = StringBuilder::new()
      b.write_string("CREATE TABLE " + name + " (")
      for i = 0; i < table.columns.length(); i = i + 1 {
        if i > 0 {
          b.write_string(", ")
        }
        b.write_string(
          table.columns[i].name + " " + type_name(table.columns[i].data_type),
        )
      }
      b.write_string(");")
      Some(b.to_string())
    }
  }
}

///|
pub fn Connection::run_line(
  self : Connection,
  line : String,
) -> Result[String, SqlError] {
  let input = line.trim().to_owned()
  if input == ".help" {
    return Ok(
      ".tables\n.schema TABLE\n.ast SQL\n.version\n.quit\n.exit",
    )
  }
  if input == ".version" {
    return Ok("moonsql " + version())
  }
  if input == ".tables" {
    return Ok(self.table_names().join("\n"))
  }
  if input == ".quit" || input == ".exit" {
    self.close()
    return Ok("bye")
  }
  if input.length() >= 7 && input[:7] == ".schema" {
    let name = input[7:].to_owned().trim().to_owned()
    return match self.schema(name) {
      Some(sql) => Ok(sql)
      None => Err({ message: "no such table: " + name, line: 1, column: 1 })
    }
  }
  if input.length() >= 4 && input[:4] == ".ast" {
    return debug_ast(input[4:].to_owned().trim().to_owned())
  }
  let result = self.execute(input).unwrap()
  if result.columns.length() == 0 {
    return Ok("OK")
  }
  let b = StringBuilder::new()
  b.write_string(result.columns.join(" | "))
  b.write_char('\n')
  for row in result.rows {
    b.write_string(row.map(fn(v) { v.to_sql() }).join(" | "))
    b.write_char('\n')
  }
  Ok(b.to_string().trim_end(chars="\n").to_owned())
}
