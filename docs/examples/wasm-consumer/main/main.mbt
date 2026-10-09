///|
/// 非 native 消费者最小示例：证明 verify/diagnose 是纯计算，可在 wasm/js 后端直接使用。
///
/// 运行：moon test --target wasm

///|
/// 构造一个"工具链不匹配"场景并断言归因。
test "wasm 上 classify 工具链不匹配" {
  let outcome : @diagnose.CheckOutcome = {
    has_manifest: true,
    risky: false,
    timed_out: false,
    check: {
      exit_code: 1,
      stdout: "",
      stderr: "Type Bytes has no method exact_view.",
    },
    test_outcome: None,
    declared_targets: [],
    target: "wasm",
  }
  let d = @diagnose.classify(outcome)
  if @diagnose.label(d) != "ToolchainMismatch" {
    fail("期望 ToolchainMismatch，实际 " + @diagnose.label(d))
  }
}

///|
/// 构造一个"缺清单"场景并断言归因。
test "wasm 上 classify 缺清单" {
  let outcome : @diagnose.CheckOutcome = {
    has_manifest: false,
    risky: false,
    timed_out: false,
    check: { exit_code: 0, stdout: "", stderr: "" },
    test_outcome: None,
    declared_targets: [],
    target: "wasm",
  }
  let d = @diagnose.classify(outcome)
  if @diagnose.label(d) != "NoManifest" {
    fail("期望 NoManifest，实际 " + @diagnose.label(d))
  }
}
