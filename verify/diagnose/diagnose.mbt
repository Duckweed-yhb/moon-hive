///|
/// verify/diagnose — 把工具链输出归类为可行动的结论
///
/// 这是本项目的核心资产：**分不清"这个包坏了"和"我的工具链版本不对"，
/// 工具就会撒谎**。
///
/// 实测背景：`moonbitlang/x`（生态里最活跃的库之一）在本机工具链上
/// `moon check` 报 14 个错误，其中包括
///     Type Bytes has no method exact_view.
/// 这类"方法/类型不存在"的错误通常源于工具链版本差异，而非包本身损坏。
/// 因此必须与真正的类型错误区分开。
///
/// 本文件是**纯计算**：只吃字符串，不跑进程，因此可以完全离线单测。

///|
/// 验证结论
pub(all) enum Diagnosis {
  /// 编译与测试全绿
  Verified
  /// 能编译，但测试未通过
  TestFailing(String)
  /// 编译器报错（真正的代码问题）
  DoesNotCompile(String)
  /// 诊断指向工具链版本/API 不兼容——不是包的错
  ToolchainMismatch(String)
  /// 依赖解析失败
  MissingDependency(String)
  /// 不是 MoonBit 模块（没有清单文件）
  NoManifest
  /// 超出时间预算
  TimedOut
  /// 含 FFI / 自定义构建脚本，只做静态分析不执行
  Unsafe
  /// 克隆或准备工作区失败
  FetchFailed(String)
} derive(Eq, Debug)

///|
/// 一次命令的结果（诊断分类的输入）
pub(all) struct CommandOutcome {
  exit_code : Int
  stdout : String
  stderr : String
}

///|
/// 结论的短标签（用于表格与 JSON）
pub fn label(d : Diagnosis) -> String {
  match d {
    Verified => "Verified"
    TestFailing(_) => "TestFailing"
    DoesNotCompile(_) => "DoesNotCompile"
    ToolchainMismatch(_) => "ToolchainMismatch"
    MissingDependency(_) => "MissingDependency"
    NoManifest => "NoManifest"
    TimedOut => "TimedOut"
    Unsafe => "Unsafe"
    FetchFailed(_) => "FetchFailed"
  }
}

///|
/// 结论的符号（用于终端展示）
pub fn mark(d : Diagnosis) -> String {
  match d {
    Verified => "✅"
    TestFailing(_) => "⚠️ "
    DoesNotCompile(_) => "❌"
    ToolchainMismatch(_) => "🚫"
    MissingDependency(_) => "📦"
    NoManifest => "📄"
    TimedOut => "⏱️ "
    Unsafe => "🔒"
    FetchFailed(_) => "🌐"
  }
}

///|
/// 结论的简要解释（面向用户）
pub fn explain(d : Diagnosis) -> String {
  match d {
    Verified => "编译与测试通过，可以直接使用"
    TestFailing(_) => "能编译，但测试未通过——代码在演进中，谨慎使用"
    DoesNotCompile(_) => "编译器报错，当前工具链上不可用"
    ToolchainMismatch(_) => "版本/API 不兼容——不是包的问题，是工具链版本差异"
    MissingDependency(_) => "依赖解析失败，不是自包含的模块"
    NoManifest => "没有 moon.mod，不是 MoonBit 模块"
    TimedOut => "超出时间预算"
    Unsafe => "含 FFI 或自定义构建脚本，出于安全只做静态分析"
    FetchFailed(_) => "获取仓库失败"
  }
}

///|
/// 结论附带的证据（首条诊断信息）
pub fn evidence(d : Diagnosis) -> String {
  match d {
    Verified => ""
    TestFailing(m) => m
    DoesNotCompile(m) => m
    ToolchainMismatch(m) => m
    MissingDependency(m) => m
    NoManifest => ""
    TimedOut => ""
    Unsafe => ""
    FetchFailed(m) => m
  }
}

///|
/// 是否为"可用"的结论
pub fn is_usable(d : Diagnosis) -> Bool {
  match d {
    Verified => true
    _ => false
  }
}

// ---------- 诊断特征库 ----------

