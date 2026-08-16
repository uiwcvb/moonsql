///|
async fn repl(db : @lib.Connection) -> Unit {
  println("moonsql " + @lib.version() + " - pure MoonBit embedded SQL")
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
const VERSION : String = "0.1.0"

///|
const USAGE : String =
  "usage: moonsql [--file PATH] [--version] [--help]\n" +
  "  --file PATH   open (or create) the database file (default: moonsql.mdb)\n" +
  "  --version     print the engine version and exit\n" +
  "  --help        print this message and exit"

///|
async fn main {
  let args = @env.args()
  match @lib.resolve_args(args) {
    Err("version") => println("moonsql " + VERSION)
    Err("help") => println(USAGE)
    Err(message) => {
      println("error: " + message)
      println(USAGE)
    }
    Ok(path) => repl(@lib.open(path))
  }
}