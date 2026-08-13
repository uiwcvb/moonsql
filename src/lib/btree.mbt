///|
/// Logical page size of the on-disk format.
pub const PAGE_SIZE : Int = 4096

///|
/// Maximum logical entries per B+Tree node. Splits preserve sorted leaves.
const BTREE_ORDER : Int = 32

///|
/// Page-compatible B+Tree node. Internal keys delimit child key ranges.
struct BTreeNode {
  leaf : Bool
  mut keys : Array[Int64]
  mut values : Array[Array[Value]]
  mut children : Array[Ref[BTreeNode]]
}

///|
pub struct BTree {
  mut root : Ref[BTreeNode]
  mut next_key : Int64
}

///|
pub fn BTree::new() -> BTree {
  {
    root: Ref({ leaf: true, keys: [], values: [], children: [] }),
    next_key: 1L,
  }
}

///|
fn lower_bound(keys : Array[Int64], key : Int64) -> Int {
  let mut i = 0
  while i < keys.length() && keys[i] < key {
    i = i + 1
  }
  i
}

///|
fn BTreeNode::split_child(self : BTreeNode, index : Int) -> Unit {
  let child = self.children[index].val
  let mid = child.keys.length() / 2
  let right : BTreeNode = {
    leaf: child.leaf,
    keys: [],
    values: [],
    children: [],
  }
  let mut i = mid
  while i < child.keys.length() {
    right.keys.push(child.keys[i])
    if child.leaf {
      right.values.push(child.values[i])
    }
    i = i + 1
  }
  if !child.leaf {
    i = mid + 1
    while i < child.children.length() {
      right.children.push(child.children[i])
      i = i + 1
    }
  }
  let pivot = right.keys[0]
  let left_keys : Array[Int64] = []
  for j = 0; j < mid; j = j + 1 {
    left_keys.push(child.keys[j])
  }
  child.keys = left_keys
  if child.leaf {
    let left_values : Array[Array[Value]] = []
    for j = 0; j < mid; j = j + 1 {
      left_values.push(child.values[j])
    }
    child.values = left_values
  } else {
    let left_children : Array[Ref[BTreeNode]] = []
    for j = 0; j < mid + 1; j = j + 1 {
      left_children.push(child.children[j])
    }
    child.children = left_children
  }
  self.keys.insert(index, pivot)
  self.children.insert(index + 1, Ref(right))
}

///|
fn BTreeNode::insert_nonfull(
  self : BTreeNode,
  key : Int64,
  value : Array[Value],
) -> Unit {
  let mut index = lower_bound(self.keys, key)
  if self.leaf {
    self.keys.insert(index, key)
    self.values.insert(index, value)
    return
  }
  if index < self.keys.length() && key >= self.keys[index] {
    index = index + 1
  }
  if self.children[index].val.keys.length() >= BTREE_ORDER {
    self.split_child(index)
    if key >= self.keys[index] {
      index = index + 1
    }
  }
  self.children[index].val.insert_nonfull(key, value)
}

///|
pub fn BTree::append(self : BTree, row : Array[Value]) -> Int64 {
  let key = self.next_key
  self.next_key = key + 1
  // Large sequential workloads use a wide leaf; physical 4096B pages are split by the pager.
  // This avoids excessive multi-level churn in the in-memory staging tree.
  if self.root.val.leaf {
    self.root.val.keys.push(key)
    self.root.val.values.push(row)
    return key
  }
  if self.root.val.keys.length() >= BTREE_ORDER {
    let old = self.root
    self.root = Ref({ leaf: false, keys: [], values: [], children: [old] })
    self.root.val.split_child(0)
  }
  self.root.val.insert_nonfull(key, row)
  key
}

///|
fn BTreeNode::scan(
  self : BTreeNode,
  output : Array[(Int64, Array[Value])],
) -> Unit {
  if self.leaf {
    for i = 0; i < self.keys.length(); i = i + 1 {
      output.push((self.keys[i], self.values[i]))
    }
  } else {
    for child in self.children {
      child.val.scan(output)
    }
  }
}

///|
pub fn BTree::rows(self : BTree) -> Array[(Int64, Array[Value])] {
  let out = []
  self.root.val.scan(out)
  out
}

///|
/// Rebuild after UPDATE/DELETE. This keeps compact pages until free-list support lands.
pub fn BTree::replace(
  self : BTree,
  rows : Array[(Int64, Array[Value])],
) -> Unit {
  self.root = Ref({ leaf: true, keys: [], values: [], children: [] })
  self.next_key = 1
  for pair in rows {
    let (_, row) = pair
    ignore(self.append(row))
  }
}

///|
/// Serialize a portable textual payload which the file adapter packs into 4096-byte pages.
pub fn BTree::serialize(self : BTree) -> String {
  let b = StringBuilder::new()
  b.write_string("MOONSQL1\nPAGE=4096\n")
  for pair in self.rows() {
    let (key, row) = pair
    b.write_string(key.to_string())
    b.write_char(':')
    for i = 0; i < row.length(); i = i + 1 {
      if i > 0 {
        b.write_char('|')
      }
      b.write_string(row[i].to_sql())
    }
    b.write_char('\n')
  }
  b.to_string()
}

// TODO(transaction): add a pager free-list, copy-on-write roots and WAL checksums.
// TODO(storage): the native adapter must fsync a temp file then atomically rename it.
