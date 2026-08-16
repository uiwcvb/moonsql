# REPL contract

Prompt: `moonsql> ` (continuation `   ...> `). SQL accumulates until a semicolon outside a string; a trailing line at EOF still runs. Results print a header and pipe-separated values. Errors use `error:line:column: message`.

- `.tables` calls `Connection::table_names`.
- `.schema NAME` calls `Connection::schema`; `.schema` alone lists every table.
- `.ast SQL` calls `debug_ast`.
- `.dump` renders the whole database as replayable SQL.
- `.version` prints the engine version.
- `.help` prints grammar and dot commands.
- `.quit` and `.exit` close the connection.

`Connection::run_line` implements this dispatcher and result formatting as pure, testable logic. `src/main` feeds it from `moonbitlang/async/stdio` using `stdin.read_until("\\n")`, and closes the selected database on EOF or `.quit`.
