///|
/// verify/check — 工具链驱动
///
/// 把"取仓库 → 预检 → 跑工具链 → 分类"串成一条流程。
/// 判定逻辑全部委托给 `verify/diagnose`，本模块只负责执行与编排。
///
/// 安全边界（重要）：
///   - 只调用 MoonBit 官方工具链的 `check` 与 `test`
///   - 不用 `build`：它会在目标平台编译 C stub（若仓库带了 stub，
///     编译过程可能执行未受控的构建逻辑）
///   - 检出含 C stub 的仓库时标记为 Unsafe，只做静态分析不执行

///|
/// 单个候选包的验证结果
pub(all) struct RevResult {
  /// 仓库标识 owner/repo
  slug : String
  /// 最终结论
  diagnosis : @diagnose.Diagnosis
  /// moon check 的耗时（毫秒）
  check_ms : UInt64
  /// moon test 的耗时（毫秒）；未执行时为 0
  test_ms : UInt64
  /// 仓库体积（字节）
  repo_bytes : Int64
  /// .mbt 文件数量
  mbt_files : Int
  /// 源码行数
  source_lines : Int
  /// 测试文件数量（文件名含 test）
  test_files : Int
  /// 克隆是否成功
  fetched : Bool
}

///|
/// 验证过程的错误（发生于分类之前）
pub suberror CheckError {
  /// 工作区操作失败
  WorkspaceFailed(String)
}

///|
/// 判定为"需要谨慎执行"的构建配置标记。
/// 命中任一即认为仓库带有自定义构建步骤，出于安全只做静态分析。
fn unsafe_markers() -> Array[String] {
  ["native-stub", "cc-link-flags", "link-flags", "pre-build", "post-build"]
}

///|
/// 扫描 moon.pkg 文件，判断是否含自定义构建配置
fn detect_unsafe(dir : String) -> Bool {
  for pkg in @fs.list_files(dir, ".pkg", 6) {
    let content = @fs.read_text(pkg)
    if content.length() == 0 {
      continue
    }
    let lower = content.to_lower()
    for m in unsafe_markers() {
      if lower.contains(m) {
        return true
      }
    }
  }
  // 仓库自带 C 源文件：编译它就需要本地工具链，一律视为需谨慎
  !@fs.list_files(dir, ".c", 6).is_empty()
}

///|
/// 从 moon.pkg / CI 配置里尽力提取声明的目标后端。
/// 只做保守识别：识别不到就返回空数组（表示"未声明"），
/// 绝不猜测——错误的声明会直接导致错误的结论。
fn detect_declared_targets(dir : String) -> Array[String] {
  let found : Array[String] = []
  let candidates = ["wasm", "wasm-gc", "js", "native", "llvm"]
  // 只看构建与包配置文件，避免把 README 里的描述当成声明
  let files : Array[String] = [@proc.join_path(dir, "moon.mod")]
  for ext in [".pkg", ".json", ".yml", ".yaml"] {
    for f in @fs.list_files(dir, ext, 4) {
      files.push(f)
    }
  }
  for f in files {
    let content = @fs.read_text(f)
    if content.length() == 0 {
      continue
    }
    let lower = content.to_lower()
    for t in candidates {
      if lower.contains("target") && lower.contains(t) && !contains_str(found, t) {
        found.push(t)
      }
    }
  }
  found
}

///|
fn contains_str(arr : Array[String], s : String) -> Bool {
  for x in arr {
    if x == s {
      return true
    }
  }
  false
}

///|
/// 统计仓库的规模指标（纯静态，不执行任何仓库代码）
fn measure_repo(dir : String) -> (Int, Int, Int, Int64) {
  let mbt = @fs.list_files(dir, ".mbt", 8)
  let mut lines = 0
  let mut tests = 0
  for f in mbt {
    let content = @fs.read_text(f)
    for _ in content.split("\n") {
      lines = lines + 1
    }
    if f.to_lower().contains("test") {
      tests = tests + 1
    }
  }
  (mbt.length(), lines, tests, @fs.dir_bytes(dir, 10))
}

///|
/// 把进程输出转成分类器需要的形状
fn to_outcome(out : @proc.Output) -> @diagnose.CommandOutcome {
  { exit_code: out.exit_code, stdout: out.stdout, stderr: out.stderr }
}

///|
/// 把进程层错误转成可读文本。
/// 不能笼统写成"无法启动进程"——那会把 spawn 失败、内存不足、
/// 空命令等原因混成一句，报告里就失去了诊断价值。
/// 带上 OS 错误码，便于区分"权限不足"与"资源耗尽"这类原因。
fn proc_error_text(e : @proc.ProcError) -> String {
  let os = @proc.last_os_error()
  let suffix = if os != 0 {
    "（系统错误码 " + os.to_string() + "）"
  } else {
    ""
  }
  match e {
    EmptyCommand => "命令为空"
    SpawnFailed => "无法创建子进程（命令不可执行或系统资源不足）" + suffix
    OutOfMemory => "内存分配失败"
    StderrCaptureFailed(code) => "无法捕获 stderr（错误码 " + code.to_string() + "）"
  }
}

