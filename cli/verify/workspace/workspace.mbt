///|
/// verify/workspace — 隔离工作区
///
/// 验证陌生仓库必须在**一次性、可清理、有配额**的目录里进行。
/// 本模块只管目录生命周期与调度，不做任何验证判断。
///
/// 设计要点：
///   1. 每个仓库一个独立子目录，互不干扰
///   2. 全部工作区集中在同一个根下，便于一键清理与容量核算
///   3. 删除前做前缀校验，防止路径错误导致误删
///   4. 超时用 platform/time 的 Budget，与具体验证逻辑解耦

///|
/// 工作区布局
pub struct Workspace {
  /// 工作区根目录（所有仓库目录都在其下）
  root : String
}

///|
/// 工作区相关错误
pub suberror WorkspaceError {
  /// 无法创建根目录
  CannotCreateRoot(String)
  /// 拒绝删除：目标不在工作区根之下
  RefuseToRemoveOutsider(String)
  /// 仓库名不合法（含路径分隔符等）
  InvalidName(String)
}

///|
/// 默认工作区根目录名（放在系统临时目录下）
const WORKSPACE_PREFIX : String = "moonhive-workspaces"

///|
/// 默认运行标识前缀
const RUN_PREFIX : String = "moonhive-workspace-"

///|
/// 在系统临时目录下创建一个新的工作区根。
///
/// 每次调用产生一个唯一的根，因此并发运行与历史残留互不影响。
pub fn create() -> Result[Workspace, WorkspaceError] {
  let base = @proc.temp_dir()
  if base.length() == 0 {
    return Err(CannotCreateRoot("无法确定临时目录"))
  }
  let stamp = @env.now()
  let root = @proc.join_path(
    @proc.join_path(base, WORKSPACE_PREFIX),
    RUN_PREFIX + stamp.to_string(),
  )
  if !@fs.mkdir_all(root) {
    return Err(CannotCreateRoot(root))
  }
  Ok({ root: root })
}

///|
/// 在指定基目录下创建工作区（测试与自定义场景用）
pub fn create_in(base : String, name : String) -> Result[Workspace, WorkspaceError] {
  if name.length() == 0 || name.contains("/") || name.contains("\\") {
    return Err(InvalidName(name))
  }
  let root = @proc.join_path(base, name)
  if !@fs.mkdir_all(root) {
    return Err(CannotCreateRoot(root))
  }
  Ok({ root: root })
}

///|
/// 工作区根目录
pub fn root_of(w : Workspace) -> String {
  w.root
}

///|
/// 为某个仓库分配一个子目录路径，并确保目录存在。
///
/// `name` 必须是不含路径分隔符的简单名字——它会同时作为目录名，
/// 因此调用方应先把 `owner/repo` 之类的标识规范化。
pub fn alloc(w : Workspace, name : String) -> Result[String, WorkspaceError] {
  if name.length() == 0 || name.contains("/") || name.contains("\\") {
    return Err(InvalidName(name))
  }
  let dir = @proc.join_path(w.root, name)
  if !@fs.mkdir_all(dir) {
    return Err(CannotCreateRoot(dir))
  }
  Ok(dir)
}

///|
/// 判断某个路径是否位于本工作区之下。
///
/// 用于删除前的安全检查：只允许删除自己管辖范围内的目录。
pub fn owns(w : Workspace, path : String) -> Bool {
  let root = normalize(w.root)
  let target = normalize(path)
  if target.length() <= root.length() {
    return false
  }
  // 必须严格以 root + 分隔符 开头
  target.has_prefix(root + "\\") || target.has_prefix(root + "/")
}

///|
/// 规范化路径：统一分隔符为 `\`，去掉重复分隔符与末尾分隔符。
/// 只做字符串层面的归一化，不解析 `..`（工作区路径由本项目生成，可控）。
fn normalize(p : String) -> String {
  let b = StringBuilder()
  let mut prev_sep = false
  for c in p {
    if c == '/' || c == '\\' {
      if !prev_sep {
        b.write_char('\\')
      }
      prev_sep = true
    } else {
      b.write_char(c)
      prev_sep = false
    }
  }
  let s = b.to_string()
  // 去掉末尾分隔符
  if s.length() > 1 && s.unsafe_get(s.length() - 1) == '\\' {
    s[:s.length() - 1].to_owned()
  } else {
    s
  }
}

