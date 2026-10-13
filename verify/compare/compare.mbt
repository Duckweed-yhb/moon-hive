///|
/// verify/compare — 跨工具链行为对比（纯计算，可离线单测）
///
/// 单工具链判定（verify/diagnose）回答"这个包在当前工具链上能不能用"，
/// 但它有一个内在软肋：**判定依赖编译器措辞的特征串匹配**，评审可以反问
/// "这个分类逻辑凭什么不能是脚本里的一百行"。本模块把它升级为
/// **跨工具链行为对比**：
///
///   同一个候选包，用 N 个 moon 版本（工具链命令）各验证一遍，
///   对比诊断结果：
///     - 所有工具链一致通过          → AllGreen（包健康）
///     - 所有工具链一致失败（同标签）→ ConsistentFail（包本身的问题）
///     - 有通过有失败                → ToolchainDrift（工具链演进 / API 漂移，
///                                    直接证明"不是包的错"）
///     - 都失败但原因不同            → InconsistentFail（需要进一步调查）
///
/// 这一对比不依赖任何编译器措辞：无论诊断来自特征串还是未来更强的
/// 归因器，"行为是否随工具链变化"本身是机制性证据。它同样不跑进程，
/// 只吃「工具链名 + 诊断结果」，因此可以完全离线单测。
///
/// 设计约束：本包不 import 任何 platform 包，声明覆盖全部四个后端。

///|
/// 一次工具链运行的结果（compare_runs 的输入）
pub(all) struct ToolchainRun {
  /// 工具链命令或版本标识（如 "moon"、"moon-0.10.14"、"0.11.0"）
  toolchain : String
  /// 该工具链下的诊断结论
  diagnosis : @diagnose.Diagnosis
  /// 结论证据（首条诊断信息，可为空）
  evidence : String
}

///|
/// 跨工具链对比的最终判定
pub enum CompareVerdict {
  /// 所有工具链一致通过 —— 包健康
  AllGreen
  /// 所有工具链一致失败（同一诊断标签）—— 包本身的问题，与工具链版本无关
  ConsistentFail(String)
  /// 结果随工具链版本变化（有通过有失败）—— 工具链演进 / API 漂移，不是包坏了
  ToolchainDrift(Array[ToolchainRun])
  /// 都失败但原因不同 —— 需要进一步调查
  InconsistentFail(Array[ToolchainRun])
}

///|
/// 对比一组工具链运行结果，给出判定。
///
/// 判定顺序：
///   1. 空输入 → ConsistentFail("没有工具链运行结果")（防御，不猜结论）
///   2. 全部 Verified → AllGreen
///   3. 有通过有失败 → ToolchainDrift（无论失败原因，行为随版本变化）
///   4. 全部失败且诊断标签一致 → ConsistentFail(标签)
///   5. 全部失败但标签不同 → InconsistentFail
pub fn compare_runs(runs : Array[ToolchainRun]) -> CompareVerdict {
  if runs.length() == 0 {
    return ConsistentFail("没有工具链运行结果")
  }
  let mut all_green = true
  let mut any_green = false
  let first_label = @diagnose.label(runs[0].diagnosis)
  let mut all_same_label = true
  for r in runs {
    if @diagnose.is_usable(r.diagnosis) {
      any_green = true
    } else {
      all_green = false
    }
    if @diagnose.label(r.diagnosis) != first_label {
      all_same_label = false
    }
  }
  if all_green {
    AllGreen
  } else if any_green {
    ToolchainDrift(runs)
  } else if all_same_label {
    ConsistentFail(first_label)
  } else {
    InconsistentFail(runs)
  }
}

///|
/// 判定的短标签（用于表格与 JSON）
pub fn verdict_label(v : CompareVerdict) -> String {
  match v {
    AllGreen => "AllGreen"
    ConsistentFail(_) => "ConsistentFail"
    ToolchainDrift(_) => "ToolchainDrift"
    InconsistentFail(_) => "InconsistentFail"
  }
}

///|
/// 判定的符号（用于终端展示）
pub fn verdict_mark(v : CompareVerdict) -> String {
  match v {
    AllGreen => "✅"
    ConsistentFail(_) => "❌"
    ToolchainDrift(_) => "🚫"
    InconsistentFail(_) => "⚠️ "
  }
}

