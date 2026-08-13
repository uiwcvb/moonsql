///|
pub enum TokenKind {
  Keyword(String)
  Identifier(String)
  IntegerLiteral(Int64)
  RealLiteral(Double)
  StringLiteral(String)
  Symbol(String)
  Eof
} derive(Eq, Debug)

///|
pub struct Token {
  kind : TokenKind
  line : Int
  column : Int
} derive(Eq, Debug)

///|
fn is_keyword(s : String) -> Bool {
  match s {
    "CREATE"
    | "TABLE"
    | "INSERT"
    | "INTO"
    | "VALUES"
    | "SELECT"
    | "FROM"
    | "WHERE"
    | "UPDATE"
    | "SET"
    | "DELETE"
    | "DROP"
    | "ORDER"
    | "BY"
    | "ASC"
    | "DESC"
    | "LIMIT"
    | "OFFSET"
    | "AND"
    | "OR"
    | "NOT"
    | "INTEGER"
    | "TEXT"
    | "REAL"
    | "NULL" => true
    _ => false
  }
}

///|
fn digit_value(c : Char) -> Int {
  c.to_int() - '0'.to_int()
}

///|
fn parse_integer_literal(raw : String) -> Int64 {
  let mut value = 0L
  for c in raw {
    value = value * 10L + digit_value(c).to_int64()
  }
  value
}

///|
fn parse_real_literal(raw : String) -> Double {
  let mut value = 0.0
  let mut scale = 1.0
  let mut fractional = false
  for c in raw {
    if c == '.' {
      fractional = true
    } else if fractional {
      scale = scale * 10.0
      value = value + digit_value(c).to_double() / scale
    } else {
      value = value * 10.0 + digit_value(c).to_double()
    }
  }
  value
}

///|
/// A small UTF-16-safe lexer for SQL's ASCII grammar and Unicode identifier tails.
pub fn lex(source : String) -> Result[Array[Token], SqlError] {
  let chars = source.to_array()
  let out : Array[Token] = []
  let mut i = 0
  let mut line = 1
  let mut col = 1
  while i < chars.length() {
    let c = chars[i]
    if c == ' ' || c == '\t' || c == '\r' {
      i = i + 1
      col = col + 1
      continue
    }
    if c == '\n' {
      i = i + 1
      line = line + 1
      col = 1
      continue
    }
    let start = col
    if c.is_ascii_alphabetic() || c == '_' {
      let b = StringBuilder::new()
      while i < chars.length() &&
            (
              chars[i].is_ascii_alphabetic() ||
              chars[i].is_ascii_digit() ||
              chars[i] == '_'
            ) {
        b.write_char(chars[i])
        i = i + 1
        col = col + 1
      }
      let raw = b.to_string()
      let upper = raw.to_upper()
      out.push({
        kind: if is_keyword(upper) {
          Keyword(upper)
        } else {
          Identifier(raw)
        },
        line,
        column: start,
      })
      continue
    }
    if c.is_ascii_digit() {
      let b = StringBuilder::new()
      let mut dot = false
      while i < chars.length() &&
            (chars[i].is_ascii_digit() || (!dot && chars[i] == '.')) {
        if chars[i] == '.' {
          dot = true
        }
        b.write_char(chars[i])
        i = i + 1
        col = col + 1
      }
      let raw = b.to_string()
      if dot {
        out.push({
          kind: RealLiteral(parse_real_literal(raw)),
          line,
          column: start,
        })
      } else {
        out.push({
          kind: IntegerLiteral(parse_integer_literal(raw)),
          line,
          column: start,
        })
      }
      continue
    }
    if c == '\'' {
      i = i + 1
      col = col + 1
      let b = StringBuilder::new()
      let mut closed = false
      while i < chars.length() {
        if chars[i] == '\'' {
          if i + 1 < chars.length() && chars[i + 1] == '\'' {
            b.write_char('\'')
            i = i + 2
            col = col + 2
          } else {
            i = i + 1
            col = col + 1
            closed = true
            break
          }
        } else {
          b.write_char(chars[i])
          i = i + 1
          col = col + 1
        }
      }
      if !closed {
        return Err({ message: "unterminated string", line, column: start })
      }
      out.push({ kind: StringLiteral(b.to_string()), line, column: start })
      continue
    }
    let mut sym = c.to_string()
    if i + 1 < chars.length() {
      let pair = sym + chars[i + 1].to_string()
      if pair == "<>" || pair == "<=" || pair == ">=" {
        sym = pair
        i = i + 1
        col = col + 1
      }
    }
    if sym == "(" ||
      sym == ")" ||
      sym == "," ||
      sym == "*" ||
      sym == ";" ||
      sym == "=" ||
      sym == "<>" ||
      sym == "<" ||
      sym == ">" ||
      sym == "<=" ||
      sym == ">=" {
      out.push({ kind: Symbol(sym), line, column: start })
      i = i + 1
      col = col + 1
    } else {
      return Err({ message: "unexpected character", line, column: start })
    }
  }
  out.push({ kind: Eof, line, column: col })
  Ok(out)
}
