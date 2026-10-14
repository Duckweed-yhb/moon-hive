///|
/// MoonHive 可运行示例：语义化归因演示
///
/// 同一个 "Type X has no method Y" 措辞，缺失符号归属不同则结论不同：
///   - 缺失符号属 core（Bytes / String / Array …）→ ToolchainMismatch（工具链版本差异）
///   - 缺失符号属包自身（MyPacket …）            → DoesNotCompile（包/文档写错）
///
/// 这正是 MoonHive 与"对报错文本做字符串匹配"的根本区别——
/// 不再对特征串一刀切，而是对缺失符号做归属分析（`classify_verified`）。
///
/// 运行：moon run main --target native （在 docs/examples/classify-demo 目录下）

///|
/// 构造一次"moon check 失败"的输入
fn failing_check(stderr : String) -> @diagnose.CommandOutcome {
  { exit_code: 1, stdout: "", stderr: stderr }
}

///|
/// 构造一个完整检查结果
fn outcome(check : @diagnose.CommandOutcome) -> @diagnose.CheckOutcome {
  {
    has_manifest: true,
    risky: false,
    timed_out: false,
    check: check,
    test_outcome: None,
    declared_targets: [],
    target: "native",
  }
}

///|
/// 打印一条结论
fn print_case(title : String, check : @diagnose.CommandOutcome) -> Unit {
  let d = @diagnose.classify(outcome(check))
  println(title)
  println("  结论: " + @diagnose.mark(d) + " " + @diagnose.label(d))
  println("  含义: " + @diagnose.explain(d))
  println("  证据: " + @diagnose.evidence(d))
  println("")
}

fn main() -> Unit {
  println("=== MoonHive 语义化归因示例 ===\n")

  // 场景 1：core 符号缺失 → 工具链版本差异（不是包的错）
  // Bytes 属 core 类型，随工具链版本管控，其方法缺失判 ToolchainMismatch。
  let s1 = outcome(failing_check("Error: [4015]\n  Type Bytes has no method exact_view."))
  let d1 = @diagnose.classify_verified(s1, [])
  println("场景1: Type Bytes has no method exact_view.（Bytes 属 core）")
  println("  结论: " + @diagnose.mark(d1) + " " + @diagnose.label(d1))
  println("  含义: " + @diagnose.explain(d1))
  println("")

  // 场景 2：包自身符号缺失 → 包/文档写错（语义化判定的关键区别）
  // MyPacket 是包自身类型，其方法缺失是包写错，不应误判为工具链问题。
  // 这正是回应评审"对语义没有了解"的核心：对缺失符号做归属分析，
  // 而不是把一切 "has no method" 都归为工具链不兼容。
  let s2 = outcome(failing_check("Error: [4015]\n  Type MyPacket has no method encode."))
  let d2 = @diagnose.classify_verified(s2, [])
  println("场景2: Type MyPacket has no method encode.（MyPacket 属包自身）")
  println("  结论: " + @diagnose.mark(d2) + " " + @diagnose.label(d2))
  println("  含义: " + @diagnose.explain(d2))
  println("")

  // 场景 3：外部探测注入确认缺失 → ToolchainMismatch
  // 当 verify/compare 跨工具链对比确认某符号在当前工具链确实缺失时，
  // 通过 confirmed_missing 注入证据，一并判工具链不兼容。
  let s3 = outcome(failing_check("Error: [4015]\n  Type Bytes has no method exact_view."))
  let d3 = @diagnose.classify_verified(s3, ["Bytes.exact_view"])
  println("场景3: 跨工具链探测确认 Bytes.exact_view 缺失 → 工具链不兼容")
  println("  结论: " + @diagnose.mark(d3) + " " + @diagnose.label(d3))
  println("")

  // 场景 4：真实语法错误 → 确定的代码问题，不是工具链漂移
  print_case(
    "场景4: Parse error, unexpected token.（语法错误是代码问题）",
    failing_check(
      "Error: [3002]\nParse error, unexpected token `?`, you may expect a statement or expression on a new line.",
    ),
  )

  // 场景 5：全绿 → 可直接使用
  let d5 = @diagnose.classify(outcome({ exit_code: 0, stdout: "", stderr: "" }))
  println("场景5: moon check 通过（无错误）")
  println("  结论: " + @diagnose.mark(d5) + " " + @diagnose.label(d5))
  println("  含义: " + @diagnose.explain(d5))
  println("")
}
