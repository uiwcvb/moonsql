# Architecture

## Parse-to-execute pipeline

1. `lexer.mbt` scans the source into positioned tokens. Keywords are ASCII case-insensitive; identifier spelling is preserved. SQL strings use doubled-quote escaping.
2. `parser.mbt` is recursive descent. Boolean precedence is `NOT`, comparison, `AND`, `OR`. It rejects trailing input and returns structured positions.
3. `ast.mbt` separates projection, expressions, ordering and statement kinds.
4. `executor.mbt` resolves columns against a table schema, coerces only INTEGER to REAL, filters, sorts, slices, projects and mutates rows.
5. `btree.mbt` owns monotonically generated row IDs and sorted leaves. Full nodes split at their median. UPDATE and DELETE compact by rebuilding until a page free-list exists.

## Invariants

- Every stored row has exactly the schema's arity and types.
- Leaf keys are ascending; internal keys delimit child ranges.
- SELECT evaluates WHERE on full rows before projection.
- UPDATE validation occurs per target column; unknown tables and columns are errors.
- Connection methods reject operations after `close`.

## Persistence

The project intentionally has no `extern "c"`. `open(path)` validates and decodes a page-aligned binary image (format v2: every 4096B page sealed with a 32-bit checksum, so corrupted files surface as `storage_error`). `close()` encodes the catalog, schema, B+Tree internal pages, leaf pages and typed rows through `moonbitlang/x/fs`; `:memory:` performs no I/O. Atomic rename and explicit fsync remain necessary for crash safety.

Transaction upgrade path: reserve two superblock slots, add generation numbers, extend the checksum scheme, then implement copy-on-write dirty pages plus a WAL. This is deliberately a TODO rather than pretending the current single-writer design is transactional.