///|
/// 工具链不兼容的特征。
///
/// 这些措辞的共同点是：**引用了当前工具链里不存在的 API 或类型**，
/// 而不是代码本身写错了。误判的代价是双向的：
///   - 把工具链问题判成包的问题 → 冤枉了生态里健康的库
///   - 把包的问题判成工具链问题 → 掩盖了真实的坏包
/// 因此特征串必须具体，宁可保守（判为 DoesNotCompile）也不滥用。
fn toolchain_mismatch_markers() -> Array[String] {
  [
    "has no method",
    "no method named",
    "is not defined in",
    "unknown method",
    "unresolved identifier",
    "unknown type",
    "type not found",
    "unsupported target",
    "no such field",
    "not found in type",
    "unexpected token",   // 语法层面的漂移同样常见于版本差异
  ]
}

///|
/// 依赖缺失的特征
fn missing_dependency_markers() -> Array[String] {
  [
    "failed to resolve",
    "cannot find module",
    "cannot find package",
    "no such package",
    "failed to download",
    "dependency",
    "registry",
  ]
}

///|
/// 测试失败的特征
fn test_failure_markers() -> Array[String] {
  [
    "tests failed",
    "test failed",
    "failed: ",
    "assertion failed",
    "expect failed",
    "panicked",
  ]
}

///|
/// 在文本中查找第一个命中的特征串
fn first_marker(text : String, markers : Array[String]) -> String? {
  let lower = text.to_lower()
  for m in markers {
    if lower.contains(m) {
      return Some(m)
    }
  }
  None
}

///|
/// 从诊断文本中提取最有价值的那一条错误描述，作为结论的证据。
///
/// 为什么不能只取"第一行含 error"：MoonBit 的诊断输出形如
///     Error: [4015]
///       ╭─[ file.mbt:12:3 ]
///       │
///     12 │   Type Bytes has no method exact_view.
///       ╰──────
/// 若按行号顺序取，会先命中 `Error: [4015]` 这种**只有错误码、没有内容**
/// 的行，证据就变成了无意义的 "Error: [4015]"。
///
/// 三轮筛选（实测校准过，顺序很重要）：
///   1. 带 error 关键词、且不是纯错误码的行 —— 最理想
///   2. **像诊断内容的行**（较长、含空白或冒号，排除代码行与装饰行）
///      —— 编译器常把具体错误内容放在错误码的下一行，而那一行本身
///      不含 "error" 字样（例如 `Type Bytes has no method exact_view.`）
///   3. 兜底：第一行非装饰性文本
///
/// 第 2 轮不能省：否则会退化成返回 "Error: [4015]" 这种无用证据。
pub fn first_error_line(text : String) -> String {
  // 第一轮：带 error 关键词的实质错误行
  for line in text.split("\n") {
    let cleaned = strip_box_chars(line.to_owned().trim().to_owned())
    if cleaned.length() == 0 || is_decoration(cleaned) {
      continue
    }
    let lower = cleaned.to_lower()
    if (lower.contains("error") || lower.contains("失败") || lower.contains("错误")) &&
      !is_bare_error_code(cleaned) {
      return truncate(cleaned, 160)
    }
  }
  // 第二轮：看起来像"诊断内容"的行
  for line in text.split("\n") {
    let cleaned = strip_box_chars(line.to_owned().trim().to_owned())
    if looks_like_diagnostic(cleaned) {
      return truncate(cleaned, 160)
    }
  }
  // 第三轮：兜底取第一行非装饰性文本
  for line in text.split("\n") {
    let cleaned = strip_box_chars(line.to_owned().trim().to_owned())
    if cleaned.length() > 0 && !is_decoration(cleaned) {
      return truncate(cleaned, 160)
    }
  }
  ""
}

///|
/// 判断一行是否"像诊断内容"。
///
/// 诊断内容的特征：有足够长度、包含空格或冒号（是句子而非标识符）、
/// 且不是代码片段（代码行通常以行号开头，例如 `12 │ let x = 1`）。
fn looks_like_diagnostic(s : String) -> Bool {
  if s.length() < 12 || is_decoration(s) || is_bare_error_code(s) {
    return false
  }
  // 排除代码行：以数字开头、后面紧跟空白
  let first = s.unsafe_get(0)
  if first >= '0' && first <= '9' {
    return false
  }
  s.contains_char(' ') || s.contains_char(':')
}

