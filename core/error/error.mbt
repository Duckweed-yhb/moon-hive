///|
/// core/error — MoonHive 统一错误契约
///
/// 设计目标：把 v1 里"到处返回 String、靠字符串判断成败"的做法，
/// 换成可穷尽匹配、可映射退出码的类型化错误。
///
/// 分层原则：
///   - 本模块只定义错误与分类，不依赖 platform、不依赖 IO
///   - 每个变体都有明确的 `code()` 与 `exit_code()`，供 CLI 与测试断言

///|
/// MoonHive 全局错误类型
pub suberror MoonHiveError {
  /// 环境不满足运行条件（缺 git / 缺 moon / 临时目录不可写…）
  Environment(String)
  /// 子进程执行失败（无法启动、内存不足等），区别于"非零退出码"
  Process(String)
  /// 文件系统操作失败
  FileSystem(String)
  /// 找不到指定对象（包、仓库、报告…）
  NotFound(String)
  /// 输入的参数不合法
  InvalidArgument(String)
  /// 依赖的工具链问题（版本过低、缺少目标后端…）
  Toolchain(String)
}

///|
/// 0 = 成功；非 0 = 失败。约定与 CLI 退出码一致。
pub fn exit_code_of(err : MoonHiveError) -> Int {
  match err {
    Environment(_) => 10
    Process(_) => 11
    FileSystem(_) => 12
    NotFound(_) => 13
    InvalidArgument(_) => 14
    Toolchain(_) => 15
  }
}

///|
/// 人类可读的错误描述（CLI 直接打印）
pub fn message_of(err : MoonHiveError) -> String {
  match err {
    Environment(m) => "环境错误: " + m
    Process(m) => "进程错误: " + m
    FileSystem(m) => "文件错误: " + m
    NotFound(m) => "未找到: " + m
    InvalidArgument(m) => "参数错误: " + m
    Toolchain(m) => "工具链错误: " + m
  }
}

///|
/// 简短错误类别名，用于日志与结构化输出
pub fn category_of(err : MoonHiveError) -> String {
  match err {
    Environment(_) => "environment"
    Process(_) => "process"
    FileSystem(_) => "filesystem"
    NotFound(_) => "not_found"
    InvalidArgument(_) => "invalid_argument"
    Toolchain(_) => "toolchain"
  }
}

///|
/// 把进程层错误转成全局错误
pub fn from_process_error(m : String) -> MoonHiveError {
  Process(m)
}

///|
/// 把文件层错误转成全局错误
pub fn from_fs_error(m : String) -> MoonHiveError {
  FileSystem(m)
}

// ---------- 单元测试 ----------

test "exit_code_of: 每个变体都有唯一退出码" {
  let codes = [
    exit_code_of(Environment("x")),
    exit_code_of(Process("x")),
    exit_code_of(FileSystem("x")),
    exit_code_of(NotFound("x")),
    exit_code_of(InvalidArgument("x")),
    exit_code_of(Toolchain("x")),
  ]
  for c in codes {
    assert_true(c > 0)
  }
  // 唯一性
  for i = 0; i < codes.length(); i = i + 1 {
    for j = i + 1; j < codes.length(); j = j + 1 {
      assert_true(codes[i] != codes[j])
    }
  }
}

test "message_of: 包含原始信息" {
  let msg = message_of(NotFound("moonbit-community/yaml"))
  assert_true(msg.contains("moonbit-community/yaml"))
}

test "category_of: 类别名稳定" {
  assert_eq(category_of(Toolchain("v")), "toolchain")
  assert_eq(category_of(InvalidArgument("v")), "invalid_argument")
}
