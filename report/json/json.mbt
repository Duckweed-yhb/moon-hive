///|
/// report/json — 机器可读输出
///
/// 为什么需要它：Markdown 报告给人看，JSON 给脚本看。
/// CI 里想判断"这批包里有没有编译不过的"，或者想把历史结果存起来做趋势对比，
/// 都需要一个稳定、可解析的结构。
///
/// 设计要点：
///   - **自包含**：包含 schema 版本、验证环境（工具链/目标后端/时间戳），
///     这样一份旧 JSON 在任何时候都能被正确解读
///   - **纯计算**：只依赖 report/model，不碰文件系统，因此可完全离线单测
///   - **转义完备**：包名、诊断证据里都可能出现引号与反斜杠，
///     不转义就会产生非法 JSON

///|
/// 当前 JSON schema 版本。
/// 字段一旦发布就不再改名；需要变更时递增此版本，让消费方能判断兼容性。
pub const SCHEMA_VERSION : Int = 1

///|
/// 转义 JSON 字符串内容。
///
/// 必须处理的字符：`"` `\` 以及所有控制字符（U+0000–U+001F）。
/// 诊断证据里常出现反斜杠（Windows 路径）与引号，不转义会直接产生非法 JSON。
pub fn escape(s : String) -> String {
  let b = StringBuilder()
  for c in s {
    if c == '"' {
      b.write_string("\\\"")
    } else if c == '\\' {
      b.write_string("\\\\")
    } else if c == '\n' {
      b.write_string("\\n")
    } else if c == '\r' {
      b.write_string("\\r")
    } else if c == '\t' {
      b.write_string("\\t")
    } else if c == '\u{08}' {
      b.write_string("\\b")
    } else if c == '\u{0C}' {
      b.write_string("\\f")
    } else {
      let n = c.to_int()
      if n < 0x20 {
        // 其余控制字符用 \u00XX 形式
        b.write_string("\\u")
        b.write_string(hex4(n))
      } else {
        b.write_char(c)
      }
    }
  }
  b.to_string()
}

///|
/// 取一位十六进制字符。
/// 用码元常量而不是字符字面量，避免 String::unsafe_get 的 UInt16 与 Char 混用。
fn hex_digit(v : Int) -> Char {
  if v < 10 {
    // '0' = 0x30
    Char::from_int(0x30 + v)
  } else {
    // 'a' = 0x61
    Char::from_int(0x61 + v - 10)
  }
}

///|
/// 四位十六进制（小写）
fn hex4(n : Int) -> String {
  let b = StringBuilder()
  b.write_char(hex_digit((n / 4096) % 16))
  b.write_char(hex_digit((n / 256) % 16))
  b.write_char(hex_digit((n / 16) % 16))
  b.write_char(hex_digit(n % 16))
  b.to_string()
}

///|
/// 引号包裹并转义的字符串
fn quoted(s : String) -> String {
  "\"" + escape(s) + "\""
}

///|
/// 渲染为 JSON 文本。
///
/// 结构（稳定契约）：
/// ```json
/// {
///   "schemaVersion": 1,
///   "generatedAt": 1700000000000,
///   "target": "native",
///   "toolchain": "moon 0.1.x",
///   "summary": { "total": 4, "usable": 1, "usableRatio": "25.0%",
///                "byDiagnosis": { "Verified": 1, ... } },
///   "results": [ { "slug": "...", "diagnosis": "Verified", ... } ]
/// }
/// ```
pub fn render(m : @model.ReportModel) -> String {
  let b = StringBuilder()
  b.write_string("{\n")
  b.write_string("  \"schemaVersion\": " + SCHEMA_VERSION.to_string() + ",\n")
  b.write_string("  \"generatedAt\": " + m.generated_at.to_string() + ",\n")
  b.write_string("  \"target\": " + quoted(m.target) + ",\n")
  b.write_string("  \"toolchain\": " + quoted(m.toolchain) + ",\n")

  // summary
  b.write_string("  \"summary\": {\n")
  b.write_string("    \"total\": " + m.rows.length().to_string() + ",\n")
  b.write_string("    \"usable\": " + @model.count_of(m, "Verified").to_string() + ",\n")
  b.write_string("    \"usableRatio\": " + quoted(@model.format_ratio(m)) + ",\n")
  b.write_string("    \"totalSourceLines\": " + @model.total_source_lines(m).to_string() + ",\n")
  b.write_string("    \"totalBytes\": " + @model.total_bytes(m).to_string() + ",\n")
  b.write_string("    \"byDiagnosis\": {")
  let mut first = true
  for l in @model.labels() {
    let n = @model.count_of(m, l)
    if n > 0 {
      if !first {
        b.write_string(",")
      }
      b.write_string("\n      " + quoted(l) + ": " + n.to_string())
      first = false
    }
  }
  if !first {
    b.write_string("\n    ")
  }
  b.write_string("}\n")
  b.write_string("  },\n")

  // results
  b.write_string("  \"results\": [")
  let mut first_row = true
  for r in m.rows {
    if !first_row {
      b.write_string(",")
    }
    b.write_string("\n    {\n")
    b.write_string("      \"slug\": " + quoted(r.slug) + ",\n")
    b.write_string("      \"diagnosis\": " + quoted(r.diagnosis) + ",\n")
    b.write_string("      \"explain\": " + quoted(r.explain) + ",\n")
    b.write_string("      \"evidence\": " + quoted(r.evidence) + ",\n")
    b.write_string("      \"fetched\": " + bool_str(r.fetched) + ",\n")
    b.write_string("      \"mbtFiles\": " + r.mbt_files.to_string() + ",\n")
    b.write_string("      \"sourceLines\": " + r.source_lines.to_string() + ",\n")
    b.write_string("      \"testFiles\": " + r.test_files.to_string() + ",\n")
    b.write_string("      \"repoBytes\": " + r.repo_bytes.to_string() + ",\n")
    b.write_string("      \"checkMs\": " + r.check_ms.to_string() + ",\n")
    b.write_string("      \"testMs\": " + r.test_ms.to_string() + "\n")
    b.write_string("    }")
    first_row = false
  }
  if !first_row {
    b.write_string("\n  ")
  }
  b.write_string("]\n")
  b.write_string("}\n")
  b.to_string()
}

