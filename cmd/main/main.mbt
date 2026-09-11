///|
/// MoonHive 插件化 CLI 工具基座 - 可执行入口
///
/// 用法: moon run cmd/main <plugin> <command> [args...]
/// 示例: moon run cmd/main base64 encode "hello world"
fn main {
  let plugin = @lib.Base64Plugin::{}
  print_plugin_info(plugin)
}

/// 打印任意插件的信息（参数是 Plugin 特征对象，任何插件都能传进来）
fn print_plugin_info(plugin : &@lib.Plugin) -> Unit {
  println("插件名: " + plugin.name())
  println("描述: " + plugin.description())
}
