///|
/// MoonHive — MoonBit 生态验证引擎
///
/// 用法: moonhive <命令> [参数...]
///
/// 退出码约定（与 core/error 的 exit_code_of 一致）：
///   0  成功
///   10 环境错误   11 进程错误   12 文件错误
///   13 未找到     14 参数错误   15 工具链错误

///|
fn main {
  let argv = @env.args()
  if argv.length() <= 1 {
    print_usage()
    @proc.exit_with(0)
    return
  }
  let cmd = argv[1]
  let rest : Array[String] = if argv.length() > 2 {
    argv[2:].to_owned()
  } else {
    []
  }
  match cmd {
    "doctor" => cmd_doctor()
    "inspect" => cmd_inspect(rest)
    "survey" => cmd_survey(rest)
    "version" | "--version" | "-V" => println(version_line())
    "help" | "--help" | "-h" => print_usage()
    other => {
      println("未知命令: " + other)
      println("")
      print_usage()
      @proc.exit_with(14)
    }
  }
}

///|
fn version_line() -> String {
  "moonhive 0.2.0 (MoonBit 生态验证引擎)"
}

///|
fn cmd_doctor() -> Unit {
  let report = @doctor.run_doctor()
  println(@doctor.render(report))
  if @doctor.has_failure(report) {
    @proc.exit_with(10)
  }
}

///|
/// inspect 命令：moonhive inspect <owner/repo> [owner/repo ...]
fn cmd_inspect(args : Array[String]) -> Unit {
  if args.length() == 0 {
    println("用法: moonhive inspect <owner/repo> [owner/repo ...]")
    println("")
    println("示例: moonhive inspect moonbit-community/yaml")
    @proc.exit_with(14)
    return
  }
  let (results, code) = @inspect.run(args, @inspect.default_options())
  ignore(results)
  @proc.exit_with(code)
}

///|
/// survey 命令：moonhive survey [--out md] [--json f] [--site f] <候选>...
///
/// 候选可以是 owner/repo、HTTPS URL 或本地目录。
/// 三种报告格式可同时输出，共用同一份数据模型。
fn cmd_survey(args : Array[String]) -> Unit {
  if args.length() == 0 {
    println("用法: moonhive survey [--out <md>] [--json <json>] [--site <html>] <候选>...")
    println("")
    println("候选可以是 owner/repo、https://github.com/owner/repo 或本地目录")
    println(
      "示例: moonhive survey --out report.md --json report.json --site index.html moonbit-community/yaml",
    )
    @proc.exit_with(14)
    return
  }
  let mut md_path = ""
  let mut json_path = ""
  let mut site_path = ""
  let candidates : Array[@gitsource.Candidate] = []
  let mut i = 0
  let bad : Array[String] = []
  while i < args.length() {
    let a = args[i]
    if (a == "--out" || a == "--md") && i + 1 < args.length() {
      md_path = args[i + 1]
      i = i + 2
    } else if a == "--json" && i + 1 < args.length() {
      json_path = args[i + 1]
      i = i + 2
    } else if a == "--site" && i + 1 < args.length() {
      site_path = args[i + 1]
      i = i + 2
    } else if a.has_prefix("--out=") {
      md_path = a.substring(start=6, end=a.length())
      i = i + 1
    } else if a.has_prefix("--json=") {
      json_path = a.substring(start=7, end=a.length())
      i = i + 1
    } else if a.has_prefix("--site=") {
      site_path = a.substring(start=7, end=a.length())
      i = i + 1
    } else {
      match @inspect.resolve_candidate(a) {
        Ok(c) => candidates.push(c)
        Err(msg) => bad.push(a + "（" + msg + "）")
      }
      i = i + 1
    }
  }
  for b in bad {
    println("跳过: " + b)
  }
  if candidates.length() == 0 {
    println("没有可验证的候选。")
    @proc.exit_with(14)
    return
  }
  let opt : @survey.SurveyOptions = {
    target: "native",
    timeout_ms: 120000,
    with_test: true,
    md_path,
    json_path,
    site_path,
  }
  let (_report, code) = @survey.run(candidates, opt)
  @proc.exit_with(code)
}

///|
fn print_usage() -> Unit {
  println(version_line())
  println("")
  println("用法: moonhive <命令> [参数...]")
  println("")
  println("命令:")
  println("  survey [--out md] [--json f] [--site f] <候选>...")
  println("                                  批量普查并生成三种格式的报告")
  println("  inspect <候选>...               体检指定仓库：拉下来用真实工具链验证")
  println("  doctor                          检查运行环境（工具链 / git / TLS / 临时目录）")
  println("  version                         打印版本")
  println("  help                            打印本帮助")
  println("")
  println("候选写法: owner/repo | https://github.com/owner/repo | 本地目录路径")
  println("")
  println("结论说明:")
  println("  ✅ Verified            编译与测试通过，可以直接使用")
  println("  ⚠️  TestFailing         能编译但测试未通过")
  println("  ❌ DoesNotCompile       编译器报错")
  println("  🚫 ToolchainMismatch    版本/API 不兼容——不是包的问题")
  println("  📦 MissingDependency    依赖解析失败")
  println("  📄 NoManifest           不是 MoonBit 模块")
  println("  ⏱️  TimedOut            超出时间预算")
  println("  🔒 Unsafe               含 FFI/自定义构建配置，只做静态分析")
  println("  🌐 FetchFailed          获取仓库失败")
}
