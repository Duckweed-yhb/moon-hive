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
  /// 命令执行超过超时上限，子进程已被强杀
  TimedOut
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
extern "C" fn proc_read_file_raw(path : String) -> String = "proc_read_file"

#borrow(path)
extern "C" fn proc_remove_file_raw(path : String) -> Int = "proc_remove_file"

extern "C" fn proc_last_elapsed_ms_raw() -> UInt64 = "proc_last_elapsed_ms"

extern "C" fn proc_last_os_error_raw() -> Int = "proc_last_os_error"

extern "C" fn proc_exit_raw(code : Int) -> Unit = "proc_exit"

///|
/// 最近一次进程层失败对应的操作系统错误码（诊断用）。
/// Windows 上是 GetLastError() 的值，其他平台是 errno。
pub fn last_os_error() -> Int {
  proc_last_os_error_raw()
}

// ---------- 错误码映射 ----------

///|
/// 把 C 侧错误码翻译成类型化错误。
///
/// C 侧约定（必须与真实退出码区分开）：
///   -1001 空命令 / -1002 无法创建管道 / -1003 stderr 文件不可写 / -1004 内存不足 / -1005 超时
fn map_error_code(code : Int) -> ProcError? {
  if code == -1001 {
    Some(EmptyCommand)
  } else if code == -1002 {
    Some(SpawnFailed)
  } else if code == -1003 {
    Some(StderrCaptureFailed(code))
  } else if code == -1004 {
    Some(OutOfMemory)
  } else if code == -1005 {
    Some(TimedOut)
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
    dir + path_separator() + name
  }
}

/// 当前平台的路径分隔符：Windows 用反斜杠，Linux/macOS 及 Wasm/JS 用正斜杠
#cfg(platform="windows")
fn path_separator() -> String {
  "\\"
}

#cfg(not(platform="windows"))
fn path_separator() -> String {
  "/"
}

// ---------- 公开 API ----------

///|
/// 执行命令并捕获输出。
///
/// - `cmd`：要执行的命令（经由 shell）
/// - `workdir`：工作目录；空串表示继承当前目录
/// - `timeout_ms`：超时上限（毫秒）；超过后 C 层强杀子进程并返回 `TimedOut`
///
/// 非零退出码**不算错误**——编译器报错就是非零退出码，是正常结果。
pub fn run(cmd : String, workdir : String, timeout_ms : Int) -> Result[Output, ProcError] {
  let stamp = @env.now()
  let prefix = "moonhive-" + stamp.to_string()
  let tmp = temp_dir()
  let out_file = join_path(tmp, prefix + "-out.txt")
  let err_file = join_path(tmp, prefix + "-err.txt")
  let code = proc_run_capture(cmd, workdir, out_file, err_file, timeout_ms)
  let stdout = proc_read_file_raw(out_file)
  let stderr = proc_read_file_raw(err_file)
  ignore(proc_remove_file_raw(out_file))
  ignore(proc_remove_file_raw(err_file))
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
/// 以指定退出码终止进程。CLI 用它把错误契约映射成 shell 可见的退出码。
/// 正常路径调用后不会返回。
pub fn exit_with(code : Int) -> Unit {
  proc_exit_raw(code)
}

#cfg(platform="windows")
test "proc 超时强杀（Windows：ping 无限挂起 → TimedOut）" {
  // ping -t 无限挂起；800ms 超时后必须被 C 层强杀并返回 TimedOut，
  // 而不是永久阻塞（守护 proc 层超时不被改回 v1 的"尽力而为"）。
  let r = run("ping -t 127.0.0.1", "", 800)
  match r {
    Err(TimedOut) => ()
    Err(e) => fail("期望 TimedOut，实际其他错误")
    Ok(_) => fail("期望超时，实际正常返回")
  }
}

#cfg(not(platform="windows"))
test "proc 超时强杀（POSIX：sleep 挂起 → TimedOut）" {
  // sleep 100 挂起 100 秒；800ms 超时后必须被 C 层强杀并返回 TimedOut。
  let r = run("sleep 100", "", 800)
  match r {
    Err(TimedOut) => ()
    Err(e) => fail("期望 TimedOut，实际其他错误")
    Ok(_) => fail("期望超时，实际正常返回")
  }
}