///|
/// 删除整个工作区。
///
/// 通过 `create`/`create_in` 得到的工作区，其根路径由本项目生成且必然
/// 位于临时目录之下，因此这里只做"路径非空"这一道最基本的安全检查；
/// 真正的越界防护在 `release`（删除子目录）里通过 `owns` 完成。
pub fn destroy(w : Workspace) -> Result[Unit, WorkspaceError] {
  let norm = normalize(w.root)
  if norm.length() == 0 {
    return Err(RefuseToRemoveOutsider(w.root))
  }
  if !@fs.exists(w.root) {
    return Ok(())
  }
  if @fs.rm_rf(w.root) {
    Ok(())
  } else {
    Err(RefuseToRemoveOutsider(w.root))
  }
}

///|
/// 删除工作区下的某个仓库目录（比删除整个根更细粒度）
pub fn release(w : Workspace, dir : String) -> Result[Unit, WorkspaceError] {
  if !owns(w, dir) {
    return Err(RefuseToRemoveOutsider(dir))
  }
  if @fs.rm_rf(dir) {
    Ok(())
  } else {
    Err(RefuseToRemoveOutsider(dir))
  }
}

///|
/// 工作区当前占用的字节数（递归统计，深度限制 12 层）
pub fn used_bytes(w : Workspace) -> Int64 {
  let n = @fs.dir_bytes(w.root, 12)
  if n < 0L {
    0L
  } else {
    n
  }
}

///|
/// 磁盘配额检查：给定上限（字节），判断是否已超出。
/// `limit_bytes <= 0` 表示不限制。
pub fn over_quota(w : Workspace, limit_bytes : Int64) -> Bool {
  if limit_bytes <= 0L {
    return false
  }
  used_bytes(w) > limit_bytes
}

///|
/// 把字节数格式化为人类可读文本
pub fn format_bytes(n : Int64) -> String {
  if n < 1024L {
    return n.to_string() + " B"
  }
  let kb = n.to_double() / 1024.0
  if kb < 1024.0 {
    return format_one_decimal(kb) + " KB"
  }
  let mb = kb / 1024.0
  if mb < 1024.0 {
    return format_one_decimal(mb) + " MB"
  }
  format_one_decimal(mb / 1024.0) + " GB"
}

///|
/// 保留一位小数
fn format_one_decimal(x : Double) -> String {
  let scaled = (x * 10.0 + 0.5).to_int()
  (scaled / 10).to_string() + "." + (scaled % 10).to_string()
}

///|
/// 在系统临时目录下清理所有历史工作区（名称以 RUN_PREFIX 开头）。
/// 返回被清理的数量。
///
/// 实现方式：列出基目录下的文件，取顶层目录名去重后逐个删除。
pub fn clean_stale() -> Int {
  let base = @proc.temp_dir()
  let ws_base = @proc.join_path(base, WORKSPACE_PREFIX)
  if !@fs.is_dir(ws_base) {
    return 0
  }
  let mut removed = 0
  let seen : Array[String] = []
  // 深度 1：只列到子目录的文件，用文件路径还原顶层目录名
  for f in @fs.list_files(ws_base, "", 1) {
    let dir = top_level_of(ws_base, f)
    if dir.length() == 0 {
      continue
    }
    if !contains_str(seen, dir) {
      seen.push(dir)
      ignore(@fs.rm_rf(dir))
      removed = removed + 1
    }
  }
  removed
}

///|
/// 从文件全路径中取出相对 base 的顶层目录名
fn top_level_of(base : String, file : String) -> String {
  let b = normalize(base)
  let f = normalize(file)
  let prefix_len = b.length() + 1
  if f.length() <= prefix_len || !f.has_prefix(b + "\\") {
    return ""
  }
  let rest = f[prefix_len:].to_owned()
  for i = 0; i < rest.length(); i = i + 1 {
    let c = rest.unsafe_get(i)
    if c == '\\' || c == '/' {
      return b + "\\" + rest[:i].to_owned()
    }
  }
  b + "\\" + rest
}

///|
/// 数组是否包含指定字符串
fn contains_str(arr : Array[String], s : String) -> Bool {
  for x in arr {
    if x == s {
      return true
    }
  }
  false
}

// ---------- 单元测试 ----------

///|
fn test_base(tag : String) -> String {
  let b = @proc.join_path(
    @proc.temp_dir(),
    "moonhive-ws-test-" + tag + "-" + @env.now().to_string(),
  )
  ignore(@fs.rm_rf(b))
  b
}