///|
/// 验证一个候选仓库。
///
/// `target`：目标后端，默认 "native"
/// `timeout_ms`：单条工具链命令的超时
/// `with_test`：check 通过后是否继续跑测试
pub fn verify_candidate(
  c : @gitsource.Candidate,
  w : @workspace.Workspace,
  backend : @gitsource.GitBackend,
  target : String,
  timeout_ms : Int,
  with_test : Bool,
) -> Result[RevResult, CheckError] {
  let dir_name = @gitsource.to_dir_name(c.slug)
  let dir = match @workspace.alloc(w, dir_name) {
    Ok(d) => d
    Err(_) => return Err(WorkspaceFailed("无法分配工作区子目录: " + dir_name))
  }

  // 1. 取仓库：本地目录直接复制进工作区；远端仓库走 git 克隆
  if @gitsource.is_local(c) {
    if !@fs.copy_tree(c.local_path, dir) {
      return Ok(
        empty_result(c.slug, @diagnose.FetchFailed("无法复制本地目录: " + c.local_path)),
      )
    }
  } else {
    match @gitsource.clone_repo(c, dir, 1, backend) {
      Err(@gitsource.RemoteUnreachable(m)) =>
        return Ok(empty_result(c.slug, @diagnose.FetchFailed(m)))
      Err(_) => return Ok(empty_result(c.slug, @diagnose.FetchFailed("无法访问远端")))
      Ok(_) => ()
    }
  }

  // 2. 静态预检 + 规模测量（不执行任何仓库代码）
  let has_manifest = @gitsource.is_moonbit_module(dir)
  let (mbt_count, lines, test_count, bytes) = measure_repo(dir)
  let risky = detect_unsafe(dir)
  let (target_label, declared) = (target, detect_declared_targets(dir))

  // 3. 不满足前提或存在风险时，直接给出结论，不执行工具链
  if !has_manifest || risky {
    let diag = if !has_manifest {
      @diagnose.NoManifest
    } else {
      @diagnose.Unsafe
    }
    return Ok({
      slug: c.slug,
      diagnosis: diag,
      check_ms: 0UL,
      test_ms: 0UL,
      repo_bytes: bytes,
      mbt_files: mbt_count,
      source_lines: lines,
      test_files: test_count,
      fetched: true,
    })
  }

  // 4. 跑 moon check
  let check_cmd = "moon check --target " + target_label
  let (check_out, check_ms) = match @proc.run(check_cmd, dir, timeout_ms) {
    Ok(o) => (to_outcome(o), o.elapsed_ms)
    Err(e) => (
      { exit_code: -1, stdout: "", stderr: proc_error_text(e) },
      0UL,
    )
  }
  let mut timed_out = check_ms > timeout_ms.to_uint64()

  // 5. check 通过且允许时，跑 moon test
  let mut test_outcome : @diagnose.CommandOutcome? = None
  let mut test_ms = 0UL
  if check_out.exit_code == 0 && with_test {
    match @proc.run("moon test --target " + target_label, dir, timeout_ms) {
      Ok(o) => {
        test_outcome = Some(to_outcome(o))
        test_ms = o.elapsed_ms
        if test_ms > timeout_ms.to_uint64() {
          timed_out = true
        }
      }
      Err(_) => ()
    }
  }

  // 6. 交给分类器下结论
  let outcome : @diagnose.CheckOutcome = {
    has_manifest,
    risky,
    timed_out,
    check: check_out,
    test_outcome,
    declared_targets: declared,
    target: target_label,
  }
  Ok({
    slug: c.slug,
    diagnosis: @diagnose.classify(outcome),
    check_ms,
    test_ms,
    repo_bytes: bytes,
    mbt_files: mbt_count,
    source_lines: lines,
    test_files: test_count,
    fetched: true,
  })
}