///|
/// 判断一行是否只是错误码/长度声明这类"没有诊断内容"的行。
/// 例如 `Error: [4015]`、`Failed with 0 warnings, 14 errors.`
///
/// 实现上刻意避开 substring 与前后缀的组合判断，改用逐字符扫描：
/// 逻辑更直白，也不会因为空格/大小写等细节悄悄失效。
fn is_bare_error_code(s : String) -> Bool {
  let lower = s.to_lower()
  // 形态一："error: [4015]" —— 去掉 "error:" 与空白后，恰好是 "[" + 数字 + "]"
  if lower.has_prefix("error:") {
    let n = s.length()
    let mut i = 6
    while i < n && (s.unsafe_get(i) == ' ' || s.unsafe_get(i) == '\t') {
      i = i + 1
    }
    if i < n && s.unsafe_get(i) == '[' {
      let mut j = i + 1
      let mut digits = 0
      while j < n && s.unsafe_get(j) >= '0' && s.unsafe_get(j) <= '9' {
        digits = digits + 1
        j = j + 1
      }
      if digits > 0 && j < n && s.unsafe_get(j) == ']' && j == n - 1 {
        return true
      }
    }
  }
  // 形态二："failed with N warnings, M errors."
  lower.contains("warnings,") && lower.contains("errors")
}

///|
/// 判断一行是否只是框线装饰
fn is_decoration(s : String) -> Bool {
  if s.length() == 0 {
    return true
  }
  let lower = s.to_lower()
  lower == "failed with 0 warnings, 0 errors." || lower.has_prefix("error: failed to")
}

///|
/// 去掉编译器输出里的框线与箭头装饰字符
fn strip_box_chars(s : String) -> String {
  let b = StringBuilder()
  for c in s {
    if c == '│' || c == '╭' || c == '╰' || c == '─' || c == '┬' || c == '╯' || c == '╮' {
      b.write_char(' ')
    } else {
      b.write_char(c)
    }
  }
  b.to_string().trim().to_owned()
}

///|
/// 截断过长文本
fn truncate(s : String, n : Int) -> String {
  if s.length() <= n {
    s
  } else {
    s[:n].to_owned() + "…"
  }
}

// ---------- 分类 ----------

///|
/// 检查结果汇总（分类的完整输入）
pub(all) struct CheckOutcome {
  /// 目录里是否存在 MoonBit 模块清单
  has_manifest : Bool
  /// 是否含 FFI / 构建脚本（安全起见不执行）
  risky : Bool
  /// 是否超出时间预算
  timed_out : Bool
  /// moon check 的结果
  check : CommandOutcome
  /// moon test 的结果；未执行时为 None
  test_outcome : CommandOutcome?
  /// 仓库声明的目标后端列表（空表示未声明）
  declared_targets : Array[String]
  /// 本次实际使用的目标后端
  target : String
}

///|
/// 根据检查结果给出结论。
///
/// 判定顺序（重要）：先排除环境与前提问题，再区分工具链与代码问题，
/// 最后才看测试结果。顺序错了会产生误导性的结论。
pub fn classify(o : CheckOutcome) -> Diagnosis {
  // 1. 前提：必须是 MoonBit 模块
  if !o.has_manifest {
    return NoManifest
  }
  // 2. 安全：含 FFI / 构建脚本时不执行
  if o.risky {
    return Unsafe
  }
  // 3. 超时
  if o.timed_out {
    return TimedOut
  }
  // 4. 仓库声明了目标后端，但不含本次使用的后端 → 环境不匹配
  if o.declared_targets.length() > 0 && !has_target(o.declared_targets, o.target) {
    return ToolchainMismatch(
      "仓库声明的目标后端为 [" +
      join_strings(o.declared_targets, ", ") +
      "]，不含本次使用的 " +
      o.target,
    )
  }
  // 5. check 失败：区分工具链问题 / 依赖问题 / 真正的编译错误
  if o.check.exit_code != 0 {
    let text = o.check.stdout + "\n" + o.check.stderr
    let evidence = first_error_line(text)
    // 5a. 依赖解析失败优先判定——它常常同时包含 "unknown" 之类的字样
    if first_marker(text, missing_dependency_markers()) is Some(_) &&
      first_marker(text, ["failed to resolve", "cannot find module", "cannot find package", "no such package"]) is
      Some(_) {
      return MissingDependency(evidence)
    }
    // 5b. 工具链不兼容
    if first_marker(text, toolchain_mismatch_markers()) is Some(m) {
      return ToolchainMismatch(evidence + "（特征: " + m + "）")
    }
    return DoesNotCompile(evidence)
  }
  // 6. check 通过：看测试
  match o.test_outcome {
    None => Verified
    Some(t) =>
      if t.exit_code != 0 {
        let text = t.stdout + "\n" + t.stderr
        if first_marker(text, test_failure_markers()) is Some(_) {
          TestFailing(first_error_line(text))
        } else {
          TestFailing(first_error_line(text))
        }
      } else {
        Verified
      }
  }
}

