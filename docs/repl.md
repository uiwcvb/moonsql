# REPL contract

Prompt: `moonsql> `. SQL accumulates until a semicolon outside a string. Results print a header and pipe-separated values. Errors use `error:line:column: message`.

- `.tables` calls `Connection::table_names`.
- `.schema NAME` calls `Connection::schema`.
- `.ast SQL` calls `debug_ast`.
- `.version` prints the engine version.
- `.help` prints grammar and dot commands.
- `.quit` and `.exit` close the connection.

`Connection::run_line` implements this dispatcher and result formatting as pure, testable logic. `src/main` feeds it from `moonbitlang/async/stdio` using `stdin.read_until("\\n")`, and closes the selected database on EOF or `.quit`.
