///|
/// features/inspect — 单包深度体检
///
/// 对指定的一个或多个仓库执行完整验证流程，并输出人类可读的结论。
/// 这是 `survey`（批量普查）的单体版本，也是最早可用的端到端命令。

///|
/// 体检命令的选项
pub struct Options {
  /// 目标后端
  target : String
  /// 单条工具链命令的超时（毫秒）
  timeout_ms : Int
  /// check 通过后是否继续跑测试
  with_test : Bool
  /// 完成后是否保留工作区（便于人工排查）
  keep_workspace : Bool
}

///|
/// 默认选项
pub fn default_options() -> Options {
  { target: "native", timeout_ms: 120000, with_test: true, keep_workspace: false }
}

///|
/// 把字节数格式化为可读文本（复用 workspace 的实现）
fn fmt_bytes(n : Int64) -> String {
  @workspace.format_bytes(n)
}

///|
/// 渲染单个结果
pub fn render_result(r : @check.RevResult) -> String {
  let b = StringBuilder()
  b.write_string(@diagnose.mark(r.diagnosis) + " " + r.slug + "\n")
  b.write_string("   结论: " + @diagnose.label(r.diagnosis) + "\n")
  b.write_string("   说明: " + @diagnose.explain(r.diagnosis) + "\n")
  let ev = @diagnose.evidence(r.diagnosis)
  if ev.length() > 0 {
    b.write_string("   证据: " + ev + "\n")
  }
  if r.fetched {
    b.write_string(
      "   规模: " +
      r.mbt_files.to_string() +
      " 个 .mbt / " +
      r.source_lines.to_string() +
      " 行 / " +
      r.test_files.to_string() +
      " 个测试文件 / " +
      fmt_bytes(r.repo_bytes) +
      "\n",
    )
  }
  if r.check_ms > 0UL || r.test_ms > 0UL {
    b.write_string(
      "   耗时: check " +
      @time.format_ms(r.check_ms) +
      " / test " +
      @time.format_ms(r.test_ms) +
      "\n",
    )
  }
  b.to_string()
}

///|
/// 把命令行参数解析成候选仓库。
///
/// 支持三种写法：
///   - `owner/repo`        远端仓库
///   - `https://github.com/owner/repo`  远端仓库（完整 URL）
///   - `C:\path\to\pkg` / `./pkg`       本地目录（直接复制进工作区，不联网）
pub fn resolve_candidate(raw : String) -> Result[@gitsource.Candidate, String] {
  if @gitsource.looks_like_local_path(raw) {
    match @gitsource.from_local(raw) {
      Ok(c) => Ok(c)
      Err(_) => Err("本地路径不存在或不是目录")
    }
  } else {
    match @gitsource.from_slug(raw) {
      Ok(c) => Ok(c)
      Err(_) => Err("不是合法的 owner/repo，也不是已存在的目录")
    }
  }
}

///|
/// 执行一次体检。
///
/// 返回 (结果数组, 退出码)。退出码约定：
///   0 至少有一个包验证通过；1 全部未通过；其他为环境错误。
pub fn run(slugs : Array[String], opt : Options) -> (Array[@check.RevResult], Int) {
  let results : Array[@check.RevResult] = []

  // 准备：后端探测一次，工作区一个
  let backend = @gitsource.detect_backend()
  println("git TLS 后端: " + @gitsource.backend_description(backend))
  let ws = match @workspace.create() {
    Ok(w) => w
    Err(_) => {
      println("无法创建工作区（临时目录不可写？）")
      return (results, 10)
    }
  }
  println("工作区: " + @workspace.root_of(ws))
  println("目标后端: " + opt.target)
  println("")

  let mut idx = 0
  for raw in slugs {
    idx = idx + 1
    let tag = "[" + idx.to_string() + "/" + slugs.length().to_string() + "] "
    match resolve_candidate(raw) {
      Err(msg) => {
        println(tag + "跳过: " + raw + "（" + msg + "）")
        continue
      }
      Ok(c) => {
        match
          @check.verify_candidate(
            c,
            ws,
            backend,
            opt.target,
            opt.timeout_ms,
            opt.with_test,
          ) {
          Ok(r) => {
            println(tag + render_result(r))
            results.push(r)
            if !opt.keep_workspace {
              @check.release_candidate(ws, c.slug)
            }
          }
          Err(_) => println(tag + c.slug + " 验证过程出错（工作区或获取失败）")
        }
      }
    }
  }

  // 汇总
  let usable = count_usable(results)
  println(summarize(results))
  if !opt.keep_workspace {
    ignore(@workspace.destroy(ws))
  } else {
    println("工作区已保留: " + @workspace.root_of(ws))
  }
  (results, if usable > 0 { 0 } else { 1 })
}

///|
/// 统计"可直接使用"的数量
pub fn count_usable(results : Array[@check.RevResult]) -> Int {
  let mut n = 0
  for r in results {
    if @diagnose.is_usable(r.diagnosis) {
      n = n + 1
    }
  }
  n
}

///|
/// 生成汇总文本：按结论分类计数
pub fn summarize(results : Array[@check.RevResult]) -> String {
  let labels = [
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
  let b = StringBuilder()
  b.write_string("结论汇总（共 " + results.length().to_string() + " 个）\n")
  for l in labels {
    let mut n = 0
    for r in results {
      if @diagnose.label(r.diagnosis) == l {
        n = n + 1
      }
    }
    if n > 0 {
      b.write_string("  " + l + ": " + n.to_string() + "\n")
    }
  }
  b.to_string()
}
