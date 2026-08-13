///|
/// Per-table storage information returned by the integrity inspector.
pub struct TableStats {
  name : String
  columns : Int
  rows : Int
  estimated_bytes : Int
} derive(Eq, Debug)

///|
/// Database-wide logical and physical statistics.
pub struct DatabaseStats {
  tables : Int
  rows : Int
  estimated_pages : Int
  table_stats : Array[TableStats]
} derive(Eq, Debug)

///|
/// One physical page descriptor for diagnostic tools.
pub struct PageInfo {
  number : Int
  kind : String
  entries : Int
  next_page : Int
} derive(Eq, Debug)

///|
/// Result of a non-mutating integrity pass.
pub struct IntegrityReport {
  ok : Bool
  checks : Int
  messages : Array[String]
} derive(Eq, Debug)

///|
fn logical_row_size(row : Array[Value]) -> Int {
  let mut size = 10
  for value in row {
    let value_size = match value {
      Null => 1
      Integer(_) => 9
      Real(_) => 9
      Text(text) => 3 + @encoding_utf8.encode(text).length()
    }
    size = size + value_size
  }
  size
}

///|
/// Collect stable statistics without exposing mutable table internals.
pub fn Connection::stats(self : Connection) -> DatabaseStats {
  let names = self.table_names()
  let table_stats : Array[TableStats] = []
  let mut total_rows = 0
  let mut total_bytes = PAGE_SIZE * 2
  for name in names {
    match self.tables.get(name) {
      None => ()
      Some(table) => {
        let rows = table.rows.rows()
        let mut bytes = 0
        for pair in rows {
          bytes = bytes + logical_row_size(pair.1)
        }
        total_rows = total_rows + rows.length()
        total_bytes = total_bytes + bytes
        table_stats.push({
          name,
          columns: table.columns.length(),
          rows: rows.length(),
          estimated_bytes: bytes,
        })
      }
    }
  }
  {
    tables: table_stats.length(),
    rows: total_rows,
    estimated_pages: (total_bytes + PAGE_SIZE - 1) / PAGE_SIZE,
    table_stats,
  }
}

///|
/// Validate catalog names, schemas, row widths, value types, and row keys.
pub fn Connection::integrity_check(self : Connection) -> IntegrityReport {
  let messages : Array[String] = []
  let mut checks = 0
  let names = self.table_names()
  for name in names {
    checks = checks + 1
    if name.length() == 0 {
      messages.push("catalog contains an empty table name")
    }
    match self.tables.get(name) {
      None => messages.push("catalog lookup failed for " + name)
      Some(table) => {
        checks = checks + 1
        if table.columns.length() == 0 {
          messages.push("table " + name + " has no columns")
        }
        let column_names : Map[String, Bool] = Map([])
        for column in table.columns {
          checks = checks + 1
          if column.name.length() == 0 {
            messages.push("table " + name + " has an empty column name")
          }
          if column_names.contains(column.name) {
            messages.push("table " + name + " repeats column " + column.name)
          }
          column_names[column.name] = true
        }
        let rows = table.rows.rows()
        let mut previous = 0L
        for pair in rows {
          let (key, row) = pair
          checks = checks + 1
          if key <= previous {
            messages.push("table " + name + " has unsorted row keys")
          }
          previous = key
          if row.length() != table.columns.length() {
            messages.push("table " + name + " has a row width mismatch")
          } else {
            for i = 0; i < row.length(); i = i + 1 {
              checks = checks + 1
              if coerce(row[i], table.columns[i].data_type) is None {
                messages.push(
                  "table " +
                  name +
                  " has a value type mismatch at column " +
                  table.columns[i].name,
                )
              }
            }
          }
        }
      }
    }
  }
  { ok: messages.length() == 0, checks, messages }
}

///|
/// Inspect the exact binary image that would be written on close.
pub fn Connection::page_directory(
  self : Connection,
) -> Result[Array[PageInfo], String] {
  let bytes = encode_database(self.tables).unwrap()
  let page_count = bytes.length() / PAGE_SIZE
  let pages : Array[PageInfo] = []
  for number = 0; number < page_count; number = number + 1 {
    if number == 0 {
      pages.push({
        number,
        kind: "superblock",
        entries: self.tables.length(),
        next_page: 1,
      })
      continue
    }
    let page = slice_page(bytes, number)
    let kind = page[0].to_int()
    if kind == 1 {
      let reader : ByteReader = { data: page, pos: 1 }
      pages.push({
        number,
        kind: "catalog",
        entries: reader.u16(),
        next_page: 0,
      })
    } else if kind == 2 {
      let reader : ByteReader = { data: page, pos: 1 }
      let entries = reader.u16()
      let next_page = reader.u32()
      pages.push({ number, kind: "leaf", entries, next_page })
    } else if kind == 3 {
      let reader : ByteReader = { data: page, pos: 1 }
      pages.push({
        number,
        kind: "internal",
        entries: reader.u16(),
        next_page: 0,
      })
    } else {
      return Err("unknown physical page kind")
    }
  }
  Ok(pages)
}

///|
/// Human-readable page dump used by debugging tools.
pub fn Connection::dump_pages(self : Connection) -> Result[String, String] {
  let directory = self.page_directory().unwrap()
  let out = StringBuilder::new()
  for page in directory {
    out.write_string("page ")
    out.write_string(page.number.to_string())
    out.write_string(" kind=")
    out.write_string(page.kind)
    out.write_string(" entries=")
    out.write_string(page.entries.to_string())
    if page.next_page != 0 {
      out.write_string(" next=")
      out.write_string(page.next_page.to_string())
    }
    out.write_char('\n')
  }
  Ok(out.to_string())
}

///|
/// Verify that encoding and decoding preserves every logical row.
pub fn Connection::verify_roundtrip(self : Connection) -> IntegrityReport {
  let messages : Array[String] = []
  let mut checks = 1
  match encode_database(self.tables) {
    Err(message) => messages.push("encode failed: " + message)
    Ok(bytes) =>
      match decode_database(bytes) {
        Err(message) => messages.push("decode failed: " + message)
        Ok(restored) => {
          checks = checks + 1
          if restored.length() != self.tables.length() {
            messages.push("table count changed after roundtrip")
          }
          for name in self.table_names() {
            checks = checks + 1
            match (self.tables.get(name), restored.get(name)) {
              (Some(before), Some(after)) => {
                let left = before.rows.rows()
                let right = after.rows.rows()
                if left.length() != right.length() {
                  messages.push("row count changed for " + name)
                } else {
                  for i = 0; i < left.length(); i = i + 1 {
                    checks = checks + 1
                    if left[i].1 != right[i].1 {
                      messages.push(
                        "row changed for " + name + " at " + i.to_string(),
                      )
                    }
                  }
                }
              }
              _ => messages.push("table disappeared after roundtrip: " + name)
            }
          }
        }
      }
  }
  { ok: messages.length() == 0, checks, messages }
}