///|
/// 目标后端列表是否包含指定后端
fn has_target(targets : Array[String], target : String) -> Bool {
  for t in targets {
    if t.to_lower() == target.to_lower() {
      return true
    }
  }
  false
}

///|
/// 用分隔符连接字符串数组（本模块内自足，不依赖 core 扩展）
fn join_strings(arr : Array[String], sep : String) -> String {
  let b = StringBuilder()
  let mut first = true
  for s in arr {
    if !first {
      b.write_string(sep)
    }
    b.write_string(s)
    first = false
  }
  b.to_string()
}

// ---------- 单元测试 ----------

///|
fn ok_out() -> CommandOutcome {
  { exit_code: 0, stdout: "", stderr: "" }
}

///|
fn fail_out(text : String) -> CommandOutcome {
  { exit_code: 1, stdout: "", stderr: text }
}

///|
fn base_outcome() -> CheckOutcome {
  {
    has_manifest: true,
    risky: false,
    timed_out: false,
    check: ok_out(),
    test_outcome: None,
    declared_targets: [],
    target: "native",
  }
}

test "classify: 无清单 → NoManifest" {
  let o = { ..base_outcome(), has_manifest: false }
  assert_eq(classify(o), NoManifest)
}

test "classify: 含 FFI → Unsafe（不执行）" {
  let o = { ..base_outcome(), risky: true }
  assert_eq(classify(o), Unsafe)
}

test "classify: 超时 → TimedOut" {
  let o = { ..base_outcome(), timed_out: true }
  assert_eq(classify(o), TimedOut)
}

test "classify: 全绿 → Verified" {
  assert_eq(classify(base_outcome()), Verified)
}

test "classify: 声明后端不含 native → ToolchainMismatch" {
  let o = { ..base_outcome(), declared_targets: ["wasm", "js"] }
  match classify(o) {
    ToolchainMismatch(m) => {
      assert_true(m.contains("native"))
      assert_true(m.contains("wasm"))
    }
    other => fail("应为 ToolchainMismatch，实际 " + label(other))
  }
}

test "classify: 声明后端包含 native → 不再因此判不匹配" {
  let o = { ..base_outcome(), declared_targets: ["wasm", "native"] }
  assert_eq(classify(o), Verified)
}

test "classify: 真实编译错误 → DoesNotCompile" {
  let o = {
    ..base_outcome(),
    check: fail_out("error: Type Int is not comparable with String\n  expected Int, got String"),
  }
  match classify(o) {
    DoesNotCompile(m) => assert_true(m.length() > 0)
    other => fail("应为 DoesNotCompile，实际 " + label(other))
  }
}

test "classify: has no method 特征 → ToolchainMismatch（对应 moonbitlang/x 实测）" {
  let text = "Error: [4015]\n  Type Bytes has no method exact_view."
  let o = { ..base_outcome(), check: fail_out(text) }
  match classify(o) {
    ToolchainMismatch(m) => {
      assert_true(m.contains("has no method"))
      assert_true(m.contains("exact_view"))
    }
    other => fail("应为 ToolchainMismatch，实际 " + label(other))
  }
}

test "classify: unresolved identifier 也归为工具链不兼容" {
  let o = { ..base_outcome(), check: fail_out("error: unresolved identifier @json.parse_ex") }
  match classify(o) {
    ToolchainMismatch(_) => ()
    other => fail("应为 ToolchainMismatch，实际 " + label(other))
  }
}

