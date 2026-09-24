///|
/// report/model — 报告的数据模型（纯计算，可离线单测）
///
/// 为什么单独抽出模型，而不是直接渲染 verify/check 的 RevResult：
///   - 报告是要**归档与被外部消费**的产物，它的字段一旦发布就不能随意改
///   - 验证层的内部结构（例如 RevResult）应能自由演进，不受报告格式牵制
///   - 中间多一层显式映射，也让"报告里到底有什么"这件事一目了然
///
/// 本模块不依赖任何平台层，因此 JSON 与 HTML 渲染都能只靠字符串断言测试。

///|
/// 报告中的单条结果（扁平、自包含）
pub(all) struct ResultRow {
  /// 仓库标识
  slug : String
  /// 结论标签，例如 Verified
  diagnosis : String
  /// 人类可读解释
  explain : String
  /// 结论证据（首条诊断信息）
  evidence : String
  /// 是否成功获取到代码
  fetched : Bool
  /// .mbt 文件数
  mbt_files : Int
  /// 源码行数
  source_lines : Int
  /// 测试文件数
  test_files : Int
  /// 仓库体积（字节）
  repo_bytes : Int64
  /// check 耗时（毫秒）
  check_ms : UInt64
  /// test 耗时（毫秒）
  test_ms : UInt64
}

///|
/// 完整报告模型
pub(all) struct ReportModel {
  /// 生成时间（毫秒时间戳）
  generated_at : UInt64
  /// 目标后端
  target : String
  /// 验证所用 MoonBit 工具链版本
  toolchain : String
  /// 逐个结果
  rows : Array[ResultRow]
}

///|
/// 报告涉及的结论标签全集（顺序固定，供渲染与计数使用）
pub fn labels() -> Array[String] {
  [
    "Verified",
    "TestFailing",
    "DoesNotCompile",
    "ToolchainMismatch",
    "MissingDependency",
    "NoManifest",
    "TimedOut",
    "Unsafe",
    "FetchFailed",
  ]
}

///|
/// 计数
pub fn count_of(m : ReportModel, label : String) -> Int {
  let mut n = 0
  for r in m.rows {
    if r.diagnosis == label {
      n = n + 1
    }
  }
  n
}

///|
/// 可用率（0.0 ~ 1.0）。无数据时返回 0.0。
///
/// 定义：`Verified` 数量 / 总数量。这是报告里最直观的一个数字，
/// 但**必须与逐条明细一起看**——把 ToolchainMismatch 算进"不可用"
/// 会冤枉健康的库，因此可用率只作为概览，不替代明细。
pub fn usable_ratio(m : ReportModel) -> Double {
  if m.rows.length() == 0 {
    return 0.0
  }
  count_of(m, "Verified").to_double() / m.rows.length().to_double()
}

///|
/// 把可用率格式化为百分比字符串（一位小数）
pub fn format_ratio(m : ReportModel) -> String {
  let scaled = (usable_ratio(m) * 1000.0 + 0.5).to_int()
  (scaled / 10).to_string() + "." + (scaled % 10).to_string() + "%"
}

///|
/// 总计源码行数
pub fn total_source_lines(m : ReportModel) -> Int {
  let mut n = 0
  for r in m.rows {
    n = n + r.source_lines
  }
  n
}

///|
/// 总计体积
pub fn total_bytes(m : ReportModel) -> Int64 {
  let mut n = 0L
  for r in m.rows {
    n = n + r.repo_bytes
  }
  n
}

///|
/// 结论的短解释（与 verify/diagnose 的措辞保持一致，避免两处漂移）
pub fn explain_of(label : String) -> String {
  if label == "Verified" {
    "编译与测试通过，可以直接使用"
  } else if label == "TestFailing" {
    "能编译，但测试未通过——代码在演进中，谨慎使用"
  } else if label == "DoesNotCompile" {
    "编译器报错，当前工具链上不可用"
  } else if label == "ToolchainMismatch" {
    "版本/API 不兼容——不是包的问题，是工具链版本差异"
  } else if label == "MissingDependency" {
    "依赖解析失败，不是自包含的模块"
  } else if label == "NoManifest" {
    "没有 moon.mod，不是 MoonBit 模块"
  } else if label == "TimedOut" {
    "超出时间预算"
  } else if label == "Unsafe" {
    "含 FFI 或自定义构建脚本，出于安全只做静态分析"
  } else if label == "FetchFailed" {
    "获取仓库失败"
  } else {
    "未知结论"
  }
}