///|
/// 从注册表（mooncakes）验证一个包的**发布版本**。
///
/// 与 git clone 的区别：clone 拿到的是仓库默认分支的最新代码（可能是
/// 未发布的开发中代码），而 `moon fetch` 拿到的是用户 `moon add` 时
/// 真正会装到的注册表发布版本——因此"发布版本能不能用"更贴合实际问题。
/// （实测佐证：moonbit-community/yaml 的 GitHub 默认分支没有 moon.mod，
///  判为 NoManifest；而注册表发布版 0.0.6 check 全绿、69 测试通过。）
///
/// 实现：在工作区子目录里执行 `moon fetch <slug>`，包会落到
/// `<dir>/.repos/<owner>/<repo>/<version>`，定位含 moon.mod 的目录后，
/// 与 git 路径共用 check/test/classify 全流程。
pub fn verify_registry_candidate(
  slug : String,
  w : @workspace.Workspace,
  target : String,
  timeout_ms : Int,
  with_test : Bool,
) -> Result[RevResult, CheckError] {
  let dir_name = @gitsource.to_dir_name(slug)
  let dir = match @workspace.alloc(w, dir_name) {
    Ok(d) => d
    Err(_) => return Err(WorkspaceFailed("无法分配工作区子目录: " + dir_name))
  }

  // 1. 用 moon fetch 拉取注册表发布版本
  match @proc.run("moon fetch " + slug, dir, timeout_ms) {
    Err(e) => return Ok(empty_result(slug, @diagnose.FetchFailed(proc_error_text(e))))
    Ok(o) =>
      if o.exit_code != 0 {
        let ev = @diagnose.first_error_line(o.stdout + "\n" + o.stderr)
        return Ok(
          empty_result(
            slug,
            @diagnose.FetchFailed(if ev.length() > 0 { ev } else { "moon fetch 失败" }),
          ),
        )
      }
  }

  // 2. 定位下载的包目录（.repos/... 下含 moon.mod 的目录）
  let pkg = match locate_registry_pkg(dir) {
    Some(p) => p
    None => return Ok(empty_result(slug, @diagnose.NoManifest))
  }

  // 3. 静态预检 + 规模测量（与 git 路径共用同一套判定）
  let has_manifest = @gitsource.is_moonbit_module(pkg)
  let (mbt_count, lines, test_count, bytes) = measure_repo(pkg)
  let risky = detect_unsafe(pkg)
  let (target_label, declared) = (target, detect_declared_targets(pkg))

  // 不满足前提或存在风险时，直接给出结论，不执行工具链
  if !has_manifest || risky {
    let diag = if !has_manifest {
      @diagnose.NoManifest
    } else {
      @diagnose.Unsafe
    }
    return Ok({
      slug,
      diagnosis: diag,
      check_ms: 0UL,
      test_ms: 0UL,
      repo_bytes: bytes,
      mbt_files: mbt_count,
      source_lines: lines,
      test_files: test_count,
      fetched: true,
    })
  }

  // 4. 跑 moon check（cwd 为包目录）
  let check_cmd = "moon check --target " + target_label
  let (check_out, check_ms) = match @proc.run(check_cmd, pkg, timeout_ms) {
    Ok(o) => (to_outcome(o), o.elapsed_ms)
    Err(e) => (
      { exit_code: -1, stdout: "", stderr: proc_error_text(e) },
      0UL,
    )
  }
  let mut timed_out = check_ms > timeout_ms.to_uint64()

  // 5. check 通过且允许时，跑 moon test
  let mut test_outcome : @diagnose.CommandOutcome? = None
  let mut test_ms = 0UL
  if check_out.exit_code == 0 && with_test {
    match @proc.run("moon test --target " + target_label, pkg, timeout_ms) {
      Ok(o) => {
        test_outcome = Some(to_outcome(o))
        test_ms = o.elapsed_ms
        if test_ms > timeout_ms.to_uint64() {
          timed_out = true
        }
      }
      Err(_) => ()
    }
  }

  // 6. 交给分类器下结论
  let outcome : @diagnose.CheckOutcome = {
    has_manifest,
    risky,
    timed_out,
    check: check_out,
    test_outcome,
    declared_targets: declared,
    target: target_label,
  }
  Ok({
    slug,
    diagnosis: @diagnose.classify(outcome),
    check_ms,
    test_ms,
    repo_bytes: bytes,
    mbt_files: mbt_count,
    source_lines: lines,
    test_files: test_count,
    fetched: true,
  })
}

///|
/// 在 `.repos` 下载目录中定位含 moon.mod 的包目录。
///
/// 不能用 `list_files(dir, "moon.mod", ...)`：平台层按"扩展名"过滤，
/// 要求文件名长度严格大于扩展名，恰好叫 moon.mod 的文件匹配不到。
/// 因此列出全部文件后手动过滤后缀。
fn locate_registry_pkg(dir : String) -> String? {
  for f in @fs.list_files(dir, "", 6) {
    if f.has_suffix("moon.mod") {
      return Some(parent_dir(f))
    }
  }
  None
}

///|
/// 取文件所在目录（字符串层面，不触碰文件系统）
fn parent_dir(f : String) -> String {
  let mut last = -1
  for i = 0; i < f.length(); i = i + 1 {
    let c = f.unsafe_get(i)
    if c == '/' || c == '\\' {
      last = i
    }
  }
  if last < 0 {
    f
  } else {
    f[:last].to_owned()
  }
}

///|
/// 获取失败时的占位结果
fn empty_result(slug : String, d : @diagnose.Diagnosis) -> RevResult {
  {
    slug,
    diagnosis: d,
    check_ms: 0UL,
    test_ms: 0UL,
    repo_bytes: 0L,
    mbt_files: 0,
    source_lines: 0,
    test_files: 0,
    fetched: false,
  }
}

///|
/// 验证完成后释放该候选仓库占用的磁盘空间
pub fn release_candidate(w : @workspace.Workspace, slug : String) -> Unit {
  let dir = @proc.join_path(@workspace.root_of(w), @gitsource.to_dir_name(slug))
  ignore(@workspace.release(w, dir))
}