test "classify: 依赖解析失败优先于工具链判定" {
  let o = {
    ..base_outcome(),
    check: fail_out("failed to resolve package 'someone/unknown'\ncannot find module foo"),
  }
  match classify(o) {
    MissingDependency(_) => ()
    other => fail("应为 MissingDependency，实际 " + label(other))
  }
}

test "classify: check 通过但测试失败 → TestFailing" {
  let o = {
    ..base_outcome(),
    test_outcome: Some(fail_out("Total tests: 10, passed: 8, failed: 2.")),
  }
  match classify(o) {
    TestFailing(m) => assert_true(m.length() > 0)
    other => fail("应为 TestFailing，实际 " + label(other))
  }
}

test "classify: check 与 test 都通过 → Verified" {
  let o = { ..base_outcome(), test_outcome: Some(ok_out()) }
  assert_eq(classify(o), Verified)
}

test "first_error_line 提取并去掉框线装饰" {
  let text = "  ╭─[ file.mbt:12:3 ]\n  │\n 12 │ bad code\n  ╰─── Error: Type X has no method y."
  let line = first_error_line(text)
  assert_true(line.contains("Error"))
  assert_false(line.contains("│"))
}

test "first_error_line 对空文本返回空串" {
  assert_eq(first_error_line(""), "")
}

test "first_error_line 跳过纯错误码行，取有内容的诊断行" {
  // 真实形态：错误码在上一行，具体内容在下一行且不含 "error" 字样
  let text = "Error: [4015]\n  Type Bytes has no method exact_view."
  let line = first_error_line(text)
  assert_true(line.contains("exact_view"))
  assert_false(line.contains("[4015]"))
}

test "first_error_line 不把代码行当作诊断内容" {
  // 代码行以行号开头，应被排除，取真正的诊断文本
  let text = "Error: [4015]\n  12 │   let x = 1\n  Type Bytes has no method exact_view."
  let line = first_error_line(text)
  assert_true(line.contains("exact_view"))
}

test "first_error_line 优先返回带 error 关键词的实质行" {
  let text = "some noise here that is long\n  error: Type mismatch, expected Int got String"
  let line = first_error_line(text)
  assert_true(line.contains("Type mismatch"))
}

test "looks_like_diagnostic 排除装饰行与代码行" {
  assert_false(looks_like_diagnostic(""))
  assert_false(looks_like_diagnostic("Error: [4015]"))
  assert_false(looks_like_diagnostic("12   let x = 1"))
  assert_false(looks_like_diagnostic("short"))
  assert_true(looks_like_diagnostic("Type Bytes has no method exact_view."))
}

test "is_bare_error_code 只认纯错误码与长度声明" {
  assert_true(is_bare_error_code("Error: [4015]"))
  assert_true(is_bare_error_code("error: [E4015]") == false)
  assert_true(is_bare_error_code("Failed with 0 warnings, 14 errors."))
  assert_false(is_bare_error_code("Error: Type mismatch in expression"))
  assert_false(is_bare_error_code(""))
}

test "label / mark / explain / evidence 覆盖全部变体" {
  let all = [
    Verified,
    TestFailing("a"),
    DoesNotCompile("b"),
    ToolchainMismatch("c"),
    MissingDependency("d"),
    NoManifest,
    TimedOut,
    Unsafe,
    FetchFailed("e"),
  ]
  for d in all {
    assert_true(label(d).length() > 0)
    assert_true(mark(d).length() > 0)
    assert_true(explain(d).length() > 0)
  }
  assert_eq(evidence(Verified), "")
  assert_eq(evidence(TestFailing("x")), "x")
  assert_eq(evidence(FetchFailed("y")), "y")
}

test "is_usable 只对 Verified 为真" {
  assert_true(is_usable(Verified))
  assert_false(is_usable(TestFailing("a")))
  assert_false(is_usable(ToolchainMismatch("b")))
}

test "label 与 enum 名一致（报告与 JSON 依赖它稳定）" {
  assert_eq(label(ToolchainMismatch("x")), "ToolchainMismatch")
  assert_eq(label(MissingDependency("x")), "MissingDependency")
  assert_eq(label(NoManifest), "NoManifest")
}