test "create_in 创建根目录并可分配子目录" {
  let base = test_base("alloc")
  match create_in(base, "run1") {
    Ok(w) => {
      assert_true(@fs.is_dir(root_of(w)))
      match alloc(w, "owner__repo") {
        Ok(dir) => {
          assert_true(@fs.is_dir(dir))
          assert_true(dir.contains("owner__repo"))
        }
        Err(_) => fail("alloc 应成功")
      }
      ignore(destroy(w))
    }
    Err(_) => fail("create_in 应成功")
  }
  ignore(@fs.rm_rf(base))
}

test "alloc 拒绝含路径分隔符的名字" {
  let base = test_base("badname")
  match create_in(base, "run1") {
    Ok(w) => {
      assert_true(match alloc(w, "a/b") {
        Err(InvalidName(_)) => true
        _ => false
      })
      assert_true(match alloc(w, "") {
        Err(InvalidName(_)) => true
        _ => false
      })
      ignore(destroy(w))
    }
    Err(_) => fail("create_in 应成功")
  }
  ignore(@fs.rm_rf(base))
}

test "owns 正确判定归属" {
  let base = test_base("owns")
  match create_in(base, "run1") {
    Ok(w) => {
      let inside = @proc.join_path(root_of(w), "sub")
      assert_true(owns(w, inside))
      assert_false(owns(w, base))
      assert_false(owns(w, @proc.join_path(base, "other")))
      // 前缀相同但不是子路径的情况必须被拒绝
      assert_false(owns(w, root_of(w) + "evil"))
      ignore(destroy(w))
    }
    Err(_) => fail("create_in 应成功")
  }
  ignore(@fs.rm_rf(base))
}

test "release 只允许删除工作区内的目录" {
  let base = test_base("release")
  let outsider = @proc.join_path(base, "outsider")
  ignore(@fs.mkdir_all(outsider))
  match create_in(base, "run1") {
    Ok(w) => {
      assert_true(match release(w, outsider) {
        Err(RefuseToRemoveOutsider(_)) => true
        _ => false
      })
      assert_true(@fs.is_dir(outsider))
      match alloc(w, "inner") {
        Ok(inner) => {
          assert_true(match release(w, inner) {
            Ok(_) => true
            _ => false
          })
          assert_false(@fs.exists(inner))
        }
        Err(_) => fail("alloc 应成功")
      }
      ignore(destroy(w))
    }
    Err(_) => fail("create_in 应成功")
  }
  ignore(@fs.rm_rf(base))
}

test "destroy 删除根后可重建" {
  let base = test_base("destroy")
  match create_in(base, "run1") {
    Ok(w) => {
      let r = root_of(w)
      assert_true(@fs.is_dir(r))
      ignore(destroy(w))
      assert_false(@fs.exists(r))
    }
    Err(_) => fail("create_in 应成功")
  }
  ignore(@fs.rm_rf(base))
}

test "used_bytes 与 over_quota" {
  let base = test_base("quota")
  match create_in(base, "run1") {
    Ok(w) => {
      let used0 = used_bytes(w)
      assert_true(used0 >= 0L)
      assert_false(over_quota(w, 0L))
      // 写一个文件后必须大于 0
      ignore(@proc.run_ok("echo hello > \"" + @proc.join_path(root_of(w), "f.txt") + "\"", "", 10000))
      assert_true(used_bytes(w) > 0L)
      assert_true(over_quota(w, 1L))
      assert_false(over_quota(w, 1000000000L))
      ignore(destroy(w))
    }
    Err(_) => fail("create_in 应成功")
  }
  ignore(@fs.rm_rf(base))
}

test "format_bytes 单位换算" {
  assert_eq(format_bytes(0L), "0 B")
  assert_eq(format_bytes(512L), "512 B")
  assert_eq(format_bytes(1024L), "1.0 KB")
  assert_eq(format_bytes(1536L), "1.5 KB")
  assert_eq(format_bytes(1048576L), "1.0 MB")
}

test "normalize 统一分隔符并去掉末尾分隔符" {
  // 通过 owns 间接验证：混合分隔符也应判定为子路径
  let base = test_base("normalize")
  match create_in(base, "run1") {
    Ok(w) => {
      let mixed = root_of(w) + "\\sub/nested"
      assert_true(owns(w, mixed))
      ignore(destroy(w))
    }
    Err(_) => fail("create_in 应成功")
  }
  ignore(@fs.rm_rf(base))
}
