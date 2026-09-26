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
///   4. **一屏读懂结论**：可用率横幅、结论分布（含占比条）、按可用性排序的明细。

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
/// 职责：**让结论一眼可读**——颜色区分结论、占比条表达分布、窄屏不破版。
pub fn stylesheet() -> String {
  "body{font-family:system-ui,-apple-system,'Segoe UI',sans-serif;max-width:960px;margin:0 auto;padding:20px 20px 32px;line-height:1.6;color:#1a1a1a;background:#fff}\n" +
  "h1{font-size:1.7rem;margin:0 0 4px}\n" +
  ".sub{color:#666;font-size:.92rem;margin-bottom:16px}\n" +
  "nav{font-size:.85rem;color:#57606a;margin:0 0 16px}\n" +
  "nav a{color:#0969da;text-decoration:none;margin-right:12px}\n" +
  ".hero{display:flex;align-items:baseline;gap:14px;flex-wrap:wrap;background:linear-gradient(135deg,#f6f8fa,#eef1f4);border:1px solid #e5e5e5;border-radius:10px;padding:16px 20px;margin:14px 0 6px}\n" +
  ".hero .n{font-size:2.2rem;font-weight:700;color:#1a7f37;line-height:1}\n" +
  ".hero .t{font-size:1rem;color:#24292f}\n" +
  ".hero .s{flex-basis:100%;font-size:.85rem;color:#57606a}\n" +
  ".env{background:#f7f7f8;border:1px solid #e5e5e5;border-radius:8px;padding:12px 16px;margin:12px 0 6px;font-size:.9rem}\n" +
  ".env div{margin:2px 0}\n" +
  ".env code{background:#fff;padding:1px 6px;border-radius:3px;border:1px solid #e5e5e5}\n" +
  ".stats{display:flex;flex-wrap:wrap;gap:12px;margin:14px 0 4px}\n" +
  ".stat{flex:1 1 130px;min-width:0;border:1px solid #e5e5e5;border-radius:10px;padding:12px 16px;box-shadow:0 1px 2px rgba(0,0,0,.03)}\n" +
  ".stat .n{font-size:1.5rem;font-weight:600}\n" +
  ".stat .l{font-size:.8rem;color:#666}\n" +
  "h2{font-size:1.2rem;margin:30px 0 12px;border-bottom:1px solid #e5e5e5;padding-bottom:8px;scroll-margin-top:8px}\n" +
  "table{border-collapse:collapse;width:100%;font-size:.9rem}\n" +
  "th,td{text-align:left;padding:9px 10px;border-bottom:1px solid #eee;vertical-align:top}\n" +
  "th{background:#fafafa;font-weight:600}\n" +
  "code{font-family:ui-monospace,SFMono-Regular,Consolas,monospace;font-size:.85em}\n" +
  ".ev{color:#57606a;font-size:.83em;max-width:340px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;word-break:keep-all}\n" +
  ".bar{background:#eef1f4;border-radius:5px;height:8px;min-width:80px;overflow:hidden}\n" +
  ".fill{height:100%;border-radius:5px}\n" +
  ".tbl-wrap{overflow-x:auto}\n" +
  ".ok{color:#1a7f37}.warn{color:#9a6700}.bad{color:#cf222e}\n" +
  ".c-verified{color:#1a7f37}.c-testfailing{color:#9a6700}.c-toolchainmismatch{color:#9a6700}.c-missingdependency{color:#bc4c00}.c-doesnotcompile{color:#cf222e}.c-nomanifest{color:#bc4c00}.c-timedout{color:#57606a}.c-unsafe{color:#8250df}.c-fetchfailed{color:#57606a}\n" +
  ".fill-verified{background:#1a7f37}.fill-testfailing{background:#d4a72c}.fill-toolchainmismatch{background:#d4a72c}.fill-missingdependency{background:#bc4c00}.fill-doesnotcompile{background:#cf222e}.fill-nomanifest{background:#bc4c00}.fill-timedout{background:#8b949e}.fill-unsafe{background:#8250df}.fill-fetchfailed{background:#8b949e}\n" +
  "footer{margin-top:36px;padding-top:12px;border-top:1px solid #e5e5e5;color:#666;font-size:.85rem}\n" +
  "@media(max-width:600px){h1{font-size:1.4rem}.hero .n{font-size:1.8rem}th,td{padding:7px 6px;font-size:.82rem}.stat{flex-basis:calc(50% - 12px)}}\n"
}

///|
/// 结论对应的语义类（`ok`/`warn`/`bad` 三档 + 每结论专属色类，二者叠加）
fn class_of(label : String) -> String {
  let mut base = "bad"
  if label == "Verified" {
    base = "ok"
  } else if label == "TestFailing" || label == "ToolchainMismatch" || label == "MissingDependency" {
    base = "warn"
  }
  base + " c-" + lowercase(label)
}

