///|
/// Trailing FNV-1a checksum bytes appended to every sealed page.
const CHECKSUM_SIZE : Int = 4

///|
priv struct ByteWriter {
  data : Array[Byte]
}

///|
fn ByteWriter::u8(self : ByteWriter, v : Int) -> Unit {
  self.data.push(v.to_byte())
}

///|
fn ByteWriter::u16(self : ByteWriter, v : Int) -> Unit {
  self.u8(v)
  self.u8(v >> 8)
}

///|
fn ByteWriter::u32(self : ByteWriter, v : Int) -> Unit {
  self.u8(v)
  self.u8(v >> 8)
  self.u8(v >> 16)
  self.u8(v >> 24)
}

///|
fn ByteWriter::i64(self : ByteWriter, v : Int64) -> Unit {
  let bits = v.reinterpret_as_uint64()
  for shift = 0; shift < 64; shift = shift + 8 {
    self.u8((bits >> shift).to_int())
  }
}

///|
fn ByteWriter::raw(self : ByteWriter, bytes : Bytes) -> Unit {
  for byte in bytes {
    self.data.push(byte)
  }
}

///|
fn ByteWriter::text(self : ByteWriter, value : String) -> Unit {
  let bytes = @encoding_utf8.encode(value)
  self.u16(bytes.length())
  self.raw(bytes)
}

///|
fn ByteWriter::value(self : ByteWriter, value : Value) -> Unit {
  match value {
    Null => self.u8(0)
    Integer(v) => {
      self.u8(1)
      self.i64(v)
    }
    Text(v) => {
      self.u8(2)
      self.text(v)
    }
    Real(v) => {
      self.u8(3)
      self.i64(v.reinterpret_as_int64())
    }
  }
}

///|
fn ByteWriter::page(self : ByteWriter) -> Result[Array[Byte], String] {
  if self.data.length() > PAGE_SIZE - CHECKSUM_SIZE {
    return Err("page overflow")
  }
  while self.data.length() < PAGE_SIZE - CHECKSUM_SIZE {
    self.data.push((0 : Int).to_byte())
  }
  Ok(self.data)
}

///|
/// 32-bit djb2-style hash over the first `PAGE_SIZE - 4` bytes of a page.
fn fnv1a32(page : Bytes) -> Int {
  let mut hash = 5381
  for i = 0; i < PAGE_SIZE - 4; i = i + 1 {
    hash = ((hash << 5) + hash + page[i].to_int()) & 0x7FFFFFFF
  }
  hash
}

///|
fn fnv1a32_array(page : Array[Byte]) -> Int {
  let mut hash = 5381
  for i = 0; i < PAGE_SIZE - 4; i = i + 1 {
    hash = ((hash << 5) + hash + page[i].to_int()) & 0x7FFFFFFF
  }
  hash
}

///|
/// Append the page checksum to the last four bytes of a page image.
pub fn seal_page(page : Array[Byte]) -> Array[Byte] {
  let hash = fnv1a32_array(page)
  let out = page.copy()
  while out.length() < PAGE_SIZE {
    out.push((0 : Int).to_byte())
  }
  out[PAGE_SIZE - 4] = (hash & 0xFF).to_byte()
  out[PAGE_SIZE - 3] = ((hash >> 8) & 0xFF).to_byte()
  out[PAGE_SIZE - 2] = ((hash >> 16) & 0xFF).to_byte()
  out[PAGE_SIZE - 1] = ((hash >> 24) & 0xFF).to_byte()
  out
}

///|
/// Verify the trailing checksum of a sealed page image.
pub fn verify_page(file : Bytes, number : Int) -> Bool {
  let page = slice_page(file, number)
  let hash = fnv1a32(page)
  hash ==
  (page[PAGE_SIZE - 4].to_int() | (page[PAGE_SIZE - 3].to_int() << 8) |
  (page[PAGE_SIZE - 2].to_int() << 16) |
  (page[PAGE_SIZE - 1].to_int() << 24))
}

