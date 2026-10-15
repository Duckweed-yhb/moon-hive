///|
/// features/survey — 批量普查与多格式报告生成
///
/// 这是 MoonHive 的主命令：对一批候选仓库逐个验证，汇总成可阅读、可归档、
/// 可被脚本消费的报告。
///
/// 与 `inspect` 的区别：inspect 面向"我现在就想看这一个包"，
/// survey 面向"这批包整体健康状况如何"，因此额外产出三种报告文件：
///   - Markdown：给人读、可贴进仓库
///   - JSON    ：给脚本读、可做趋势对比
///   - HTML    ：给任何人点开看（可托管为公开静态站）
///
/// 三种格式共用 `report/model` 的同一份数据模型，避免"三个渲染器三套字段"
/// 这种典型的漂移来源。

///|
/// 普查选项
pub(all) struct SurveyOptions {
  target : String
  timeout_ms : Int
  with_test : Bool
  /// Markdown 报告路径；空串表示不写
  md_path : String
  /// JSON 报告路径；空串表示不写
  json_path : String
  /// 静态站 HTML 路径；空串表示不写
  site_path : String
  /// 从注册表（mooncakes）验证发布版本，而非 git clone 默认分支
  registry : Bool
}

///|
/// 默认选项（不写任何文件）
pub fn default_options() -> SurveyOptions {
  {
    target: "native",
    timeout_ms: 120000,
    with_test: true,
    md_path: "",
    json_path: "",
    site_path: "",
    registry: false,
  }
}

// ---------- 数据模型转换 ----------

///|
/// 把验证结果转成报告模型的一行。
///
/// 这一层显式映射是刻意的：验证层的内部结构可以自由演进，
/// 报告格式却必须稳定——中间隔一层，两边就不会互相牵制。
pub fn to_model_row(r : @check.RevResult) -> @model.ResultRow {
  {
    slug: r.slug,
    diagnosis: @diagnose.label(r.diagnosis),
    explain: @diagnose.explain(r.diagnosis),
    evidence: @diagnose.evidence(r.diagnosis),
    fetched: r.fetched,
    mbt_files: r.mbt_files,
    source_lines: r.source_lines,
    test_files: r.test_files,
    repo_bytes: r.repo_bytes,
    check_ms: r.check_ms,
    test_ms: r.test_ms,
  }
}

///|
/// 由验证结果构造完整报告模型
pub fn build_model(
  results : Array[@check.RevResult],
  target : String,
  toolchain : String,
  generated_at : UInt64,
) -> @model.ReportModel {
  let rows : Array[@model.ResultRow] = []
  for r in results {
    rows.push(to_model_row(r))
  }
  { generated_at, target, toolchain, rows }
}

// ---------- 工具 ----------

