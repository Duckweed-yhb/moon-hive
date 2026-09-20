///|
/// report/site — 公开静态站生成
///
/// 为什么需要它：一份只有作者能跑出来的报告，说服力有限。
/// 静态站把结论变成**任何人都能点开看的页面**——这是"可复现性"最直观的证明。
///
/// 设计约束：
///   1. **零依赖**：单个 HTML 文件，内联 CSS，不用 JavaScript 框架。
///      这样它能被直接托管在 GitHub Pages 上，也能离线打开。
///   2. **可复现信息置顶**：工具链版本、目标后端、生成时间必须出现在首屏——
///      脱离环境的"能不能用"是没有意义的结论。
///   3. **纯计算**：只依赖 report/model，渲染函数只吃数据出字符串，可离线单测。

///|
/// HTML 转义。
/// 诊断证据里会出现 `<`、`>`、`&`（编译器输出、泛型符号），
/// 不转义会破坏页面结构，也会造成注入风险。
pub fn escape_html(s : String) -> String {
  let b = StringBuilder()
  for c in s {
    if c == '&' {
      b.write_string("&amp;")
    } else if c == '<' {
      b.write_string("&lt;")
    } else if c == '>' {
      b.write_string("&gt;")
    } else if c == '"' {
      b.write_string("&quot;")
    } else if c == '\'' {
      b.write_string("&#39;")
    } else {
      b.write_char(c)
    }
  }
  b.to_string()
}

///|
/// 内联样式表。
/// 刻意保持精简：这个页面的职责是**传达结论**，不是展示设计。
pub fn stylesheet() -> String {
  "body{font-family:system-ui,-apple-system,'Segoe UI',sans-serif;max-width:960px;margin:0 auto;padding:24px;line-height:1.6;color:#1a1a1a;background:#fff}\n" +
  "h1{font-size:1.6rem;margin:0 0 4px}\n" +
  "h2{font-size:1.15rem;margin:28px 0 10px;border-bottom:1px solid #e5e5e5;padding-bottom:6px}\n" +
  ".sub{color:#666;font-size:.9rem;margin-bottom:20px}\n" +
  ".env{background:#f7f7f8;border:1px solid #e5e5e5;border-radius:6px;padding:12px 16px;margin:16px 0;font-size:.9rem}\n" +
  ".env div{margin:2px 0}\n" +
  ".env code{background:#fff;padding:1px 6px;border-radius:3px;border:1px solid #e5e5e5}\n" +
  ".stats{display:flex;flex-wrap:wrap;gap:12px;margin:16px 0}\n" +
  ".stat{border:1px solid #e5e5e5;border-radius:6px;padding:10px 16px;min-width:96px}\n" +
  ".stat .n{font-size:1.4rem;font-weight:600}\n" +
  ".stat .l{font-size:.8rem;color:#666}\n" +
  "table{border-collapse:collapse;width:100%;font-size:.9rem}\n" +
  "th,td{text-align:left;padding:8px 10px;border-bottom:1px solid #eee;vertical-align:top}\n" +
  "th{background:#fafafa;font-weight:600}\n" +
  "code{font-family:ui-monospace,SFMono-Regular,Consolas,monospace;font-size:.85em}\n" +
  ".ev{color:#666;font-size:.85em;word-break:break-all}\n" +
  ".ok{color:#1a7f37}.warn{color:#9a6700}.bad{color:#cf222e}\n" +
  "footer{margin-top:32px;padding-top:12px;border-top:1px solid #e5e5e5;color:#666;font-size:.85rem}\n"
}

///|
/// 结论对应的 CSS 类
fn class_of(label : String) -> String {
  if label == "Verified" {
    "ok"
  } else if label == "TestFailing" || label == "ToolchainMismatch" || label == "MissingDependency" {
    "warn"
  } else {
    "bad"
  }
}

///|
/// 渲染统计卡片
fn render_stats(m : @model.ReportModel) -> String {
  let b = StringBuilder()
  b.write_string("<div class=\"stats\">\n")
  b.write_string(stat_card(m.rows.length().to_string(), "验证总数"))
  b.write_string(stat_card(@model.count_of(m, "Verified").to_string(), "可直接使用"))
  b.write_string(stat_card(@model.format_ratio(m), "可用率"))
  b.write_string(stat_card(@model.total_source_lines(m).to_string(), "源码总行数"))
  b.write_string("</div>\n")
  b.to_string()
}