///|
/// 判定的简要解释（面向用户）
pub fn verdict_explain(v : CompareVerdict) -> String {
  match v {
    AllGreen => "所有工具链一致通过，包健康"
    ConsistentFail(label) => "所有工具链一致失败（" + label + "），是包本身的问题，与工具链版本无关"
    ToolchainDrift(_) => "结果随工具链版本变化（有通过有失败），是工具链演进 / API 漂移，不是包坏了"
    InconsistentFail(_) => "各工具链失败原因不同，需要进一步调查"
  }
}

///|
/// 把对比结果渲染为人类可读文本（逐工具链一行 + 结论）。
pub fn render_compare(subject : String, runs : Array[ToolchainRun], v : CompareVerdict) -> String {
  let mut s = verdict_mark(v) + " " + subject + "  →  " + verdict_label(v) + "\n"
  s = s + "    " + verdict_explain(v) + "\n"
  for r in runs {
    s = s + "    [" + r.toolchain + "] "
    s = s + @diagnose.mark(r.diagnosis) + " " + @diagnose.label(r.diagnosis)
    if r.evidence.length() > 0 {
      s = s + " — " + r.evidence
    }
    s = s + "\n"
  }
  s
}

///|
/// 把对比结果渲染为一行 JSON（便于脚本消费）。
pub fn to_json(subject : String, runs : Array[ToolchainRun], v : CompareVerdict) -> String {
  let mut out = "{"
  out = out + "\"subject\":\"" + escape_json(subject) + "\""
  out = out + ",\"verdict\":\"" + verdict_label(v) + "\""
  out = out + ",\"runs\":["
  let mut first = true
  for r in runs {
    if !first {
      out = out + ","
    }
    first = false
    out = out + "{\"toolchain\":\"" + escape_json(r.toolchain) + "\""
    out = out + ",\"diagnosis\":\"" + @diagnose.label(r.diagnosis) + "\""
    out = out + ",\"evidence\":\"" + escape_json(r.evidence) + "\"}"
  }
  out = out + "]"
  out + "}"
}

///|
/// JSON 字符串转义（最小实现：引号与反斜杠）
fn escape_json(s : String) -> String {
  let mut out = ""
  for c in s {
    if c == '"' {
      out = out + "\\\""
    } else if c == '\\' {
      out = out + "\\\\"
    } else {
      out = out + c.to_string()
    }
  }
  out
}

// ---------- 单元测试 ----------

///|
fn run(tc : String, d : @diagnose.Diagnosis) -> ToolchainRun {
  { toolchain: tc, diagnosis: d, evidence: @diagnose.evidence(d) }
}

test "compare: 空输入 → ConsistentFail（防御，不猜结论）" {
  match compare_runs([]) {
    ConsistentFail(m) => assert_eq(m, "没有工具链运行结果")
    other => fail("应为 ConsistentFail，实际 " + verdict_label(other))
  }
}

test "compare: 全部 Verified → AllGreen" {
  let runs = [run("moon", @diagnose.Verified), run("moon-0.11", @diagnose.Verified)]
  match compare_runs(runs) {
    AllGreen => ()
    other => fail("应为 AllGreen，实际 " + verdict_label(other))
  }
}

test "compare: 单工具链通过 → AllGreen" {
  let runs = [run("moon", @diagnose.Verified)]
  match compare_runs(runs) {
    AllGreen => ()
    other => fail("应为 AllGreen，实际 " + verdict_label(other))
  }
}

test "compare: 有通过有失败 → ToolchainDrift（工具链演进）" {
  // 场景：旧工具链通过、新工具链报 has no method —— 正是 moonbitlang/x 形态
  let runs = [
    run("moon-0.10.14", @diagnose.Verified),
    run("moon", @diagnose.ToolchainMismatch("Type Bytes has no method exact_view.")),
  ]
  match compare_runs(runs) {
    ToolchainDrift(rs) => {
      assert_eq(rs.length(), 2)
      assert_eq(rs[0].toolchain, "moon-0.10.14")
    }
    other => fail("应为 ToolchainDrift，实际 " + verdict_label(other))
  }
}

