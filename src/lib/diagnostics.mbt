///|
/// Severity of a structured diagnostic.
pub enum Severity {
  ErrorSeverity
  NoteSeverity
} derive(Eq, Debug)

///|
/// A source range in one SQL input string.
pub struct SourceRange {
  start_line : Int
  start_column : Int
  end_line : Int
  end_column : Int
} derive(Eq, Debug)

///|
/// Structured parser or executor diagnostic suitable for IDE clients.
pub struct Diagnostic {
  code : String
  severity : Severity
  message : String
  range : SourceRange
  hint : String?
} derive(Eq, Debug)

///|
/// Convert a public SQL error into a stable diagnostic record.
pub fn SqlError::diagnostic(self : SqlError) -> Diagnostic {
  {
    code: classify_error(self.message),
    severity: ErrorSeverity,
    message: self.message,
    range: {
      start_line: self.line,
      start_column: self.column,
      end_line: self.line,
      end_column: self.column + 1,
    },
    hint: diagnostic_hint(self.message),
  }
}

///|
fn classify_error(message : String) -> String {
  if message.contains("expected") {
    "SQL001"
  } else if message.contains("no such table") {
    "SQL101"
  } else if message.contains("unknown column") {
    "SQL102"
  } else if message.contains("type mismatch") {
    "SQL201"
  } else if message.contains("storage") {
    "SQL301"
  } else if message.contains("closed") {
    "SQL401"
  } else {
    "SQL000"
  }
}

///|
fn diagnostic_hint(message : String) -> String? {
  if message.contains("expected identifier") {
    Some("Use an unquoted name beginning with a letter or underscore.")
  } else if message.contains("expected INTEGER, TEXT, or REAL") {
    Some("The MVP supports exactly INTEGER, TEXT, and REAL column types.")
  } else if message.contains("no such table") {
    Some("Use .tables to list tables in the current database.")
  } else if message.contains("unknown column") {
    Some("Use .schema TABLE to inspect available columns.")
  } else if message.contains("type mismatch") {
    Some("Only INTEGER to REAL implicit conversion is supported.")
  } else if message.contains("closed") {
    Some("Open a new connection before executing more SQL.")
  } else {
    None
  }
}

///|
/// Render an error with a source line and caret.
pub fn render_sql_error(error : SqlError, source : String) -> String {
  let diagnostic = error.diagnostic()
  let lines = source.split("\n").to_array()
  let out = StringBuilder::new()
  out.write_string(
    severity_name(diagnostic.severity) +
    "[" +
    diagnostic.code +
    "] " +
    diagnostic.message +
    "\n",
  )
  out.write_string(
    " --> " +
    diagnostic.range.start_line.to_string() +
    ":" +
    diagnostic.range.start_column.to_string() +
    "\n",
  )
  let index = diagnostic.range.start_line - 1
  if index >= 0 && index < lines.length() {
    let text = lines[index].to_owned()
    out.write_string("  |\n")
    out.write_string(diagnostic.range.start_line.to_string())
    out.write_string(" | ")
    out.write_string(text)
    out.write_char('\n')
    out.write_string("  | ")
    for _i = 1; _i < diagnostic.range.start_column; _i = _i + 1 {
      out.write_char(' ')
    }
    out.write_string("^\n")
  }
  match diagnostic.hint {
    None => ()
    Some(hint) => out.write_string(" hint: " + hint + "\n")
  }
  out.to_string()
}

///|
fn severity_name(severity : Severity) -> String {
  match severity {
    ErrorSeverity => "error"
    NoteSeverity => "note"
  }
}

///|
/// Lint a parsed statement without changing execution semantics.
pub fn lint_statement(statement : Statement) -> Array[Diagnostic] {
  let diagnostics : Array[Diagnostic] = []
  match statement {
    CreateTable(_, columns) =>
      if columns.length() > 64 {
        diagnostics.push(
          note("SQLL01", "wide tables may require catalog overflow pages"),
        )
      }
    Insert(_, rows) =>
      if rows.length() > 1000 {
        diagnostics.push(
          note("SQLL02", "consider batching very large INSERT statements"),
        )
      }
    Select(_, _, filter, order, limit, offset) => {
      if filter is None && limit is None {
        diagnostics.push(
          note("SQLL03", "unbounded SELECT scans the whole table"),
        )
      }
      if offset > 10000 {
        diagnostics.push(
          note("SQLL04", "large OFFSET values still scan preceding rows"),
        )
      }
      if order is Some(_) && limit is None {
        diagnostics.push(
          note("SQLL05", "ORDER BY without LIMIT sorts the full result"),
        )
      }
    }
    Update(_, _, filter) =>
      if filter is None {
        diagnostics.push(
          note("SQLL06", "UPDATE without WHERE changes every row"),
        )
      }
    Delete(_, filter) =>
      if filter is None {
        diagnostics.push(
          note("SQLL07", "DELETE without WHERE removes every row"),
        )
      }
    DropTable(_) =>
      diagnostics.push(
        note("SQLL08", "DROP TABLE is irreversible without a backup"),
      )
  }
  diagnostics
}

///|
fn note(code : String, message : String) -> Diagnostic {
  {
    code,
    severity: NoteSeverity,
    message,
    range: { start_line: 1, start_column: 1, end_line: 1, end_column: 1 },
    hint: None,
  }
}

///|
/// Parse then lint a SQL statement.
pub fn lint_sql(sql : String) -> Result[Array[Diagnostic], SqlError] {
  parse(sql).map(lint_statement)
}
