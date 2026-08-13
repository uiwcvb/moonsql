///|
pub enum BinaryOp {
  Eq
  Ne
  Lt
  Gt
  Le
  Ge
  And
  Or
} derive(Eq, Debug)

///|
pub enum Expr {
  Literal(Value)
  ColumnRef(String)
  Binary(Expr, BinaryOp, Expr)
  NotExpr(Expr)
} derive(Eq, Debug)

///|
pub struct OrderSpec {
  column : String
  descending : Bool
} derive(Eq, Debug)

///|
pub enum Projection {
  AllColumns
  NamedColumns(Array[String])
} derive(Eq, Debug)

///|
pub enum Statement {
  CreateTable(String, Array[Column])
  Insert(String, Array[Array[Value]])
  Select(Projection, String, Expr?, OrderSpec?, Int?, Int)
  Update(String, Array[(String, Value)], Expr?)
  Delete(String, Expr?)
  DropTable(String)
} derive(Eq, Debug)