test "compare: 反向漂移（新通过旧失败）→ ToolchainDrift" {
  let runs = [
    run("moon-0.9", @diagnose.DoesNotCompile("Parse error")),
    run("moon", @diagnose.Verified),
  ]
  match compare_runs(runs) {
    ToolchainDrift(_) => ()
    other => fail("应为 ToolchainDrift，实际 " + verdict_label(other))
  }
}

test "compare: 全部失败且同为 DoesNotCompile → ConsistentFail（包坏）" {
  let runs = [
    run("moon-0.10.14", @diagnose.DoesNotCompile("Type mismatch")),
    run("moon", @diagnose.DoesNotCompile("Type mismatch")),
  ]
  match compare_runs(runs) {
    ConsistentFail(label) => assert_eq(label, "DoesNotCompile")
    other => fail("应为 ConsistentFail，实际 " + verdict_label(other))
  }
}

test "compare: 全部失败且同为 ToolchainMismatch → ConsistentFail" {
  // 两个版本都报同一 API 缺失：说明这个"缺失"与版本无关，是包真的依赖了不存在的 API
  let runs = [
    run("moon-0.10.14", @diagnose.ToolchainMismatch("unresolved identifier @foo.bar")),
    run("moon", @diagnose.ToolchainMismatch("unresolved identifier @foo.bar")),
  ]
  match compare_runs(runs) {
    ConsistentFail(label) => assert_eq(label, "ToolchainMismatch")
    other => fail("应为 ConsistentFail，实际 " + verdict_label(other))
  }
}

test "compare: 都失败但原因不同 → InconsistentFail" {
  let runs = [
    run("moon-0.10.14", @diagnose.DoesNotCompile("Type mismatch")),
    run("moon", @diagnose.ToolchainMismatch("has no method")),
  ]
  match compare_runs(runs) {
    InconsistentFail(rs) => assert_eq(rs.length(), 2)
    other => fail("应为 InconsistentFail，实际 " + verdict_label(other))
  }
}

test "compare: 有 NoManifest 与 Verified 混合 → ToolchainDrift" {
  let runs = [
    run("moon", @diagnose.NoManifest),
    run("moon-0.11", @diagnose.Verified),
  ]
  match compare_runs(runs) {
    ToolchainDrift(_) => ()
    other => fail("应为 ToolchainDrift，实际 " + verdict_label(other))
  }
}

test "verdict_label / mark / explain 覆盖全部变体" {
  let all = [AllGreen, ConsistentFail("x"), ToolchainDrift([]), InconsistentFail([])]
  for v in all {
    assert_true(verdict_label(v).length() > 0)
    assert_true(verdict_mark(v).length() > 0)
    assert_true(verdict_explain(v).length() > 0)
  }
}

test "verdict_explain: ConsistentFail 说明与版本无关" {
  let e = verdict_explain(ConsistentFail("DoesNotCompile"))
  assert_true(e.contains("DoesNotCompile"))
  assert_true(e.contains("版本无关"))
}

test "verdict_explain: ToolchainDrift 说明是工具链演进" {
  let e = verdict_explain(ToolchainDrift([]))
  assert_true(e.contains("工具链演进"))
  assert_true(e.contains("不是包坏了"))
}

test "render_compare 逐工具链渲染 + 结论" {
  let runs = [
    run("moon-0.10.14", @diagnose.Verified),
    run("moon", @diagnose.ToolchainMismatch("Type Bytes has no method exact_view.")),
  ]
  let v = compare_runs(runs)
  let s = render_compare("owner/pkg", runs, v)
  assert_true(s.contains("owner/pkg"))
  assert_true(s.contains("ToolchainDrift"))
  assert_true(s.contains("[moon-0.10.14]"))
  assert_true(s.contains("exact_view"))
}

test "to_json 输出 subject/verdict/runs 字段" {
  let runs = [run("moon", @diagnose.Verified)]
  let j = to_json("a/b", runs, AllGreen)
  assert_true(j.contains("\"subject\":\"a/b\""))
  assert_true(j.contains("\"verdict\":\"AllGreen\""))
  assert_true(j.contains("\"toolchain\":\"moon\""))
  assert_true(j.contains("\"diagnosis\":\"Verified\""))
}

test "escape_json 处理引号与反斜杠" {
  assert_eq(escape_json("a\"b"), "a\\\"b")
  assert_eq(escape_json("c\\d"), "c\\\\d")
}
