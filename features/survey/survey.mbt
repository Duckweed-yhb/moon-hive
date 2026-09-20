///|
/// features/survey — 批量普查与报告生成
///
/// 这是 MoonHive 的主命令：对一批候选仓库逐个验证，汇总成一份可阅读、
/// 可归档、可对比的报告。
///
/// 与 `inspect` 的区别：inspect 面向"我现在就想看这一个包"，
/// survey 面向"这批包整体健康状况如何"，因此额外产出报告文件。

///|
/// 一次普查的完整结果
pub(all) struct SurveyReport {
  /// 生成时间（毫秒时间戳）
  generated_at : UInt64
  /// 本次使用的目标后端
  target : String
  /// 验证时使用的 MoonBit 工具链版本
  toolchain : String
  /// 逐个包的结果
  results : Array[@check.RevResult]
}

///|
/// 普查选项
pub(all) struct SurveyOptions {
  target : String
  timeout_ms : Int
  with_test : Bool
  /// 报告输出路径；空串表示不写文件
  out_path : String
}

///|
/// 默认选项
pub fn default_options() -> SurveyOptions {
  { target: "native", timeout_ms: 120000, with_test: true, out_path: "" }
}

///|
/// 全部结论标签（顺序固定，供汇总与报告使用）
fn all_labels() -> Array[String] {
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
/// 统计某结论出现的次数
pub fn count_of(results : Array[@check.RevResult], label : String) -> Int {
  let mut n = 0
  for r in results {
    if @diagnose.label(r.diagnosis) == label {
      n = n + 1
    }
  }
  n
}

///|
/// 取得当前 MoonBit 工具链版本（用于报告头，保证结论可复现）
fn detect_toolchain() -> String {
  match @proc.run("moon version", "", 20000) {
    Ok(o) =>
      if o.exit_code == 0 {
        @diagnose.first_error_line(o.stdout)
      } else {
        "未知"
      }
    Err(_) => "未知"
  }
}

///|
/// 执行普查。`candidates` 为已解析的候选仓库列表。
///
/// 返回 (报告, 退出码)。退出码：0 至少一个通过；1 全部未通过。
pub fn run(
  candidates : Array[@gitsource.Candidate],
  opt : SurveyOptions,
) -> (SurveyReport, Int) {
  let backend = @gitsource.detect_backend()
  let toolchain = detect_toolchain()
  let results : Array[@check.RevResult] = []

  println("MoonHive 生态验证引擎")
  println("git TLS 后端: " + @gitsource.backend_description(backend))
  println("工具链: " + toolchain)
  println("目标后端: " + opt.target)
  println("待验证: " + candidates.length().to_string() + " 个")
  println("")

  let ws = match @workspace.create() {
    Ok(w) => w
    Err(_) => {
      println("无法创建工作区（临时目录不可写？）")
      return (
        { generated_at: @env.now(), target: opt.target, toolchain, results: [] },
        10,
      )
    }
  }

  let mut idx = 0
  for c in candidates {
    idx = idx + 1
    let tag = "[" + idx.to_string() + "/" + candidates.length().to_string() + "] "
    match
      @check.verify_candidate(c, ws, backend, opt.target, opt.timeout_ms, opt.with_test) {
      Ok(r) => {
        println(
          tag +
          @diagnose.mark(r.diagnosis) +
          " " +
          pad_right(r.slug, 34) +
          " " +
          pad_right(@diagnose.label(r.diagnosis), 18) +
          @time.format_ms(r.check_ms),
        )
        results.push(r)
        @check.release_candidate(ws, c.slug)
      }
      Err(_) => println(tag + "验证过程出错: " + c.slug)
    }
  }

  println("")
  let report = {
    generated_at: @env.now(),
    target: opt.target,
    toolchain,
    results,
  }
  println(summarize_line(report))

  // 写报告文件（若指定）
  if opt.out_path.length() > 0 {
    let md = render_markdown(report)
    if write_text(opt.out_path, md) {
      println("报告已写入: " + opt.out_path)
    } else {
      println("报告写入失败: " + opt.out_path)
    }
  }

  ignore(@workspace.destroy(ws))
  let usable = count_of(results, "Verified")
  (report, if usable > 0 { 0 } else { 1 })
}

///|
/// 右填充到指定宽度（用于对齐的表格输出，按字符数近似）
pub fn pad_right(s : String, width : Int) -> String {
  if s.length() >= width {
    return s
  }
  let b = StringBuilder()
  b.write_string(s)
  for _ in 0..<(width - s.length()) {
    b.write_string(" ")
  }
  b.to_string()
}

///|
/// 单行汇总
pub fn summarize_line(r : SurveyReport) -> String {
  let b = StringBuilder()
  b.write_string("结论: ")
  let mut first = true
  for l in all_labels() {
    let n = count_of(r.results, l)
    if n > 0 {
      if !first {
        b.write_string(" · ")
      }
      b.write_string(l + " " + n.to_string())
      first = false
    }
  }
  b.to_string()
}

///|
/// 写文本文件。直接走 FFI，避免任何 shell 转义问题。
fn write_text(path : String, content : String) -> Bool {
  @fs.write_text(path, content)
}

///|
/// 渲染 Markdown 报告。
///
/// 报告头必须记录**验证环境**（工具链版本、目标后端、时间），
/// 否则"这个包能不能用"这个结论无法复现，也就无法被信任。
pub fn render_markdown(r : SurveyReport) -> String {
  let b = StringBuilder()
  b.write_string("# MoonHive 生态验证报告\n\n")
  b.write_string("> 本报告由 MoonHive 用真实 MoonBit 工具链逐个验证生成。\n")
  b.write_string("> 结论只对下列验证环境下成立。\n\n")
  b.write_string("| 项 | 值 |\n|---|---|\n")
  b.write_string("| 生成时间戳(ms) | " + r.generated_at.to_string() + " |\n")
  b.write_string("| 目标后端 | " + r.target + " |\n")
  b.write_string("| 工具链 | " + r.toolchain + " |\n")
  b.write_string("| 验证数量 | " + r.results.length().to_string() + " |\n\n")

  // 汇总
  b.write_string("## 结论汇总\n\n")
  b.write_string("| 结论 | 数量 | 含义 |\n|---|---|---|\n")
  for l in all_labels() {
    let n = count_of(r.results, l)
    if n > 0 {
      b.write_string(
        "| `" + l + "` | " + n.to_string() + " | " + explain_of(l) + " |\n",
      )
    }
  }
  b.write_string("\n")

  // 明细
  b.write_string("## 逐个结果\n\n")
  for x in r.results {
    b.write_string("### " + @diagnose.mark(x.diagnosis) + " " + x.slug + "\n\n")
    b.write_string("- **结论**: `" + @diagnose.label(x.diagnosis) + "`\n")
    b.write_string("- **说明**: " + @diagnose.explain(x.diagnosis) + "\n")
    let ev = @diagnose.evidence(x.diagnosis)
    if ev.length() > 0 {
      b.write_string("- **证据**: `" + ev.replace_all(old="|", new="\\|") + "`\n")
    }
    if x.fetched {
      b.write_string(
        "- **规模**: " +
        x.mbt_files.to_string() +
        " 个 .mbt / " +
        x.source_lines.to_string() +
        " 行 / " +
        x.test_files.to_string() +
        " 个测试文件 / " +
        @workspace.format_bytes(x.repo_bytes) +
        "\n",
      )
    }
    if x.check_ms > 0UL || x.test_ms > 0UL {
      b.write_string(
        "- **耗时**: check " +
        @time.format_ms(x.check_ms) +
        " / test " +
        @time.format_ms(x.test_ms) +
        "\n",
      )
    }
    b.write_string("\n")
  }
  b.to_string()
}

///|
/// 取某结论标签的解释文本
fn explain_of(label : String) -> String {
  if label == "Verified" {
    "编译与测试通过，可以直接使用"
  } else if label == "TestFailing" {
    "能编译，但测试未通过"
  } else if label == "DoesNotCompile" {
    "编译器报错，当前工具链上不可用"
  } else if label == "ToolchainMismatch" {
    "版本/API 不兼容——不是包的问题"
  } else if label == "MissingDependency" {
    "依赖解析失败，不是自包含的"
  } else if label == "NoManifest" {
    "没有 moon.mod，不是 MoonBit 模块"
  } else if label == "TimedOut" {
    "超出时间预算"
  } else if label == "Unsafe" {
    "含 FFI 或自定义构建脚本，只做静态分析"
  } else if label == "FetchFailed" {
    "获取仓库失败"
  } else {
    ""
  }
}
