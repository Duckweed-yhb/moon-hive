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
fn print_usage() -> Unit {
  println(version_line())
  println("")
  println("用法: moonhive <命令> [参数...]")
  println("")
  println("命令:")
  println("  inspect <owner/repo>...  体检指定仓库：拉下来用真实工具链验证能否编译与测试")
  println("  doctor                   检查运行环境（工具链 / git / TLS / 临时目录）")
  println("  version                  打印版本")
  println("  help                     打印本帮助")
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