///|
fn stat_card(n : String, label : String) -> String {
  "  <div class=\"stat\"><div class=\"n\">" +
  escape_html(n) +
  "</div><div class=\"l\">" +
  escape_html(label) +
  "</div></div>\n"
}

///|
/// 渲染结论分布表
fn render_breakdown(m : @model.ReportModel) -> String {
  let b = StringBuilder()
  b.write_string("<table>\n<thead><tr><th>结论</th><th>数量</th><th>含义</th></tr></thead>\n<tbody>\n")
  let mut any = false
  for l in @model.labels() {
    let n = @model.count_of(m, l)
    if n > 0 {
      any = true
      b.write_string(
        "<tr><td class=\"" +
        class_of(l) +
        "\"><code>" +
        escape_html(l) +
        "</code></td><td>" +
        n.to_string() +
        "</td><td>" +
        escape_html(@model.explain_of(l)) +
        "</td></tr>\n",
      )
    }
  }
  if !any {
    b.write_string("<tr><td colspan=\"3\">（无数据）</td></tr>\n")
  }
  b.write_string("</tbody>\n</table>\n")
  b.to_string()
}

///|
/// 渲染逐条明细表
fn render_rows(m : @model.ReportModel) -> String {
  let b = StringBuilder()
  b.write_string(
    "<table>\n<thead><tr><th>项目</th><th>结论</th><th>规模</th><th>耗时</th><th>证据</th></tr></thead>\n<tbody>\n",
  )
  if m.rows.length() == 0 {
    b.write_string("<tr><td colspan=\"5\">（无数据）</td></tr>\n")
  }
  for r in m.rows {
    b.write_string("<tr>")
    b.write_string("<td><code>" + escape_html(r.slug) + "</code></td>")
    b.write_string(
      "<td class=\"" +
      class_of(r.diagnosis) +
      "\">" +
      @model.mark_of(r.diagnosis) +
      " <code>" +
      escape_html(r.diagnosis) +
      "</code></td>",
    )
    if r.fetched {
      b.write_string(
        "<td>" +
        r.mbt_files.to_string() +
        " 文件 / " +
        r.source_lines.to_string() +
        " 行</td>",
      )
      b.write_string(
        "<td>check " +
        @time.format_ms(r.check_ms) +
        (if r.test_ms > 0UL {
          " / test " + @time.format_ms(r.test_ms)
        } else {
          ""
        }) +
        "</td>",
      )
    } else {
      b.write_string("<td>—</td><td>—</td>")
    }
    let ev = r.evidence
    if ev.length() > 0 {
      b.write_string("<td class=\"ev\">" + escape_html(ev) + "</td>")
    } else {
      b.write_string("<td>—</td>")
    }
    b.write_string("</tr>\n")
  }
  b.write_string("</tbody>\n</table>\n")
  b.to_string()
}