///|
priv struct ByteReader {
  data : Bytes
  mut pos : Int
}

///|
fn ByteReader::u8(self : ByteReader) -> Int {
  let v = self.data[self.pos].to_int()
  self.pos = self.pos + 1
  v
}

///|
fn ByteReader::u16(self : ByteReader) -> Int {
  let a = self.u8()
  let b = self.u8()
  a | (b << 8)
}

///|
fn ByteReader::u32(self : ByteReader) -> Int {
  let a = self.u8()
  let b = self.u8()
  let c = self.u8()
  let d = self.u8()
  a | (b << 8) | (c << 16) | (d << 24)
}

///|
fn ByteReader::i64(self : ByteReader) -> Int64 {
  let mut v = 0UL
  for shift = 0; shift < 64; shift = shift + 8 {
    v = v | (self.u8().to_uint64() << shift)
  }
  v.reinterpret_as_int64()
}

///|
fn ByteReader::text(self : ByteReader) -> String {
  let n = self.u16()
  let bytes = Bytes::makei(n, fn(_) { self.u8().to_byte() })
  @encoding_utf8.decode(bytes) catch {
    _ => ""
  }
}

///|
fn ByteReader::value(self : ByteReader) -> Value {
  match self.u8() {
    0 => Null
    1 => Integer(self.i64())
    2 => Text(self.text())
    3 => Real(self.i64().reinterpret_as_double())
    _ => Null
  }
}

///|
priv struct CatalogRecord {
  name : String
  columns : Array[Column]
  root : Int
  count : Int
}

///|
fn slice_page(file : Bytes, number : Int) -> Bytes {
  Bytes::makei(PAGE_SIZE, fn(i) { file[number * PAGE_SIZE + i] })
}

///|
fn row_size(row : Array[Value]) -> Int {
  let mut n = 10
  for value in row {
    let size = match value {
      Null => 1
      Integer(_) => 9
      Real(_) => 9
      Text(s) => 3 + @encoding_utf8.encode(s).length()
    }
    n = n + size
  }
  n
}

///|
fn encode_database(tables : Map[String, Table]) -> Result[Bytes, String] {
  let pages : Array[Array[Byte]] = [[], []]
  let catalog : Array[CatalogRecord] = []
  let names = tables.keys().to_array()
  names.sort()
  for name in names {
    let table = tables[name]
    let rows = table.rows.rows()
    let groups : Array[Array[(Int64, Array[Value])]] = []
    let mut group : Array[(Int64, Array[Value])] = []
    let mut used = 7
    for pair in rows {
      let (_, row) = pair
      let size = row_size(row)
      if size + 7 > PAGE_SIZE - CHECKSUM_SIZE {
        return Err("row exceeds page")
      }
      if used + size > PAGE_SIZE - CHECKSUM_SIZE {
        groups.push(group)
        group = []
        used = 7
      }
      group.push(pair)
      used = used + size
    }
    if group.length() > 0 || groups.length() == 0 {
      groups.push(group)
    }
    let leaf_pages : Array[(Int64, Int)] = []
    for i = 0; i < groups.length(); i = i + 1 {
      let number = pages.length()
      let w : ByteWriter = { data: [] }
      w.u8(2)
      w.u16(groups[i].length())
      w.u32(if i + 1 < groups.length() { number + 1 } else { 0 })
      for pair in groups[i] {
        let (key, row) = pair
        w.i64(key)
        w.u16(row.length())
        for value in row {
          w.value(value)
        }
      }
      pages.push(seal_page(w.page().unwrap()))
      leaf_pages.push(
        (if groups[i].length() > 0 { groups[i][0].0 } else { 0L }, number),
      )
    }
    let root = if leaf_pages.length() == 1 {
      leaf_pages[0].1
    } else {
      let w : ByteWriter = { data: [] }
      w.u8(3)
      w.u16(leaf_pages.length())
      for pair in leaf_pages {
        w.i64(pair.0)
        w.u32(pair.1)
      }
      let number = pages.length()
      pages.push(seal_page(w.page().unwrap()))
      number
    }
    catalog.push({ name, columns: table.columns, root, count: rows.length() })
  }
  let cw : ByteWriter = { data: [] }
  cw.u8(1)
  cw.u16(catalog.length())
  for record in catalog {
    cw.text(record.name)
    cw.u16(record.columns.length())
    cw.u32(record.root)
    cw.u32(record.count)
    for column in record.columns {
      cw.text(column.name)
      cw.u8(
        match column.data_type {
          IntegerType => 1
          TextType => 2
          RealType => 3
        },
      )
    }
  }
  pages[1] = seal_page(cw.page().unwrap())
  let hw : ByteWriter = { data: [] }
  hw.raw(@encoding_utf8.encode("MOONSQL1"))
  hw.u16(2)
  hw.u16(PAGE_SIZE)
  hw.u32(pages.length())
  hw.u32(1)
  pages[0] = seal_page(hw.page().unwrap())
  let all : Array[Byte] = []
  for page in pages {
    for byte in page {
      all.push(byte)
    }
  }
  Ok(Bytes::from_array(all))
}

