///|
async fn repl(db : @lib.Connection) -> Unit {
  println("moonsql " + @lib.version() + " - pure MoonBit embedded SQL")
  println("Enter SQL or .help; terminate SQL with a semicolon.")
  let mut pending = ""
  while true {
    @stdio.stdout.write(if pending.length() == 0 { "moonsql> " } else { "   ...> " })
    match @stdio.stdin.read_until("\n") {
      None => {
        // EOF: run whatever was left, like a statement without a trailing `;`.
        if pending.length() > 0 {
          match db.run_line(pending.trim().to_owned()) {
            Ok(output) => println(output)
            Err(error) =>
              println("error:\{error.line}:\{error.column}: \{error.message}")
          }
        }
        break
      }
      Some(raw) => {
        let line = raw.trim().to_owned()
        if line.length() == 0 {
          continue
        }
        if line[0] == ('.' : Byte) {
          // dot commands act immediately and flush any pending buffer
          pending = ""
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
        } else {
          pending = pending + line + " "
          if @lib.sql_ready(pending) {
            match db.run_line(pending.trim().to_owned()) {
              Ok(output) => println(output)
              Err(error) =>
                println("error:\{error.line}:\{error.column}: \{error.message}")
            }
            pending = ""
          }
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