///|
/// MoonHive 插件化 CLI 工具基座 - 可执行入口
///
/// 用法: moon run cmd/main <plugin> <command> [args...]
/// 示例: moon run cmd/main base64 encode "hello world"
fn main {
  list_plugins()
}

/// 列出所有已注册的插件
fn list_plugins() -> Unit {
  println("可用插件：")
  for plugin in @lib.all_plugins() {
    println("- " + plugin.name() + ": " + plugin.description())
  }
}
