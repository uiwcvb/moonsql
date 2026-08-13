# moonsql file format v1

The physical page size is 4096 bytes. All persisted integers are little-endian.

| Page | Contents |
|---|---|
| 0 | magic `MOONSQL1`, format version, page size, schema root, catalog root |
| catalog leaves | table name, column names and types, root page IDs |
| table leaves | sorted row ID plus length-prefixed encoded values |
| internal pages | child page IDs and separator row IDs |

Value tags are planned as `0=null`, `1=int64`, `2=utf8 text`, `3=IEEE-754 f64`. Unused bytes are zeroed. Every variable field is bounded by its page and oversized rows will eventually use overflow pages.

The durable v0.1 connection file is binary and page-aligned. Page 0 contains `MOONSQL1`, version, page size, page count, and catalog page. Page 1 stores table names, schemas, roots, and row counts. Table roots are leaf pages or internal pages whose separator keys map to leaf pages. Leaves contain tagged typed rows and a next-leaf pointer. `open` validates and decodes this representation; `close` rewrites it.
