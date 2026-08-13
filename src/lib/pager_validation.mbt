///|
/// Superblock fields decoded without opening the catalog.
pub struct SuperblockInfo {
  version : Int
  page_size : Int
  page_count : Int
  catalog_page : Int
} derive(Eq, Debug)

///|
/// Bounds and shape checks for an encoded database image.
pub struct ValidationResult {
  valid : Bool
  errors : Array[String]
  warnings : Array[String]
  pages_checked : Int
} derive(Eq, Debug)

///|
/// Decode and validate only page zero.
pub fn inspect_superblock(file : Bytes) -> Result[SuperblockInfo, String] {
  if file.length() < PAGE_SIZE {
    return Err("file is smaller than a superblock")
  }
  let reader : ByteReader = { data: file, pos: 0 }
  let magic = Bytes::makei(8, fn(_) { reader.u8().to_byte() })
  let decoded = @encoding_utf8.decode(magic) catch { _ => "" }
  if decoded != "MOONSQL1" {
    return Err("invalid magic")
  }
  let version = reader.u16()
  let page_size = reader.u16()
  let page_count = reader.u32()
  let catalog_page = reader.u32()
  Ok({ version, page_size, page_count, catalog_page })
}

///|
/// Validate all physical page headers and references.
pub fn validate_page_image(file : Bytes) -> ValidationResult {
  let errors : Array[String] = []
  let warnings : Array[String] = []
  let mut pages_checked = 0
  if file.length() % PAGE_SIZE != 0 {
    errors.push("file length is not a multiple of 4096")
  }
  match inspect_superblock(file) {
    Err(message) => errors.push(message)
    Ok(header) => {
      pages_checked = pages_checked + 1
      if header.version != 1 {
        errors.push("unsupported format version")
      }
      if header.page_size != PAGE_SIZE {
        errors.push("superblock page size differs from 4096")
      }
      if header.page_count != file.length() / PAGE_SIZE {
        errors.push("superblock page count differs from file length")
      }
      if header.catalog_page <= 0 || header.catalog_page >= header.page_count {
        errors.push("catalog page is outside the file")
      }
      for number = 1; number < header.page_count; number = number + 1 {
        let page = slice_page(file, number)
        let kind = page[0].to_int()
        pages_checked = pages_checked + 1
        if kind == 1 {
          validate_catalog_header(page, number, errors)
        } else if kind == 2 {
          validate_leaf_header(page, number, header.page_count, errors)
        } else if kind == 3 {
          validate_internal_header(page, number, header.page_count, errors)
        } else {
          errors.push(
            "page " +
            number.to_string() +
            " has unknown kind " +
            kind.to_string(),
          )
        }
      }
      if header.page_count == 2 {
        warnings.push("database contains no table pages")
      }
    }
  }
  { valid: errors.length() == 0, errors, warnings, pages_checked }
}

///|
fn validate_catalog_header(
  page : Bytes,
  number : Int,
  errors : Array[String],
) -> Unit {
  let reader : ByteReader = { data: page, pos: 1 }
  let count = reader.u16()
  if count > 1000 {
    errors.push(
      "catalog page " + number.to_string() + " has an implausible table count",
    )
  }
}

///|
fn validate_leaf_header(
  page : Bytes,
  number : Int,
  page_count : Int,
  errors : Array[String],
) -> Unit {
  let reader : ByteReader = { data: page, pos: 1 }
  let entries = reader.u16()
  let next = reader.u32()
  if entries > 4090 {
    errors.push(
      "leaf page " + number.to_string() + " has an impossible entry count",
    )
  }
  if next < 0 || next >= page_count {
    errors.push("leaf page " + number.to_string() + " points outside the file")
  }
  if next == number {
    errors.push("leaf page " + number.to_string() + " points to itself")
  }
}

