///|
/// SQL scalar values. Null is reserved for a future nullable-column extension.
pub enum Value {
  Integer(Int64)
  Text(String)
  Real(Double)
  Null
} derive(Eq, Debug)

///|
pub enum DataType {
  IntegerType
  TextType
  RealType
} derive(Eq, Debug)

///|
pub struct Column {
  name : String
  data_type : DataType
} derive(Eq, Debug)

///|
pub struct QueryResult {
  columns : Array[String]
  rows : Array[Array[Value]]
} derive(Eq, Debug)

///|
/// Structured errors always carry a one-based source position.
pub struct SqlError {
  message : String
  line : Int
  column : Int
} derive(Eq, Debug)

///|
pub fn Value::to_sql(self : Value) -> String {
  match self {
    Integer(v) => v.to_string()
    Text(v) => v
    Real(v) => v.to_string()
    Null => "NULL"
  }
}

///|
fn value_compare(a : Value, b : Value) -> Int {
  match (a, b) {
    (Integer(x), Integer(y)) => x.compare(y)
    (Real(x), Real(y)) => x.compare(y)
    (Integer(x), Real(y)) => x.to_double().compare(y)
    (Real(x), Integer(y)) => x.compare(y.to_double())
    (Text(x), Text(y)) => x.compare(y)
    (Null, Null) => 0
    (Null, _) => -1
    (_, Null) => 1
    _ => 0
  }
}

///|
fn coerce(value : Value, typ : DataType) -> Value? {
  match (value, typ) {
    (Integer(v), IntegerType) => Some(Integer(v))
    (Integer(v), RealType) => Some(Real(v.to_double()))
    (Real(v), RealType) => Some(Real(v))
    (Text(v), TextType) => Some(Text(v))
    (Null, _) => Some(Null)
    _ => None
  }
}