///|
/// 结论对应的符号（终端与网页共用）
pub fn mark_of(label : String) -> String {
  if label == "Verified" {
    "✅"
  } else if label == "TestFailing" {
    "⚠️"
  } else if label == "DoesNotCompile" {
    "❌"
  } else if label == "ToolchainMismatch" {
    "🚫"
  } else if label == "MissingDependency" {
    "📦"
  } else if label == "NoManifest" {
    "📄"
  } else if label == "TimedOut" {
    "⏱️"
  } else if label == "Unsafe" {
    "🔒"
  } else if label == "FetchFailed" {
    "🌐"
  } else {
    "❔"
  }
}

///|
/// 结论是否可用（只有 Verified 算可用）
pub fn is_usable_label(label : String) -> Bool {
  label == "Verified"
}

///|
/// 某个结论标签是否属于已知集合——渲染前用它做一次防御性校验，
/// 避免未来新增结论时静默漏掉。
pub fn is_known_label(label : String) -> Bool {
  for l in labels() {
    if l == label {
      return true
    }
  }
  false
}

// ---------- 单元测试 ----------

///|
fn row(slug : String, diag : String) -> ResultRow {
  {
    slug,
    diagnosis: diag,
    explain: explain_of(diag),
    evidence: "",
    fetched: true,
    mbt_files: 0,
    source_lines: 0,
    test_files: 0,
    repo_bytes: 0L,
    check_ms: 0UL,
    test_ms: 0UL,
  }
}

///|
fn model(rows : Array[ResultRow]) -> ReportModel {
  { generated_at: 1700000000000UL, target: "native", toolchain: "moon test", rows }
}

test "labels 顺序稳定且无重复" {
  let ls = labels()
  assert_eq(ls.length(), 9)
  for i = 0; i < ls.length(); i = i + 1 {
    for j = i + 1; j < ls.length(); j = j + 1 {
      assert_true(ls[i] != ls[j])
    }
  }
  assert_eq(ls[0], "Verified")
}

test "count_of 统计正确" {
  let m = model([row("a", "Verified"), row("b", "Verified"), row("c", "NoManifest")])
  assert_eq(count_of(m, "Verified"), 2)
  assert_eq(count_of(m, "NoManifest"), 1)
  assert_eq(count_of(m, "TimedOut"), 0)
}

test "usable_ratio 与 format_ratio" {
  let m = model([row("a", "Verified"), row("b", "Verified"), row("c", "NoManifest"), row("d", "Unsafe")])
  assert_eq(usable_ratio(m), 0.5)
  assert_eq(format_ratio(m), "50.0%")
}

test "usable_ratio 对空报告返回 0 而不崩溃" {
  let m = model([])
  assert_eq(usable_ratio(m), 0.0)
  assert_eq(format_ratio(m), "0.0%")
}

test "format_ratio 四舍五入到一位小数" {
  // 1/3 ≈ 33.3%
  let m = model([row("a", "Verified"), row("b", "NoManifest"), row("c", "Unsafe")])
  assert_eq(format_ratio(m), "33.3%")
  // 2/3 ≈ 66.7%
  let m2 = model([row("a", "Verified"), row("b", "Verified"), row("c", "Unsafe")])
  assert_eq(format_ratio(m2), "66.7%")
}

test "format_ratio 全通过为 100.0%" {
  let m = model([row("a", "Verified")])
  assert_eq(format_ratio(m), "100.0%")
}

test "explain_of 对每个已知标签都有非空解释" {
  for l in labels() {
    let e = explain_of(l)
    assert_true(e.length() > 0)
    assert_true(e != "未知结论")
  }
  assert_eq(explain_of("NoSuchLabel"), "未知结论")
}

test "mark_of 对每个已知标签都有符号" {
  for l in labels() {
    assert_true(mark_of(l) != "❔")
  }
  assert_eq(mark_of("NoSuchLabel"), "❔")
}

test "is_usable_label 只认可 Verified" {
  assert_true(is_usable_label("Verified"))
  assert_false(is_usable_label("TestFailing"))
  assert_false(is_usable_label("ToolchainMismatch"))
}

test "is_known_label 校验标签集合" {
  assert_true(is_known_label("Verified"))
  assert_true(is_known_label("FetchFailed"))
  assert_false(is_known_label("Whatever"))
  assert_false(is_known_label(""))
}

test "总计函数" {
  let a = {
    ..row("a", "Verified"),
    source_lines: 100,
    repo_bytes: 1000L,
  }
  let b = {
    ..row("b", "NoManifest"),
    source_lines: 25,
    repo_bytes: 500L,
  }
  let m = model([a, b])
  assert_eq(total_source_lines(m), 125)
  assert_eq(total_bytes(m), 1500L)
}

test "总计函数对空报告返回 0" {
  let m = model([])
  assert_eq(total_source_lines(m), 0)
  assert_eq(total_bytes(m), 0L)
}