///|
fn decode_database(file : Bytes) -> Result[Map[String, Table], String] {
  if file.length() < PAGE_SIZE * 2 || file.length() % PAGE_SIZE != 0 {
    return Err("invalid page-aligned file")
  }
  let h : ByteReader = { data: file, pos: 0 }
  let magic = Bytes::makei(8, fn(_) { h.u8().to_byte() })
  if (@encoding_utf8.decode(magic) catch { _ => "" }) != "MOONSQL1" {
    return Err("invalid magic")
  }
  if h.u16() != 2 || h.u16() != PAGE_SIZE {
    return Err("unsupported format")
  }
  let page_count = h.u32()
  let catalog_page = h.u32()
  if page_count != file.length() / PAGE_SIZE {
    return Err("page count mismatch")
  }
  for number = 0; number < page_count; number = number + 1 {
    if !verify_page(file, number) {
      return Err("checksum mismatch on page " + number.to_string())
    }
  }
  let c : ByteReader = { data: slice_page(file, catalog_page), pos: 0 }
  if c.u8() != 1 {
    return Err("catalog kind mismatch")
  }
  let records = c.u16()
  let tables : Map[String, Table] = Map([])
  for _i = 0; _i < records; _i = _i + 1 {
    let name = c.text()
    let width = c.u16()
    let root = c.u32()
    let count = c.u32()
    let columns : Array[Column] = []
    for _j = 0; _j < width; _j = _j + 1 {
      let column = c.text()
      let typ = match c.u8() {
        1 => IntegerType
        2 => TextType
        _ => RealType
      }
      columns.push({ name: column, data_type: typ })
    }
    let root_page = slice_page(file, root)
    let leaves : Array[Int] = []
    if root_page[0].to_int() == 2 {
      leaves.push(root)
    } else {
      let ir : ByteReader = { data: root_page, pos: 1 }
      let n = ir.u16()
      for _j = 0; _j < n; _j = _j + 1 {
        ignore(ir.i64())
        leaves.push(ir.u32())
      }
    }
    let tree = BTree::new()
    let mut loaded = 0
    for leaf in leaves {
      let lr : ByteReader = { data: slice_page(file, leaf), pos: 1 }
      let n = lr.u16()
      ignore(lr.u32())
      for _j = 0; _j < n; _j = _j + 1 {
        ignore(lr.i64())
        let w = lr.u16()
        let row : Array[Value] = []
        for _k = 0; _k < w; _k = _k + 1 {
          row.push(lr.value())
        }
        ignore(tree.append(row))
        loaded = loaded + 1
      }
    }
    if loaded != count {
      return Err("row count mismatch")
    }
    tables[name] = { columns, rows: tree }
  }
  Ok(tables)
}
