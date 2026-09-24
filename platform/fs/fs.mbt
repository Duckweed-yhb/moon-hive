///|
/// platform/fs — 文件系统层
///
/// 提供路径判断、目录递归创建/删除、目录遍历与体积统计。
///
/// 为什么要自建：`moonbitlang/core` 没有文件系统模块。验证工作区需要
/// 创建目录、遍历仓库、统计体积、清理临时文件，因此通过 C FFI 自建。
///
/// 安全约束：`rm_rf` 在 C 侧拒绝过短路径与驱动器根；
/// 使用方在删除前应再次确认目标位于自己的工作区根之下。

///|
/// 路径类型
pub enum PathKind {
  None
  File
  Dir
  Other
} derive(Eq, Debug)

// ---------- C FFI 声明 ----------

#borrow(path)
extern "C" fn fs_path_kind_ffi(path : String) -> Int = "fs_path_kind"

#borrow(path)
extern "C" fn fs_exists_ffi(path : String) -> Int = "fs_exists"

#borrow(path)
extern "C" fn fs_mkdir_all_ffi(path : String) -> Int = "fs_mkdir_all"

#borrow(path)
extern "C" fn fs_rm_rf_ffi(path : String) -> Int = "fs_rm_rf"

#borrow(path)
extern "C" fn fs_file_size_ffi(path : String) -> Int64 = "fs_file_size"

#borrow(path)
extern "C" fn fs_dir_bytes_ffi(path : String, max_depth : Int) -> Int64 = "fs_dir_bytes"

#borrow(path, ext)
extern "C" fn fs_list_files_ffi(path : String, ext : String, max_depth : Int) -> String = "fs_list_files"

// ---------- 路径查询 ----------

///|
/// 判断路径类型。不存在返回 `None`，注意与 `Option::None` 同名但不同型。
pub fn path_kind(path : String) -> PathKind {
  let raw = fs_path_kind_ffi(path)
  // C 侧约定：0 不存在 / 1 文件 / 2 目录 / 3 其他
  if raw == 1 {
    File
  } else if raw == 2 {
    Dir
  } else if raw == 3 {
    Other
  } else {
    None
  }
}

///|
/// 路径是否存在
pub fn exists(path : String) -> Bool {
  fs_exists_ffi(path) != 0
}

///|
/// 是否为目录
pub fn is_dir(path : String) -> Bool {
  path_kind(path) == Dir
}

///|
/// 是否为普通文件
pub fn is_file(path : String) -> Bool {
  path_kind(path) == File
}

///|
/// 文件字节大小。目录或不存在返回 -1。
pub fn file_size(path : String) -> Int64 {
  fs_file_size_ffi(path)
}

// ---------- 目录操作 ----------

///|
/// 递归创建目录。成功返回 true。
pub fn mkdir_all(path : String) -> Bool {
  fs_mkdir_all_ffi(path) == 0
}

///|
/// 递归删除目录或文件。成功（或本来就不存在）返回 true。
///
/// 安全说明：C 侧拒绝长度小于 4 的路径与驱动器根，防止误删。
/// 但调用方仍应保证目标在自己的工作区根之下。
pub fn rm_rf(path : String) -> Bool {
  fs_rm_rf_ffi(path) >= 0
}

///|
/// 递归统计目录内所有普通文件的字节数。非目录返回 -1。
pub fn dir_bytes(path : String, max_depth : Int) -> Int64 {
  fs_dir_bytes_ffi(path, max_depth)
}

// ---------- 遍历 ----------

///|
/// 列出目录下所有普通文件的完整路径。
///
/// - `ext`：非空时只保留该扩展名结尾的文件（例如 `".mbt"`）
/// - `max_depth`：递归深度上限
///
/// 返回按遍历顺序排列的数组；目录不存在或为空时返回空数组。
pub fn list_files(path : String, ext : String, max_depth : Int) -> Array[String] {
  let raw = fs_list_files_ffi(path, ext, max_depth)
  let result : Array[String] = []
  if raw.length() == 0 {
    return result
  }
  for line in raw.split("\n") {
    let s = line.to_owned()
    if s.length() > 0 {
      result.push(s)
    }
  }
  result
}

///|
/// 统计目录下匹配扩展名的文件数量
pub fn count_files(path : String, ext : String, max_depth : Int) -> Int {
  list_files(path, ext, max_depth).length()
}

// ---------- 目录复制 ----------

#borrow(src, dst)
extern "C" fn fs_copy_tree_ffi(src : String, dst : String) -> Int = "fs_copy_tree"

#borrow(src, dst)
extern "C" fn fs_copy_file_ffi(src : String, dst : String) -> Int = "fs_copy_file"

///|
/// 递归复制目录树。
///
/// 用途：把用户已有的本地 checkout 复制进隔离工作区再验证——
/// 这样既不污染原目录，也无需联网。
///
/// 自动跳过 `.git` / `_build` / `target` / `node_modules`：
/// 它们与"能不能编译"无关，且体积可能很大。
pub fn copy_tree(src : String, dst : String) -> Bool {
  fs_copy_tree_ffi(src, dst) == 0
}

///|
/// 复制单个文件
pub fn copy_file(src : String, dst : String) -> Bool {
  fs_copy_file_ffi(src, dst) == 0
}

// ---------- 文本读写 ----------

