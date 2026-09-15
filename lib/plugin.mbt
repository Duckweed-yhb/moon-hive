///| 插件接口：所有插件必须遵守的合同
///| name: 插件名；description: 插件描述；execute: 执行插件命令并返回结果文本
pub trait Plugin {
  name(Self) -> String
  description(Self) -> String
  execute(Self, command : String, args : ArrayView[String]) -> String
}
