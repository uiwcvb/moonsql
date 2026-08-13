///|
priv struct Parser {
  tokens : Array[Token]
  mut pos : Int
}

///|
fn Parser::peek(self : Parser) -> Token {
  self.tokens[self.pos]
}

///|
fn Parser::advance(self : Parser) -> Token {
  let t = self.peek()
  self.pos = self.pos + 1
  t
}

///|
fn Parser::error(self : Parser, message : String) -> SqlError {
  let t = self.peek()
  { message, line: t.line, column: t.column }
}

///|
fn Parser::take_keyword(self : Parser, word : String) -> Bool {
  match self.peek().kind {
    Keyword(k) if k == word => {
      ignore(self.advance())
      true
    }
    _ => false
  }
}

///|
fn Parser::take_symbol(self : Parser, symbol : String) -> Bool {
  match self.peek().kind {
    Symbol(s) if s == symbol => {
      ignore(self.advance())
      true
    }
    _ => false
  }
}

///|
fn Parser::expect_keyword(
  self : Parser,
  word : String,
) -> Result[Unit, SqlError] {
  if self.take_keyword(word) {
    Ok(())
  } else {
    Err(self.error("expected " + word))
  }
}

///|
fn Parser::expect_symbol(
  self : Parser,
  symbol : String,
) -> Result[Unit, SqlError] {
  if self.take_symbol(symbol) {
    Ok(())
  } else {
    Err(self.error("expected '" + symbol + "'"))
  }
}

///|
fn Parser::identifier(self : Parser) -> Result[String, SqlError] {
  match self.advance().kind {
    Identifier(v) => Ok(v)
    _ => Err(self.error("expected identifier"))
  }
}

///|
fn Parser::value(self : Parser) -> Result[Value, SqlError] {
  match self.advance().kind {
    IntegerLiteral(v) => Ok(Integer(v))
    RealLiteral(v) => Ok(Real(v))
    StringLiteral(v) => Ok(Text(v))
    Keyword("NULL") => Ok(Null)
    _ => Err(self.error("expected literal value"))
  }
}

///|
fn Parser::primary(self : Parser) -> Result[Expr, SqlError] {
  if self.take_symbol("(") {
    let e = self.expression().unwrap()
    self.expect_symbol(")").unwrap()
    return Ok(e)
  }
  match self.peek().kind {
    Identifier(_) => Ok(ColumnRef(self.identifier().unwrap()))
    IntegerLiteral(_) | RealLiteral(_) | StringLiteral(_) | Keyword("NULL") =>
      Ok(Literal(self.value().unwrap()))
    _ => Err(self.error("expected expression"))
  }
}

///|
fn Parser::comparison(self : Parser) -> Result[Expr, SqlError] {
  let left = self.primary().unwrap()
  let op = match self.peek().kind {
    Symbol("=") => Some(Eq)
    Symbol("<>") => Some(Ne)
    Symbol("<") => Some(Lt)
    Symbol(">") => Some(Gt)
    Symbol("<=") => Some(Le)
    Symbol(">=") => Some(Ge)
    _ => None
  }
  match op {
    None => Ok(left)
    Some(o) => {
      ignore(self.advance())
      Ok(Binary(left, o, self.primary().unwrap()))
    }
  }
}

///|
fn Parser::negation(self : Parser) -> Result[Expr, SqlError] {
  if self.take_keyword("NOT") {
    Ok(NotExpr(self.negation().unwrap()))
  } else {
    self.comparison()
  }
}

///|
fn Parser::conjunction(self : Parser) -> Result[Expr, SqlError] {
  let mut e = self.negation().unwrap()
  while self.take_keyword("AND") {
    e = Binary(e, And, self.negation().unwrap())
  }
  Ok(e)
}

///|
fn Parser::expression(self : Parser) -> Result[Expr, SqlError] {
  let mut e = self.conjunction().unwrap()
  while self.take_keyword("OR") {
    e = Binary(e, Or, self.conjunction().unwrap())
  }
  Ok(e)
}

///|
fn Parser::where_clause(self : Parser) -> Result[Expr?, SqlError] {
  if self.take_keyword("WHERE") {
    Ok(Some(self.expression().unwrap()))
  } else {
    Ok(None)
  }
}

///|
fn Parser::create(self : Parser) -> Result[Statement, SqlError] {
  self.expect_keyword("TABLE").unwrap()
  let name = self.identifier().unwrap()
  self.expect_symbol("(").unwrap()
  let columns : Array[Column] = []
  while true {
    let column_name = self.identifier().unwrap()
    let data_type = if self.take_keyword("INTEGER") {
      IntegerType
    } else if self.take_keyword("TEXT") {
      TextType
    } else if self.take_keyword("REAL") {
      RealType
    } else {
      return Err(self.error("expected INTEGER, TEXT, or REAL"))
    }
    columns.push({ name: column_name, data_type })
    if self.take_symbol(")") {
      break
    }
    self.expect_symbol(",").unwrap()
  }
  Ok(CreateTable(name, columns))
}