///|
fn bool_str(v : Bool) -> String {
  if v {
    "true"
  } else {
    "false"
  }
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
    mbt_files: 1,
    source_lines: 10,
    test_files: 0,
    repo_bytes: 100L,
    check_ms: 5UL,
    test_ms: 0UL,
  }
}

///|
fn m(rows : Array[@model.ResultRow]) -> @model.ReportModel {
  { generated_at: 42UL, target: "native", toolchain: "moon x", rows }
}

test "escape 处理引号与反斜杠" {
  assert_eq(escape("a\"b"), "a\\\"b")
  assert_eq(escape("a\\b"), "a\\\\b")
  assert_eq(escape("plain"), "plain")
}

test "escape 处理换行与制表符" {
  assert_eq(escape("a\nb"), "a\\nb")
  assert_eq(escape("a\rb"), "a\\rb")
  assert_eq(escape("a\tb"), "a\\tb")
}

test "escape 处理其余控制字符为 \\u00XX" {
  assert_eq(escape("\u{01}"), "\\u0001")
  assert_eq(escape("\u{1f}"), "\\u001f")
  // 空格与普通字符不被转义
  assert_eq(escape("a b"), "a b")
}

test "hex4 输出四位小写十六进制" {
  assert_eq(hex4(0), "0000")
  assert_eq(hex4(1), "0001")
  assert_eq(hex4(15), "000f")
  assert_eq(hex4(31), "001f")
  assert_eq(hex4(255), "00ff")
}

test "render 包含 schema 版本与验证环境（可复现性的关键）" {
  let json = render(m([r("a/b", "Verified")]))
  assert_true(json.contains("\"schemaVersion\": 1"))
  assert_true(json.contains("\"generatedAt\": 42"))
  assert_true(json.contains("\"target\": \"native\""))
  assert_true(json.contains("\"toolchain\": \"moon x\""))
}

test "render 的 summary 计数正确" {
  let json = render(m([r("a", "Verified"), r("b", "Verified"), r("c", "NoManifest")]))
  assert_true(json.contains("\"total\": 3"))
  assert_true(json.contains("\"usable\": 2"))
  assert_true(json.contains("\"usableRatio\": \"66.7%\""))
}

test "render 的 byDiagnosis 只列出非零项" {
  let json = render(m([r("a", "Verified"), r("c", "NoManifest")]))
  assert_true(json.contains("\"Verified\": 1"))
  assert_true(json.contains("\"NoManifest\": 1"))
  assert_false(json.contains("\"TimedOut\""))
}

test "render 的 results 含全部字段" {
  let json = render(m([r("a/b", "Verified")]))
  for key in [
    "\"slug\"",
    "\"diagnosis\"",
    "\"explain\"",
    "\"evidence\"",
    "\"fetched\"",
    "\"mbtFiles\"",
    "\"sourceLines\"",
    "\"testFiles\"",
    "\"repoBytes\"",
    "\"checkMs\"",
    "\"testMs\"",
  ] {
    assert_true(json.contains(key))
  }
}

test "render 转义结果中的特殊字符（不产生非法 JSON）" {
  let row = {
    ..r("a\"b\\c", "DoesNotCompile"),
    evidence: "line1\nline2\ttab",
  }
  let json = render(m([row]))
  assert_true(json.contains("a\\\"b\\\\c"))
  assert_true(json.contains("line1\\nline2\\ttab"))
  // 原文中的裸换行不应出现在字符串值里
  assert_false(json.contains("line1\nline2"))
}

test "render 空报告是合法结构" {
  let json = render(m([]))
  assert_true(json.contains("\"total\": 0"))
  assert_true(json.contains("\"usable\": 0"))
  assert_true(json.contains("\"results\": []"))
}

test "render 结构首尾闭合" {
  let json = render(m([r("a", "Verified")]))
  assert_true(json.has_prefix("{"))
  assert_true(json.trim().has_suffix("}"))
}

test "render 多行结果之间用逗号分隔" {
  let json = render(m([r("a", "Verified"), r("b", "NoManifest")]))
  assert_true(json.contains("},\n    {"))
}
