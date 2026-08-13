///|
async fn repl(db : @lib.Connection) -> Unit {
  println("moonsql 0.1.0 — pure MoonBit embedded SQL")
  println("Enter SQL or .help; terminate SQL with an optional semicolon.")
  while true {
    @stdio.stdout.write("moonsql> ")
    match @stdio.stdin.read_until("\n") {
      None => break
      Some(raw) => {
        let line = raw.trim().to_owned()
        if line.length() == 0 {
          continue
        }
        match db.run_line(line) {
          Ok(output) => {
            println(output)
            if line == ".quit" || line == ".exit" {
              break
            }
          }
          Err(error) =>
            println("error:\{error.line}:\{error.column}: \{error.message}")
        }
      }
    }
  }
  db.close()
}

///|
async fn main {
  let args = @env.args()
  let path = if args.length() > 1 { args[1] } else { "moonsql.mdb" }
  repl(@lib.open(path))
}
