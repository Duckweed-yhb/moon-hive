///|
/// platform/proc — 子进程执行与文件读写（原生后端）
///
/// 这是 MoonHive 唯一允许出现 C FFI 的包之一（另一个是 platform/fs）。
/// 设计边界：上层模块只看到 Result[Output, ProcError]，看不到任何 C 类型。
///
/// 为什么需要它：`moonbitlang/core` 不提供文件系统与进程模块，
/// 而"用真实工具链验证包能不能用"必须能起进程、读文件。

///|
/// 进程执行结果
pub struct Output {
  /// 退出码；0 表示成功。注意非零退出码是正常结果，不是错误。
  exit_code : Int
  /// 标准输出（完整内容）
  stdout : String
  /// 标准错误（编译器诊断通常在这里）
  stderr : String
  /// 实际耗时（毫秒）
  elapsed_ms : UInt64
}

///|
/// 进程层错误
pub suberror ProcError {
  /// 命令为空
  EmptyCommand
  /// 无法创建管道（命令不可执行 / 系统资源不足）
  SpawnFailed
  /// 内存分配失败
  OutOfMemory
  /// stderr 重定向文件不可写
  StderrCaptureFailed(Int)
}

// ---------- C FFI 声明 ----------

#borrow(cmd, workdir, out_stdout, out_stderr)
extern "C" fn proc_run_capture(
  cmd : String,
  workdir : String,
  out_stdout : String,
  out_stderr : String,
  timeout_ms : Int
) -> Int = "proc_run_capture"

#borrow(path)
extern "C" fn fs_read_text_raw(path : String) -> String = "fs_read_text"

#borrow(path)
extern "C" fn fs_remove_raw(path : String) -> Int = "fs_remove"

extern "C" fn proc_last_elapsed_ms_raw() -> UInt64 = "proc_last_elapsed_ms"

extern "C" fn proc_exit_raw(code : Int) -> Unit = "proc_exit"

// ---------- 错误码映射 ----------

///|
/// 把 C 侧错误码翻译成类型化错误。
/// C 侧约定：-1 popen 失败，-2 stderr 文件失败，-3 内存失败，-4 空命令。
fn map_error_code(code : Int) -> ProcError? {
  if code == -1 {
    Some(SpawnFailed)
  } else if code == -2 {
    Some(StderrCaptureFailed(code))
  } else if code == -3 {
    Some(OutOfMemory)
  } else if code == -4 {
    Some(EmptyCommand)
  } else {
    None
  }
}

// ---------- 路径工具 ----------

///|
/// 当前平台的临时目录。优先读环境变量，取不到则退回当前目录。
pub fn temp_dir() -> String {
  match @env.get_env_var("TEMP") {
    Some(v) =>
      if v.length() > 0 {
        v
      } else {
        fallback_temp_dir()
      }
    None => fallback_temp_dir()
  }
}

///|
fn fallback_temp_dir() -> String {
  match @env.get_env_var("TMPDIR") {
    Some(v) =>
      if v.length() > 0 {
        v
      } else {
        match @env.current_dir() {
          Some(d) => d
          None => "."
        }
      }
    None =>
      match @env.current_dir() {
        Some(d) => d
        None => "."
      }
  }
}

///|
/// 用当前平台分隔符拼接路径。
pub fn join_path(dir : String, name : String) -> String {
  if dir.length() == 0 {
    return name
  }
  let mut ends_with_sep = false
  for c in dir {
    if c == '/' || c == '\\' {
      ends_with_sep = true
    } else {
      ends_with_sep = false
    }
  }
  if ends_with_sep {
    dir + name
  } else {
    dir + "\\" + name
  }
}

// ---------- 公开 API ----------

///|
/// 执行命令并捕获输出。
///
/// - `cmd`：要执行的命令（经由 shell）
/// - `workdir`：工作目录；空串表示继承当前目录
/// - `timeout_ms`：超时上限（v1 记录并由调用方判定）
///
/// 非零退出码**不算错误**——编译器报错就是非零退出码，是正常结果。
pub fn run(cmd : String, workdir : String, timeout_ms : Int) -> Result[Output, ProcError] {
  let stamp = @env.now()
  let prefix = "moonhive-" + stamp.to_string()
  let tmp = temp_dir()
  let out_file = join_path(tmp, prefix + "-out.txt")
  let err_file = join_path(tmp, prefix + "-err.txt")
  let code = proc_run_capture(cmd, workdir, out_file, err_file, timeout_ms)
  let stdout = fs_read_text_raw(out_file)
  let stderr = fs_read_text_raw(err_file)
  ignore(fs_remove_raw(out_file))
  ignore(fs_remove_raw(err_file))
  match map_error_code(code) {
    Some(err) => Err(err)
    None =>
      Ok({
        exit_code: code,
        stdout,
        stderr,
        elapsed_ms: proc_last_elapsed_ms_raw(),
      })
  }
}

///|
/// 便捷封装：只关心退出码是否为 0。
pub fn run_ok(cmd : String, workdir : String, timeout_ms : Int) -> Bool {
  match run(cmd, workdir, timeout_ms) {
    Ok(out) => out.exit_code == 0
    Err(_) => false
  }
}

///|
/// 读取文本文件内容。文件不存在或不可读时返回空串。
pub fn read_text(path : String) -> String {
  fs_read_text_raw(path)
}

///|
/// 删除文件。返回是否成功。
pub fn remove_file(path : String) -> Bool {
  fs_remove_raw(path) == 0
}

///|
/// 以指定退出码终止进程。CLI 用它把错误契约映射成 shell 可见的退出码。
/// 正常路径调用后不会返回。
pub fn exit_with(code : Int) -> Unit {
  proc_exit_raw(code)
}