///|
/// 渲染完整页面
pub fn render(m : @model.ReportModel) -> String {
  let b = StringBuilder()
  b.write_string("<!DOCTYPE html>\n<html lang=\"zh-CN\">\n<head>\n")
  b.write_string("<meta charset=\"utf-8\">\n")
  b.write_string("<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">\n")
  b.write_string("<title>MoonHive 生态验证报告</title>\n")
  b.write_string("<style>\n" + stylesheet() + "</style>\n")
  b.write_string("</head>\n<body>\n")
  b.write_string("<h1>MoonHive 生态验证报告</h1>\n")
  b.write_string(
    "<div class=\"sub\">用真实 MoonBit 工具链逐个验证：能不能编译、测试过不过、失败属于哪一类。</div>\n",
  )

  // 可复现信息置顶
  b.write_string("<div class=\"env\">\n")
  b.write_string("  <div><strong>验证环境</strong>（结论只在此环境下成立）</div>\n")
  b.write_string("  <div>MoonBit 工具链：<code>" + escape_html(m.toolchain) + "</code></div>\n")
  b.write_string("  <div>目标后端：<code>" + escape_html(m.target) + "</code></div>\n")
  b.write_string("  <div>生成时间戳（毫秒）：<code>" + m.generated_at.to_string() + "</code></div>\n")
  b.write_string("</div>\n")

  b.write_string(render_stats(m))
  b.write_string("<h2>结论分布</h2>\n")
  b.write_string(render_breakdown(m))
  b.write_string("<h2>逐个结果</h2>\n")
  b.write_string(render_rows(m))

  b.write_string("<footer>\n")
  b.write_string(
    "由 <code>moonhive survey</code> 生成 · 源码：<a href=\"https://github.com/Duckweed-yhb/moon-hive\">Duckweed-yhb/moon-hive</a> · MIT\n",
  )
  b.write_string("</footer>\n")
  b.write_string("</body>\n</html>\n")
  b.to_string()
}

// ---------- 单元测试 ----------

///|
fn r(slug : String, diag : String) -> @model.ResultRow {
  {
    slug,
    diagnosis: diag,
    explain: @model.explain_of(diag),
    evidence: "",
    fetched: true,
    mbt_files: 2,
    source_lines: 30,
    test_files: 1,
    repo_bytes: 200L,
    check_ms: 12UL,
    test_ms: 0UL,
  }
}

///|
fn m(rows : Array[@model.ResultRow]) -> @model.ReportModel {
  { generated_at: 99UL, target: "native", toolchain: "moon 0.1.x", rows }
}

test "escape_html 处理五个危险字符" {
  assert_eq(escape_html("a&b"), "a&amp;b")
  assert_eq(escape_html("a<b"), "a&lt;b")
  assert_eq(escape_html("a>b"), "a&gt;b")
  assert_eq(escape_html("a\"b"), "a&quot;b")
  assert_eq(escape_html("a'b"), "a&#39;b")
  assert_eq(escape_html("plain"), "plain")
}

test "render 是完整 HTML 文档" {
  let h = render(m([r("a/b", "Verified")]))
  assert_true(h.has_prefix("<!DOCTYPE html>"))
  assert_true(h.contains("<meta charset=\"utf-8\">"))
  assert_true(h.contains("</html>"))
}

test "render 把验证环境放在页面前部（可复现性）" {
  let h = render(m([r("a/b", "Verified")]))
  assert_true(h.contains("moon 0.1.x"))
  assert_true(h.contains("native"))
  assert_true(h.contains("99"))
  // 环境信息必须出现在明细表之前
  let env_pos = h.find("验证环境")
  let rows_pos = h.find("逐个结果")
  match (env_pos, rows_pos) {
    (Some(e), Some(rp)) => assert_true(e < rp)
    _ => fail("页面应同时包含环境信息与明细")
  }
}

test "render 统计卡片数值正确" {
  let h = render(m([r("a", "Verified"), r("b", "NoManifest")]))
  assert_true(h.contains("验证总数"))
  assert_true(h.contains("可直接使用"))
  assert_true(h.contains("可用率"))
  assert_true(h.contains("50.0%"))
}

test "render 结论分布只列非零项并带语义类名" {
  let h = render(m([r("a", "Verified"), r("b", "DoesNotCompile")]))
  assert_true(h.contains("<code>Verified</code>"))
  assert_true(h.contains("<code>DoesNotCompile</code>"))
  assert_false(h.contains("<code>TimedOut</code>"))
  assert_true(h.contains("class=\"ok\""))
  assert_true(h.contains("class=\"bad\""))
}

test "render 转义项目名与证据，不破坏页面结构" {
  let row = {
    ..r("evil<script>", "DoesNotCompile"),
    evidence: "a & b <tag>",
  }
  let h = render(m([row]))
  assert_false(h.contains("<script>"))
  assert_true(h.contains("&lt;script&gt;"))
  assert_true(h.contains("a &amp; b &lt;tag&gt;"))
}

test "render 标注不可用结论的语义" {
  let h = render(m([r("a", "ToolchainMismatch")]))
  assert_true(h.contains("class=\"warn\""))
  assert_true(h.contains("不是包的问题"))
}

test "render 未获取到代码时不显示规模与耗时" {
  let row = {
    ..r("a/b", "FetchFailed"),
    fetched: false,
  }
  let h = render(m([row]))
  assert_true(h.contains("<td>—</td>"))
  // 未获取时不应出现"文件 /"这种规模描述
  assert_false(h.contains(" 文件 / "))
}

test "render 空报告仍生成合法页面" {
  let h = render(m([]))
  assert_true(h.contains("（无数据）"))
  assert_true(h.contains("0.0%"))
  assert_true(h.contains("</html>"))
}

test "render 内联样式且不含外部资源引用（可离线打开）" {
  let h = render(m([r("a", "Verified")]))
  assert_true(h.contains("<style>"))
  assert_false(h.contains("<link rel=\"stylesheet\""))
  assert_false(h.contains("<script"))
}

test "render 包含数据来源与许可信息" {
  let h = render(m([r("a", "Verified")]))
  assert_true(h.contains("github.com/Duckweed-yhb/moon-hive"))
  assert_true(h.contains("MIT"))
}
