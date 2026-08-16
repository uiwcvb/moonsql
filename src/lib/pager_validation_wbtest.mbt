///|
test "inspect empty superblock" {
  let bytes = encode_database(Map([])).unwrap()
  let header = inspect_superblock(bytes).unwrap()
  assert_eq(header.version, 2)
  assert_eq(header.page_size, 4096)
  assert_eq(header.page_count, 2)
  assert_eq(header.catalog_page, 1)
}

///|
test "validate empty image" {
  let result = validate_page_image(encode_database(Map([])).unwrap())
  assert_true(result.valid)
  assert_eq(result.pages_checked, 2)
  assert_eq(result.warnings.length(), 1)
}

///|
test "validate fixture image" {
  let db = fixture()
  let bytes = encode_database(db.tables).unwrap()
  let result = validate_page_image(bytes)
  assert_true(result.valid)
  assert_eq(result.errors.length(), 0)
}

///|
test "superblock rejects short input" {
  assert_true(inspect_superblock(Bytes::new(10)) is Err(_))
}

///|
test "validator rejects short input" {
  let result = validate_page_image(Bytes::new(10))
  assert_false(result.valid)
}

///|
test "validator rejects bad magic" {
  let data = encode_database(Map([])).unwrap().to_array()
  data[0] = (0 : Int).to_byte()
  assert_false(validate_page_image(Bytes::from_array(data)).valid)
}

///|
test "validator rejects bad version" {
  let data = encode_database(Map([])).unwrap().to_array()
  data[8] = (1 : Int).to_byte()
  assert_false(validate_page_image(Bytes::from_array(data)).valid)
}

///|
test "validator rejects bad page size" {
  let data = encode_database(Map([])).unwrap().to_array()
  data[10] = (1 : Int).to_byte()
  assert_false(validate_page_image(Bytes::from_array(data)).valid)
}

///|
test "validator rejects bad catalog pointer" {
  let data = encode_database(Map([])).unwrap().to_array()
  data[16] = (99 : Int).to_byte()
  assert_false(validate_page_image(Bytes::from_array(data)).valid)
}

///|
test "validator rejects unknown page kind" {
  let data = encode_database(Map([])).unwrap().to_array()
  data[PAGE_SIZE] = (99 : Int).to_byte()
  assert_false(validate_page_image(Bytes::from_array(data)).valid)
}

///|
test "free list begins empty" {
  let free = FreeList::new()
  assert_eq(free.length(), 0)
  assert_eq(free.allocate(), None)
}

///|
test "free list release allocate" {
  let free = FreeList::new()
  assert_true(free.release(4) is Ok(_))
  assert_eq(free.length(), 1)
  assert_eq(free.allocate(), Some(4))
  assert_eq(free.length(), 0)
}

///|
test "free list allocates ascending" {
  let free = FreeList::new()
  ignore(free.release(9))
  ignore(free.release(3))
  ignore(free.release(7))
  assert_eq(free.allocate(), Some(3))
  assert_eq(free.allocate(), Some(7))
  assert_eq(free.allocate(), Some(9))
}

///|
test "free list rejects reserved page zero" {
  let free = FreeList::new()
  assert_true(free.release(0) is Err(_))
}

///|
test "free list rejects reserved catalog" {
  let free = FreeList::new()
  assert_true(free.release(1) is Err(_))
}

///|
test "free list rejects duplicate" {
  let free = FreeList::new()
  ignore(free.release(3))
  assert_true(free.release(3) is Err(_))
}

///|
test "free list contains" {
  let free = FreeList::new()
  ignore(free.release(8))
  assert_true(free.contains(8))
  assert_false(free.contains(9))
}

///|
test "free list snapshot independent" {
  let free = FreeList::new()
  ignore(free.release(8))
  let snapshot = free.snapshot()
  ignore(free.allocate())
  assert_eq(snapshot, [8])
}

///|
test "build free list from live pages" {
  let free = build_free_list(8, [0, 1, 2, 5])
  assert_eq(free.snapshot(), [3, 4, 6, 7])
}

///|
test "collect live empty database" {
  let bytes = encode_database(Map([])).unwrap()
  assert_eq(collect_live_pages(bytes).unwrap(), [0, 1])
}

///|
test "collect live fixture" {
  let db = fixture()
  let bytes = encode_database(db.tables).unwrap()
  assert_eq(collect_live_pages(bytes).unwrap(), [0, 1, 2])
}

///|
test "no orphan pages in empty database" {
  let bytes = encode_database(Map([])).unwrap()
  assert_eq(detect_orphan_pages(bytes).unwrap(), [])
}

///|
test "no orphan pages in fixture" {
  let db = fixture()
  let bytes = encode_database(db.tables).unwrap()
  assert_eq(detect_orphan_pages(bytes).unwrap(), [])
}

///|
test "no orphan pages in multi leaf database" {
  let tables : Map[String, Table] = Map([])
  let tree = BTree::new()
  let payload = "abcdefghijabcdefghijabcdefghijabcdefghijabcdefghij"
  for i = 0; i < 1000; i = i + 1 {
    ignore(tree.append([Integer(i.to_int64()), Text(payload)]))
  }
  tables["large"] = {
    columns: [
      { name: "id", data_type: IntegerType },
      { name: "payload", data_type: TextType },
    ],
    rows: tree,
  }
  let bytes = encode_database(tables).unwrap()
  assert_true(validate_page_image(bytes).valid)
  assert_eq(detect_orphan_pages(bytes).unwrap(), [])
}

///|
test "physical page count grows with rows" {
  let small = fixture()
  let small_pages = encode_database(small.tables).unwrap().length() / PAGE_SIZE
  let tables : Map[String, Table] = Map([])
  let tree = BTree::new()
  for i = 0; i < 1000; i = i + 1 {
    ignore(tree.append([Integer(i.to_int64()), Text("payload")]))
  }
  tables["large"] = {
    columns: [
      { name: "id", data_type: IntegerType },
      { name: "payload", data_type: TextType },
    ],
    rows: tree,
  }
  let large_pages = encode_database(tables).unwrap().length() / PAGE_SIZE
  assert_true(large_pages > small_pages)
}

///|
test "checksum detects single corrupted byte" {
  let bytes = encode_database(fixture().tables).unwrap().to_array()
  let flipped = (bytes[100].to_int() ^ 0xFF).to_byte()
  bytes[100] = flipped
  assert_false(validate_page_image(Bytes::from_array(bytes)).valid)
}

///|
test "checksum rejects bit flip in leaf data" {
  let bytes = encode_database(fixture().tables).unwrap().to_array()
  let leaf_byte = PAGE_SIZE * 2 + 50
  bytes[leaf_byte] = (bytes[leaf_byte].to_int() ^ 0x01).to_byte()
  assert_false(validate_page_image(Bytes::from_array(bytes)).valid)
}

///|
test "checksum accepts untouched image" {
  let bytes = encode_database(fixture().tables).unwrap()
  assert_true(validate_page_image(bytes).valid)
}
