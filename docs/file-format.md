# moonsql file format v2

The physical page size is 4096 bytes. All persisted integers are little-endian.

| Page | Contents |
|---|---|
| 0 | magic `MOONSQL1`, format version `2`, page size, page count, catalog page |
| catalog leaves | table name, column names and types, root page IDs |
| table leaves | sorted row ID plus length-prefixed encoded values |
| internal pages | child page IDs and separator row IDs |

Every page is sealed with a 32-bit checksum stored in its final 4 bytes: the page
payload is zero-padded to 4092 bytes, then `checksum = (checksum * 33) ^ byte` over
the first 4092 bytes, little-endian. `open` verifies the checksum of every page
before decoding, so a torn write or bit flip anywhere in the file is reported as
`storage_error` instead of silent corruption. Format version `1` files are rejected.

Value tags are `0=null`, `1=int64`, `2=utf8 text`, `3=IEEE-754 f64`. Unused bytes
are zeroed. Every variable field is bounded by its page and oversized rows will
eventually use overflow pages.

The durable v0.1 connection file is binary and page-aligned. Page 0 contains
`MOONSQL1`, version, page size, page count, and catalog page. Page 1 stores table
names, schemas, roots, and row counts. Table roots are leaf pages or internal pages
whose separator keys map to leaf pages. Leaves contain tagged typed rows and a
next-leaf pointer. `open` validates, checksums and decodes this representation;
`close` rewrites it.
