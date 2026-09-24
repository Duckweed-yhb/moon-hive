///|
/// features/serve — 本地验证仪表盘命令
///
/// 用法：moonhive serve [--dir <报告目录>] [--port <端口>] [--gen-only]
///
/// 默认报告目录为当前目录下的 `reports`，端口 8080。
/// `--gen-only` 只写入仪表盘入口不启动服务器（可用于部署静态站）。

///|
/// 默认报告目录
pub fn default_dir() -> String {
  "reports"
}

///|
/// 把服务器错误码转成可读文本
fn err_text(e : @http.ServeError) -> String {
  match e {
    WsaInit => "Winsock 初始化失败"
    Socket => "创建 socket 失败"
    Bind => "端口被占用或绑定失败（换 --port 试试）"
    Listen => "监听失败"
    Accept => "accept 循环异常退出"
  }
}

///|
/// 解析并校验端口参数
fn parse_port(s : String) -> Int? {
  let mut p = 0
  for c in s {
    if c >= '0' && c <= '9' {
      p = p * 10 + c.to_int() - 48
    } else {
      return None
    }
  }
  if p == 0 && s.length() > 0 {
    // 全是数字，0 也算合法解析结果
    return Some(0)
  }
  Some(p)
}

///|
/// 执行 serve 命令。返回进程退出码。
pub fn run(args : Array[String]) -> Int {
  let mut dir = default_dir()
  let mut port = @http.default_port()
  let mut gen_only = false
  let mut i = 0
  while i < args.length() {
    let a = args[i]
    if a == "--dir" && i + 1 < args.length() {
      dir = args[i + 1]
      i = i + 2
    } else if a == "--port" && i + 1 < args.length() {
      match parse_port(args[i + 1]) {
        Some(p) => port = p
        None => {
          println("端口必须是数字: " + args[i + 1])
          return 14
        }
      }
      i = i + 2
    } else if a == "--gen-only" {
      gen_only = true
      i = i + 1
    } else if a == "--help" || a == "-h" {
      println("用法: moonhive serve [--dir <报告目录>] [--port <端口>] [--gen-only]")
      println("默认: 报告目录=reports, 端口=8080")
      println("先跑 survey 生成报告: moonhive survey --json reports/2026-09-24.json <候选>...")
      return 0
    } else {
      println("未知参数: " + a)
      println("用法: moonhive serve [--dir <报告目录>] [--port <端口>] [--gen-only]")
      return 14
    }
  }

  if !(@fs.is_dir(dir)) {
    println("报告目录不存在: " + dir)
    println("先生成报告: moonhive survey --json " + @proc.join_path(dir, "<名字>.json") + " <候选>...")
    println("（目录会自动创建）")
    // 自动创建目录，让流程更顺
    if !(@fs.mkdir_all(dir)) {
      println("创建目录失败")
      return 14
    }
  }

  if !(@http.valid_port(port)) {
    println("端口非法（需 1024-65535）: " + port.to_string())
    return 14
  }

  // 写入仪表盘入口（每次 serve 都会用最新模板刷新）
  let entry = @proc.join_path(dir, "dashboard.html")
  if !(@fs.write_text(entry, template())) {
    println("无法写入仪表盘入口: " + entry)
    return 14
  }

  println("MoonHive 生态验证仪表盘")
  println("报告目录: " + dir)
  println("入口文件: " + entry)
  if gen_only {
    println("已生成入口（--gen-only，未启动服务器）")
    return 0
  }
  println("访问地址: http://127.0.0.1:" + port.to_string() + "/")
  println("按 Ctrl+C 停止")
  match @http.serve(dir, port) {
    None => 0
    Some(e) => {
      println("服务器错误: " + err_text(e))
      return 14
    }
  }
}