///|
/// 取得当前 MoonBit 工具链版本（报告头必须记录，否则结论无法复现）
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
/// 右填充到指定宽度（终端表格对齐）
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
/// 单行汇总文本
pub fn summarize_line(m : @model.ReportModel) -> String {
  let b = StringBuilder()
  b.write_string("结论: ")
  let mut first = true
  for l in @model.labels() {
    let n = @model.count_of(m, l)
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

// ---------- 主流程 ----------

///|
/// 执行普查。返回 (报告模型, 退出码)。
/// 退出码：0 = 至少一个通过；1 = 全部未通过；10 = 环境错误。
pub fn run(
  candidates : Array[@gitsource.Candidate],
  opt : SurveyOptions,
) -> (@model.ReportModel, Int) {
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
      let empty = build_model(results, opt.target, toolchain, @env.now())
      return (empty, 10)
    }
  }

  let mut idx = 0
  for c in candidates {
    idx = idx + 1
    let tag = "[" + idx.to_string() + "/" + candidates.length().to_string() + "] "
    match
      (if opt.registry {
        @check.verify_registry_candidate(
          c.slug,
          ws,
          opt.target,
          opt.timeout_ms,
          opt.with_test,
        )
      } else {
        @check.verify_candidate(c, ws, backend, opt.target, opt.timeout_ms, opt.with_test)
      }) {
      Ok(r) => {
        println(
          tag +
          @model.mark_of(@diagnose.label(r.diagnosis)) +
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
  let report = build_model(results, opt.target, toolchain, @env.now())
  println(summarize_line(report))

  // 写出报告（按需）
  write_if_requested(opt.md_path, "Markdown", render_markdown(report))
  write_if_requested(opt.json_path, "JSON", @json.render(report))
  write_if_requested(opt.site_path, "静态站", @site.render(report))

  ignore(@workspace.destroy(ws))
  let usable = @model.count_of(report, "Verified")
  (report, if usable > 0 { 0 } else { 1 })
}

///|
/// 按需写文件并打印结果
fn write_if_requested(path : String, kind : String, content : String) -> Unit {
  if path.length() == 0 {
    return
  }
  if @fs.write_text(path, content) {
    println(kind + " 报告已写入: " + path)
  } else {
    println(kind + " 报告写入失败: " + path)
  }
}

// ---------- Markdown 渲染 ----------

///|
/// 渲染 Markdown 报告。
///
/// 报告头必须记录**验证环境**（工具链版本、目标后端、时间），
/// 否则"这个包能不能用"这个结论无法复现，也就无法被信任。
pub fn render_markdown(m : @model.ReportModel) -> String {
  let b = StringBuilder()
  b.write_string("# MoonHive 生态验证报告\n\n")
  b.write_string("> 本报告由 MoonHive 用真实 MoonBit 工具链逐个验证生成。\n")
  b.write_string("> 结论只对下列验证环境下成立。\n\n")
  b.write_string("| 项 | 值 |\n|---|---|\n")
  b.write_string("| 生成时间戳(ms) | " + m.generated_at.to_string() + " |\n")
  b.write_string("| 目标后端 | " + m.target + " |\n")
  b.write_string("| 工具链 | " + m.toolchain + " |\n")
  b.write_string("| 验证数量 | " + m.rows.length().to_string() + " |\n")
  b.write_string("| 可直接使用 | " + @model.count_of(m, "Verified").to_string() + " |\n")
  b.write_string("| 可用率 | " + @model.format_ratio(m) + " |\n\n")

  b.write_string("## 结论汇总\n\n")
  b.write_string("| 结论 | 数量 | 含义 |\n|---|---|---|\n")
  for l in @model.labels() {
    let n = @model.count_of(m, l)
    if n > 0 {
      b.write_string(
        "| `" + l + "` | " + n.to_string() + " | " + @model.explain_of(l) + " |\n",
      )
    }
  }
  b.write_string("\n")

  b.write_string("## 逐个结果\n\n")
  for r in m.rows {
    b.write_string("### " + @model.mark_of(r.diagnosis) + " " + r.slug + "\n\n")
    b.write_string("- **结论**: `" + r.diagnosis + "`\n")
    b.write_string("- **说明**: " + r.explain + "\n")
    if r.evidence.length() > 0 {
      b.write_string("- **证据**: `" + r.evidence.replace_all(old="|", new="\\|") + "`\n")
    }
    if r.fetched {
      b.write_string(
        "- **规模**: " +
        r.mbt_files.to_string() +
        " 个 .mbt / " +
        r.source_lines.to_string() +
        " 行 / " +
        r.test_files.to_string() +
        " 个测试文件 / " +
        @workspace.format_bytes(r.repo_bytes) +
        "\n",
      )
    }
    if r.check_ms > 0UL || r.test_ms > 0UL {
      b.write_string(
        "- **耗时**: check " +
        @time.format_ms(r.check_ms) +
        " / test " +
        @time.format_ms(r.test_ms) +
        "\n",
      )
    }
    b.write_string("\n")
  }
  b.to_string()
}

// ---------- 单元测试（纯渲染逻辑，不跑工具链） ----------

///|
fn sample_row(slug : String, diag : String) -> @model.ResultRow {
  {
    slug,
    diagnosis: diag,
    explain: @model.explain_of(diag),
    evidence: if diag == "DoesNotCompile" {
      "Type Bytes has no method exact_view."
    } else {
      ""
    },
    fetched: true,
    mbt_files: 3,
    source_lines: 120,
    test_files: 1,
    repo_bytes: 4096L,
    check_ms: 250UL,
    test_ms: 1500UL,
  }
}

///|
fn sample_model(rows : Array[@model.ResultRow]) -> @model.ReportModel {
  { generated_at: 1234UL, target: "native", toolchain: "moon 0.1.20260904", rows }
}

test "to_model_row 保留全部关键字段" {
  let rev : @check.RevResult = {
    slug: "a/b",
    diagnosis: @diagnose.ToolchainMismatch("x"),
    check_ms: 10UL,
    test_ms: 0UL,
    repo_bytes: 512L,
    mbt_files: 7,
    source_lines: 300,
    test_files: 2,
    fetched: true,
  }
  let row = to_model_row(rev)
  assert_eq(row.slug, "a/b")
  assert_eq(row.diagnosis, "ToolchainMismatch")
  assert_eq(row.mbt_files, 7)
  assert_eq(row.source_lines, 300)
  assert_eq(row.test_files, 2)
  assert_eq(row.repo_bytes, 512L)
  assert_eq(row.check_ms, 10UL)
  assert_true(row.fetched)
}

test "to_model_row 的 diagnosis 用标签而非原始构造" {
  let rev : @check.RevResult = {
    slug: "x",
    diagnosis: @diagnose.NoManifest,
    check_ms: 0UL,
    test_ms: 0UL,
    repo_bytes: 0L,
    mbt_files: 0,
    source_lines: 0,
    test_files: 0,
    fetched: false,
  }
  assert_eq(to_model_row(rev).diagnosis, "NoManifest")
}

test "build_model 逐行转换并保留环境信息" {
  let results : Array[@check.RevResult] = [
    {
      slug: "a",
      diagnosis: @diagnose.Verified,
      check_ms: 1UL,
      test_ms: 2UL,
      repo_bytes: 10L,
      mbt_files: 1,
      source_lines: 5,
      test_files: 0,
      fetched: true,
    },
    {
      slug: "b",
      diagnosis: @diagnose.Unsafe,
      check_ms: 0UL,
      test_ms: 0UL,
      repo_bytes: 20L,
      mbt_files: 0,
      source_lines: 0,
      test_files: 0,
      fetched: true,
    },
  ]
  let m = build_model(results, "native", "moon x", 777UL)
  assert_eq(m.rows.length(), 2)
  assert_eq(m.rows[0].slug, "a")
  assert_eq(m.rows[1].diagnosis, "Unsafe")
  assert_eq(m.target, "native")
  assert_eq(m.toolchain, "moon x")
  assert_eq(m.generated_at, 777UL)
}

test "summarize_line 只列非零结论并以分隔符连接" {
  let m = sample_model([
    sample_row("a", "Verified"),
    sample_row("b", "Verified"),
    sample_row("c", "NoManifest"),
  ])
  let s = summarize_line(m)
  assert_true(s.contains("Verified 2"))
  assert_true(s.contains("NoManifest 1"))
  assert_true(s.contains(" · "))
  assert_false(s.contains("TimedOut"))
}

test "pad_right 补齐到指定宽度且不截断" {
  assert_eq(pad_right("ab", 5), "ab   ")
  assert_eq(pad_right("abcdef", 3), "abcdef")
  assert_eq(pad_right("", 2), "  ")
}

test "render_markdown 报告头含验证环境" {
  let md = render_markdown(sample_model([sample_row("a/b", "Verified")]))
  assert_true(md.has_prefix("# MoonHive 生态验证报告"))
  assert_true(md.contains("moon 0.1.20260904"))
  assert_true(md.contains("| 目标后端 | native |"))
  assert_true(md.contains("| 生成时间戳(ms) | 1234 |"))
}

test "render_markdown 含可用率与数量" {
  let md = render_markdown(
    sample_model([sample_row("a", "Verified"), sample_row("b", "NoManifest")]),
  )
  assert_true(md.contains("| 可直接使用 | 1 |"))
  assert_true(md.contains("| 可用率 | 50.0% |"))
}

test "render_markdown 转义表格竖线，避免破坏表格" {
  let row = { ..sample_row("a", "DoesNotCompile"), evidence: "a|b" }
  let md = render_markdown(sample_model([row]))
  assert_true(md.contains("a\\|b"))
}

test "render_markdown 空报告仍结构完整" {
  let md = render_markdown(sample_model([]))
  assert_true(md.contains("| 验证数量 | 0 |"))
  assert_true(md.contains("| 可用率 | 0.0% |"))
  assert_true(md.contains("## 逐个结果"))
}

test "render_markdown 证据为空时不输出证据行" {
  let md = render_markdown(sample_model([sample_row("a", "Verified")]))
  assert_false(md.contains("- **证据**"))
}

test "default_options 不写任何报告文件" {
  let o = default_options()
  assert_eq(o.md_path, "")
  assert_eq(o.json_path, "")
  assert_eq(o.site_path, "")
  assert_eq(o.target, "native")
  assert_true(o.with_test)
}
