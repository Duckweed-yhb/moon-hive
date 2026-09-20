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
  match cmd {
    "doctor" => cmd_doctor()
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
fn print_usage() -> Unit {
  println(version_line())
  println("")
  println("用法: moonhive <命令> [参数...]")
  println("")
  println("命令:")
  println("  doctor     检查运行环境（工具链 / git / TLS / 临时目录）")
  println("  version    打印版本")
  println("  help       打印本帮助")
}