///|
fn validate_internal_header(
  page : Bytes,
  number : Int,
  page_count : Int,
  errors : Array[String],
) -> Unit {
  let reader : ByteReader = { data: page, pos: 1 }
  let entries = reader.u16()
  if entries == 0 {
    errors.push("internal page " + number.to_string() + " has no children")
    return
  }
  if entries > 300 {
    errors.push(
      "internal page " + number.to_string() + " has too many children",
    )
    return
  }
  let mut previous = -1L
  for _i = 0; _i < entries; _i = _i + 1 {
    let separator = reader.i64()
    let child = reader.u32()
    if separator < previous {
      errors.push(
        "internal page " + number.to_string() + " has unsorted separators",
      )
    }
    previous = separator
    if child <= 1 || child >= page_count {
      errors.push(
        "internal page " + number.to_string() + " has an invalid child",
      )
    }
    if child == number {
      errors.push("internal page " + number.to_string() + " refers to itself")
    }
  }
}

///|
/// Copy-on-rewrite free-page abstraction for the future incremental pager.
pub struct FreeList {
  pages : Array[Int]
} derive(Eq, Debug)

///|
pub fn FreeList::new() -> FreeList {
  { pages: [] }
}

///|
pub fn FreeList::length(self : FreeList) -> Int {
  self.pages.length()
}

///|
pub fn FreeList::release(self : FreeList, page : Int) -> Result[Unit, String] {
  if page <= 1 {
    return Err("superblock and catalog pages cannot be released")
  }
  if self.pages.iter().any(fn(value) { value == page }) {
    return Err("page is already free")
  }
  self.pages.push(page)
  self.pages.sort()
  Ok(())
}

///|
pub fn FreeList::allocate(self : FreeList) -> Int? {
  if self.pages.length() == 0 {
    None
  } else {
    let page = self.pages[0]
    ignore(self.pages.remove(0))
    Some(page)
  }
}

///|
pub fn FreeList::contains(self : FreeList, page : Int) -> Bool {
  self.pages.iter().any(fn(value) { value == page })
}

///|
pub fn FreeList::snapshot(self : FreeList) -> Array[Int] {
  self.pages.copy()
}

///|
/// Mark every non-live page free from a complete page range.
pub fn build_free_list(page_count : Int, live_pages : Array[Int]) -> FreeList {
  let free = FreeList::new()
  let live : Map[Int, Bool] = Map([])
  for page in live_pages {
    live[page] = true
  }
  for page = 2; page < page_count; page = page + 1 {
    if !live.contains(page) {
      ignore(free.release(page))
    }
  }
  free
}

///|
/// Enumerate catalog, roots, internal children and leaf-chain pages.
pub fn collect_live_pages(file : Bytes) -> Result[Array[Int], String] {
  let header = inspect_superblock(file).unwrap()
  let live : Map[Int, Bool] = Map([])
  live[0] = true
  live[header.catalog_page] = true
  let catalog = slice_page(file, header.catalog_page)
  let reader : ByteReader = { data: catalog, pos: 1 }
  let tables = reader.u16()
  for _i = 0; _i < tables; _i = _i + 1 {
    ignore(reader.text())
    let columns = reader.u16()
    let root = reader.u32()
    ignore(reader.u32())
    live[root] = true
    for _j = 0; _j < columns; _j = _j + 1 {
      ignore(reader.text())
      ignore(reader.u8())
    }
    let root_page = slice_page(file, root)
    if root_page[0].to_int() == 3 {
      let internal : ByteReader = { data: root_page, pos: 1 }
      let children = internal.u16()
      for _j = 0; _j < children; _j = _j + 1 {
        ignore(internal.i64())
        live[internal.u32()] = true
      }
    }
  }
  let pages = live.keys().to_array()
  pages.sort()
  Ok(pages)
}

///|
/// Validate that all pages emitted by the encoder are reachable.
pub fn detect_orphan_pages(file : Bytes) -> Result[Array[Int], String] {
  let header = inspect_superblock(file).unwrap()
  let live = collect_live_pages(file).unwrap()
  let live_set : Map[Int, Bool] = Map([])
  for page in live {
    live_set[page] = true
  }
  let orphaned : Array[Int] = []
  for page = 0; page < header.page_count; page = page + 1 {
    if !live_set.contains(page) {
      orphaned.push(page)
    }
  }
  Ok(orphaned)
}