///|
/// 结论对应的占比条填充类
fn fill_class(label : String) -> String {
  "fill-" + lowercase(label)
}

///|
/// ASCII 小写（结论标签均为 ASCII；MoonBit 标准库无 to_lowercase）
fn lowercase(s : String) -> String {
  let b = StringBuilder()
  for c in s {
    if c >= 'A' && c <= 'Z' {
      match (c.to_int() + 32).to_char() {
        Some(lc) => b.write_char(lc)
        None => b.write_char(c)
      }
    } else {
      b.write_char(c)
    }
  }
  b.to_string()
}

///|
/// 把小数格式化为一位百分比字符串（与 report/model 的 format_ratio 同口径）
fn fmt_pct(frac : Double) -> String {
  let scaled = (frac * 1000.0 + 0.5).to_int()
  (scaled / 10).to_string() + "." + (scaled % 10).to_string() + "%"
}

///|
/// 两位补零
fn pad2(n : Int) -> String {
  if n < 10 {
    "0" + n.to_string()
  } else {
    n.to_string()
  }
}

///|
/// 民用日期算法（Howard Hinnant）：天数 → (年, 月, 日)
fn civil_from_days(z : Int) -> (Int, Int, Int) {
  let z = z + 719468
  let era = (if z >= 0 { z } else { z - 146096 }) / 146097
  let doe = z - era * 146097
  let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  let y = yoe + era * 400
  let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
  let mp = (5 * doy + 2) / 153
  let d = doy - (153 * mp + 2) / 5 + 1
  let m = mp + (if mp < 10 { 3 } else { -9 })
  (y + (if m <= 2 { 1 } else { 0 }), m, d)
}

///|
/// 毫秒时间戳 → "YYYY-MM-DD HH:MM:SS"（UTC+8，本工具面向本地使用场景）
fn format_ts(ms : UInt64) -> String {
  let total = (ms / 1000UL).to_int() + 8 * 3600
  let days = total / 86400
  let secs = total % 86400
  let (y, m, d) = civil_from_days(days)
  let hh = secs / 3600
  let mm = (secs % 3600) / 60
  let ss = secs % 60
  pad2(y) + "-" + pad2(m) + "-" + pad2(d) + " " + pad2(hh) + ":" + pad2(mm) + ":" + pad2(ss)
}

///|
/// 明细排序优先级：可用的在前，越"不可用"越靠后
fn priority_of(label : String) -> Int {
  if label == "Verified" {
    0
  } else if label == "TestFailing" {
    1
  } else if label == "ToolchainMismatch" {
    2
  } else if label == "MissingDependency" {
    3
  } else if label == "DoesNotCompile" {
    4
  } else if label == "NoManifest" {
    5
  } else if label == "TimedOut" {
    6
  } else if label == "Unsafe" {
    7
  } else {
    8
  }
}

///|
/// 按优先级排序后的明细副本（不污染传入模型）
fn sorted_rows(rows : Array[@model.ResultRow]) -> Array[@model.ResultRow] {
  let out : Array[@model.ResultRow] = []
  for r in rows {
    out.push(r)
  }
  for i = 0; i < out.length(); i = i + 1 {
    let mut best = i
    for j = i + 1; j < out.length(); j = j + 1 {
      if priority_of(out[j].diagnosis) < priority_of(out[best].diagnosis) {
        best = j
      }
    }
    if best != i {
      let tmp = out[i]
      out[i] = out[best]
      out[best] = tmp
    }
  }
  out
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
/// 渲染结论分布表（每行带占比条）
fn render_breakdown(m : @model.ReportModel) -> String {
  let b = StringBuilder()
  let total = m.rows.length()
  b.write_string("<table>\n<thead><tr><th>结论</th><th>数量</th><th>占比</th><th>含义</th></tr></thead>\n<tbody>\n")
  let mut any = false
  for l in @model.labels() {
    let n = @model.count_of(m, l)
    if n > 0 {
      any = true
      let pct = fmt_pct(n.to_double() / (if total > 0 { total.to_double() } else { 1.0 }))
      b.write_string(
        "<tr><td class=\"" +
        class_of(l) +
        "\"><code>" +
        escape_html(l) +
        "</code></td><td>" +
        n.to_string() +
        "</td><td><div class=\"bar\"><div class=\"fill " +
        fill_class(l) +
        "\" style=\"width:" +
        pct +
        "\"></div></div></td><td>" +
        escape_html(@model.explain_of(l)) +
        "</td></tr>\n",
      )
    }
  }
  if !any {
    b.write_string("<tr><td colspan=\"4\">（无数据）</td></tr>\n")
  }
  b.write_string("</tbody>\n</table>\n")
  b.to_string()
}

///|
/// 渲染逐条明细表（按可用性排序；证据列截断，悬停看全文）
fn render_rows(m : @model.ReportModel) -> String {
  let b = StringBuilder()
  b.write_string(
    "<div class=\"tbl-wrap\"><table>\n<thead><tr><th>项目</th><th>结论</th><th>规模</th><th>耗时</th><th>证据</th></tr></thead>\n<tbody>\n",
  )
  if m.rows.length() == 0 {
    b.write_string("<tr><td colspan=\"5\">（无数据）</td></tr>\n")
  }
  for r in sorted_rows(m.rows) {
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
      b.write_string("<td class=\"ev\" title=\"" + escape_html(ev) + "\">" + escape_html(ev) + "</td>")
    } else {
      b.write_string("<td>—</td>")
    }
    b.write_string("</tr>\n")
  }
  b.write_string("</tbody>\n</table></div>\n")
  b.to_string()
}

