///|
/// MoonHive 插件化 CLI 工具基座 - 可执行入口
///
/// 用法: moon run cmd/main <plugin> <command> [args...]
/// 示例: moon run cmd/main base64 encode "hello world"
fn main {
  let argv = @env.args()
  if argv.length() <= 1 {
    list_plugins()
  } else {
    run_plugin(argv[1])
  }
}

/// 列出所有已注册的插件
fn list_plugins() -> Unit {
  println("可用插件：")
  for plugin in @lib.all_plugins() {
    println("- " + plugin.name() + ": " + plugin.description())
  }
}

/// 根据插件名调用对应插件
fn run_plugin(name : String) -> Unit {
  match @lib.find_plugin(name) {
    Some(plugin) => {
      println("插件名: " + plugin.name())
      println("描述: " + plugin.description())
    }
    None => println("未知插件: " + name)
  }
}
