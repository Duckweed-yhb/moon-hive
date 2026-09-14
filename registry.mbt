///| 插件注册表：返回项目所有已注册的插件
pub fn all_plugins() -> Array[&Plugin] {
  [Base64Plugin::{}, HexPlugin::{}, DailyPlugin::{}]
}

///| 根据插件名查找插件；找不到返回 None
pub fn find_plugin(name : String) -> Option[&Plugin] {
  for plugin in all_plugins() {
    if plugin.name() == name {
      return Some(plugin)
    }
  }
  None
}