///|
/// 渲染结论横幅（首屏即读懂：可用率 + 概要）
fn render_hero(m : @model.ReportModel) -> String {
  let total = m.rows.length()
  let ok = @model.count_of(m, "Verified")
  let b = StringBuilder()
  b.write_string("<div class=\"hero\">\n")
  b.write_string("  <div class=\"n\">" + escape_html(@model.format_ratio(m)) + "</div>\n")
  b.write_string("  <div class=\"t\">可用率 —— " + ok.to_string() + " / " + total.to_string() + " 个包开箱即用</div>\n")
  if total > 0 {
    b.write_string(
      "  <div class=\"s\">其余 " +
      (total - ok).to_string() +
      " 个包的失败原因各不相同（编译不过 / 工具链版本不匹配 / 非模块 / 含 FFI 等），见下方结论分布与逐条明细。</div>\n",
    )
  }
  b.write_string("</div>\n")
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
  b.write_string("<nav><a href=\"#summary\">结论分布</a><a href=\"#details\">逐个结果</a></nav>\n")

  // 首屏结论横幅
  b.write_string(render_hero(m))

  // 可复现信息置顶
  b.write_string("<div class=\"env\">\n")
  b.write_string("  <div><strong>验证环境</strong>（结论只在此环境下成立）</div>\n")
  b.write_string("  <div>MoonBit 工具链：<code>" + escape_html(m.toolchain) + "</code></div>\n")
  b.write_string("  <div>目标后端：<code>" + escape_html(m.target) + "</code></div>\n")
  b.write_string("  <div>生成时间：<code>" + format_ts(m.generated_at) + "</code>（UTC+8）</div>\n")
  b.write_string("  <div>生成时间戳（毫秒）：<code>" + m.generated_at.to_string() + "</code></div>\n")
  b.write_string("</div>\n")

  b.write_string(render_stats(m))
  b.write_string("<h2 id=\"summary\">结论分布</h2>\n")
  b.write_string(render_breakdown(m))
  b.write_string("<h2 id=\"details\">逐个结果</h2>\n")
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

test "format_ts 把毫秒时间戳转成 UTC+8 可读时间" {
  assert_eq(format_ts(0UL), "1970-01-01 08:00:00")
  // 2026-09-25 11:22:24 (UTC+8)
  assert_eq(format_ts(1790306544680UL), "2026-09-25 11:22:24")
}

test "fmt_pct 一位小数四舍五入" {
  assert_eq(fmt_pct(0.0), "0.0%")
  assert_eq(fmt_pct(1.0), "100.0%")
  assert_eq(fmt_pct(2.0 / 18.0), "11.1%")
}

test "priority_of 可用结论优先" {
  assert_true(priority_of("Verified") < priority_of("Unsafe"))
  assert_true(priority_of("Unsafe") < priority_of("FetchFailed"))
}

test "sorted_rows 不污染原数组且按优先级排列" {
  let rows = [r("x", "Unsafe"), r("a", "Verified"), r("b", "NoManifest")]
  let out = sorted_rows(rows)
  assert_eq(out[0].slug, "a")
  assert_eq(out[1].slug, "b")
  assert_eq(out[2].slug, "x")
  // 原数组顺序不变
  assert_eq(rows[0].slug, "x")
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
  // 环境信息必须出现在明细表之前（用 h2 标题定位，避免命中导航锚点文字）
  let env_pos = h.find("验证环境")
  let rows_pos = h.find("逐个结果</h2>")
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
  assert_true(h.contains("class=\"ok"))
  assert_true(h.contains("class=\"bad"))
  // 占比条
  assert_true(h.contains("class=\"fill"))
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
  assert_true(h.contains("class=\"warn"))
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

test "render 含结论横幅与锚点导航" {
  let h = render(m([r("a", "Verified"), r("b", "Unsafe")]))
  assert_true(h.contains("可用率"))
  assert_true(h.contains("href=\"#summary\""))
  assert_true(h.contains("id=\"summary\""))
  assert_true(h.contains("id=\"details\""))
}