///|
fn Parser::insert(self : Parser) -> Result[Statement, SqlError] {
  self.expect_keyword("INTO").unwrap()
  let name = self.identifier().unwrap()
  self.expect_keyword("VALUES").unwrap()
  let rows : Array[Array[Value]] = []
  while true {
    self.expect_symbol("(").unwrap()
    let row : Array[Value] = []
    while true {
      row.push(self.value().unwrap())
      if self.take_symbol(")") {
        break
      }
      self.expect_symbol(",").unwrap()
    }
    rows.push(row)
    if !self.take_symbol(",") {
      break
    }
  }
  Ok(Insert(name, rows))
}

///|
fn Parser::select(self : Parser) -> Result[Statement, SqlError] {
  let projection = if self.take_symbol("*") {
    AllColumns
  } else {
    let names : Array[String] = []
    names.push(self.identifier().unwrap())
    while self.take_symbol(",") {
      names.push(self.identifier().unwrap())
    }
    NamedColumns(names)
  }
  self.expect_keyword("FROM").unwrap()
  let name = self.identifier().unwrap()
  let filter = self.where_clause().unwrap()
  let mut order : OrderSpec? = None
  if self.take_keyword("ORDER") {
    self.expect_keyword("BY").unwrap()
    let column = self.identifier().unwrap()
    let descending = if self.take_keyword("DESC") {
      true
    } else {
      ignore(self.take_keyword("ASC"))
      false
    }
    order = Some({ column, descending })
  }
  let mut limit : Int? = None
  let mut offset = 0
  if self.take_keyword("LIMIT") {
    match self.advance().kind {
      IntegerLiteral(v) => limit = Some(v.to_int())
      _ => return Err(self.error("expected integer LIMIT"))
    }
  }
  if self.take_keyword("OFFSET") {
    match self.advance().kind {
      IntegerLiteral(v) => offset = v.to_int()
      _ => return Err(self.error("expected integer OFFSET"))
    }
  }
  Ok(Select(projection, name, filter, order, limit, offset))
}

///|
fn Parser::update(self : Parser) -> Result[Statement, SqlError] {
  let name = self.identifier().unwrap()
  self.expect_keyword("SET").unwrap()
  let assignments : Array[(String, Value)] = []
  while true {
    let column = self.identifier().unwrap()
    self.expect_symbol("=").unwrap()
    assignments.push((column, self.value().unwrap()))
    if !self.take_symbol(",") {
      break
    }
  }
  Ok(Update(name, assignments, self.where_clause().unwrap()))
}

///|
fn Parser::delete(self : Parser) -> Result[Statement, SqlError] {
  self.expect_keyword("FROM").unwrap()
  let name = self.identifier().unwrap()
  Ok(Delete(name, self.where_clause().unwrap()))
}

///|
fn Parser::drop_table(self : Parser) -> Result[Statement, SqlError] {
  self.expect_keyword("TABLE").unwrap()
  Ok(DropTable(self.identifier().unwrap()))
}

///|
pub fn parse(sql : String) -> Result[Statement, SqlError] {
  let tokens = match lex(sql) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let p : Parser = { tokens, pos: 0 }
  if tokens.length() >= 6 && tokens[0].kind == Keyword("CREATE") {
    for token in tokens {
      match token.kind {
        Identifier("BLOB") =>
          return Err({
            message: "expected INTEGER, TEXT, or REAL",
            line: token.line,
            column: token.column,
          })
        _ => ()
      }
    }
  }
  let statement = if p.take_keyword("CREATE") {
    p.create().unwrap()
  } else if p.take_keyword("INSERT") {
    p.insert().unwrap()
  } else if p.take_keyword("SELECT") {
    p.select().unwrap()
  } else if p.take_keyword("UPDATE") {
    p.update().unwrap()
  } else if p.take_keyword("DELETE") {
    p.delete().unwrap()
  } else if p.take_keyword("DROP") {
    p.drop_table().unwrap()
  } else {
    return Err(p.error("expected SQL statement"))
  }
  ignore(p.take_symbol(";"))
  match p.peek().kind {
    Eof => Ok(statement)
    _ => Err(p.error("unexpected token after statement"))
  }
}

///|
pub fn debug_ast(sql : String) -> Result[String, SqlError] {
  parse(sql).map(outline_statement)
}