#borrow(path)
extern "C" fn fs_read_text_ffi(path : String) -> String = "fs_read_text"

#borrow(path, content)
extern "C" fn fs_write_text_ffi(path : String, content : String) -> Int = "fs_write_text"

///|
/// 读取文本文件（按 UTF-8 解码）。
/// 文件不存在或不可读时返回空串。
pub fn read_text(path : String) -> String {
  fs_read_text_ffi(path)
}

///|
/// 写文本文件（覆盖写，UTF-8 编码）。成功返回 true。
pub fn write_text(path : String, content : String) -> Bool {
  fs_write_text_ffi(path, content) == 0
}

#borrow(path)
extern "C" fn fs_remove_ffi(path : String) -> Int = "fs_remove"

///|
/// 删除文件。返回是否成功。
pub fn remove_file(path : String) -> Bool {
  fs_remove_ffi(path) == 0
}

// ---------- 单元测试 ----------
// 这些测试会真实读写临时目录。每个用例使用独立目录，避免相互干扰。

///|
/// 在临时目录下准备一个唯一的测试目录路径（毫秒时间戳保证唯一）
fn test_dir(tag : String) -> String {
  let base = @proc.temp_dir()
  let stamp = @env.now()
  @proc.join_path(base, "moonhive-fs-test-" + tag + "-" + stamp.to_string())
}

///|
/// 在指定目录下写一个文本文件。直接走 fs 层（不依赖 shell，跨平台一致）
fn write_file(path : String, content : String) -> Bool {
  write_text(path, content)
}

test "mkdir_all 创建多级目录并可识别为目录" {
  let d = test_dir("mkdir")
  let nested = @proc.join_path(@proc.join_path(d, "a"), "b")
  assert_true(mkdir_all(nested))
  assert_true(is_dir(nested))
  assert_true(exists(d))
  assert_true(rm_rf(d))
  assert_false(exists(d))
}

test "path_kind 区分文件与目录" {
  let d = test_dir("kind")
  assert_true(mkdir_all(d))
  let f = @proc.join_path(d, "sample.txt")
  assert_true(write_file(f, "hello"))
  assert_eq(path_kind(d), Dir)
  assert_eq(path_kind(f), File)
  assert_eq(path_kind(@proc.join_path(d, "nope.txt")), None)
  assert_true(rm_rf(d))
}

test "file_size 对文件返回字节数，对目录返回 -1" {
  let d = test_dir("size")
  assert_true(mkdir_all(d))
  let f = @proc.join_path(d, "payload.txt")
  assert_true(write_file(f, "abcdefghij"))
  assert_true(file_size(f) > 0)
  assert_eq(file_size(d), -1L)
  assert_eq(file_size(@proc.join_path(d, "missing")), -1L)
  assert_true(rm_rf(d))
}

test "list_files 按扩展名过滤" {
  let d = test_dir("list")
  assert_true(mkdir_all(d))
  ignore(write_file(@proc.join_path(d, "one.mbt"), "1"))
  ignore(write_file(@proc.join_path(d, "two.mbt"), "2"))
  ignore(write_file(@proc.join_path(d, "readme.md"), "3"))

  let mbt = list_files(d, ".mbt", 4)
  assert_eq(mbt.length(), 2)
  let all = list_files(d, "", 4)
  assert_eq(all.length(), 3)
  let md = list_files(d, ".md", 4)
  assert_eq(md.length(), 1)
  assert_true(rm_rf(d))
}

test "list_files 递归进入子目录" {
  let d = test_dir("recurse")
  let sub = @proc.join_path(d, "sub")
  assert_true(mkdir_all(sub))
  ignore(write_file(@proc.join_path(d, "top.mbt"), "1"))
  ignore(write_file(@proc.join_path(sub, "deep.mbt"), "2"))

  let deep = list_files(d, ".mbt", 4)
  assert_eq(deep.length(), 2)
  // 深度限制为 0 时只能看到顶层
  let shallow = list_files(d, ".mbt", 0)
  assert_eq(shallow.length(), 1)
  assert_true(rm_rf(d))
}

test "dir_bytes 累计普通文件体积" {
  let d = test_dir("bytes")
  assert_true(mkdir_all(d))
  ignore(write_file(@proc.join_path(d, "a.txt"), "12345"))
  let one = dir_bytes(d, 4)
  assert_true(one > 0)
  // 非目录返回 -1
  let f = @proc.join_path(d, "a.txt")
  assert_eq(dir_bytes(f, 4), -1L)
  assert_true(rm_rf(d))
}

test "rm_rf 删除不存在的路径视为成功" {
  let d = test_dir("noexist")
  assert_true(rm_rf(d))
  assert_false(exists(d))
}

test "rm_rf 拒绝过短路径（安全护栏）" {
  // C 侧对长度 < 4 的路径直接拒绝，防止误删根目录
  assert_false(rm_rf("C:"))
  assert_false(rm_rf(""))
}

test "count_files 与 list_files 结果一致" {
  let d = test_dir("count")
  assert_true(mkdir_all(d))
  ignore(write_file(@proc.join_path(d, "x.mbt"), "1"))
  ignore(write_file(@proc.join_path(d, "y.mbt"), "2"))
  assert_eq(count_files(d, ".mbt", 4), 2)
  assert_eq(count_files(d, ".zig", 4), 0)
  assert_true(rm_rf(d))
}
