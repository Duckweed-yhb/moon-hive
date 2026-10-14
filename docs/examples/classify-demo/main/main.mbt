///|
/// MoonHive 可运行示例：语义化归因演示
///
/// 同一个 "Type X has no method Y" 措辞，归属不同则结论不同：
///   - 缺失符号属 core（Bytes / String / Array …）→ ToolchainMismatch（工具链版本差异）
///   - 缺失符号属包自身（MyPacket …）        → DoesNotCompile（包/文档写错）
///
/// 这正是 MoonHive 与"对报错文本做字符串匹配"的根本区别——
/// 不再对特征串一刀切，而是对缺失符号做归属分析。
///
/// 运行：moon run --target native （在 docs/examples/classify-demo 目录下）

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
  print_case(
    "场景1: Type Bytes has no method exact_view.（Bytes 属 core，随工具链版本管控）",
    failing_check("Error: [4015]\n  Type Bytes has no method exact_view."),
  )

  // 场景 2：包自身符号缺失 → 应判 DoesNotCompile（包/文档写错）
  print_case(
    "场景2: Type MyPacket has no method encode.（MyPacket 属包自身）",
    failing_check("Error: [4015]\n  Type MyPacket has no method encode."),
  )

  // 场景 3：真实语法错误 → 确定的代码问题，不是工具链漂移
  print_case(
    "场景3: Parse error, unexpected token.（语法错误是代码问题）",
    failing_check(
      "Error: [3002]\nParse error, unexpected token `?`, you may expect a statement or expression on a new line.",
    ),
  )

  // 场景 4：全绿 → 可直接使用
  let ok = @diagnose.classify(outcome({ exit_code: 0, stdout: "", stderr: "" }))
  println("场景4: moon check 通过（无错误）")
  println("  结论: " + @diagnose.mark(ok) + " " + @diagnose.label(ok))
  println("  含义: " + @diagnose.explain(ok))
  println("")
}
