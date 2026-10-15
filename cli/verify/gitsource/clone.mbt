///|
/// verify/gitsource — 克隆与引用解析（对外部 git 的封装）
///
/// 本文件负责执行 git，因此不可离线单测；解析逻辑在 source.mbt。
///
/// 关于 git 的 TLS 后端：某些 Windows 环境系统级配置了
/// `http.sslBackend = schannel`，而该后端取不到凭据，导致所有 HTTPS 操作
/// 失败（实测报 SEC_E_NO_CREDENTIALS）。本模块的做法是**自动探测**可用的
/// 后端，并**只在本条命令上**通过 `-c` 传入，不修改用户的全局 git 配置。
///
/// 后端以显式参数在调用链上传递，不使用全局可变状态——
/// 这样 `run_verify` 只探测一次，后续所有命令复用同一结论。

///|
/// git 使用的 TLS 后端
pub enum GitBackend {
  /// 使用系统默认配置
  Default
  /// 显式指定 openssl
  Openssl
} derive(Eq, Debug)

///|
/// 克隆相关错误
pub suberror SourceError {
  /// git 命令无法启动
  GitUnavailable
  /// 无法访问远端（网络、TLS、鉴权等原因）
  RemoteUnreachable(String)
  /// 克隆成功但目录里没有 MoonBit 模块清单
  NotAMoonBitModule(String)
}

///|
/// 一次外部命令的结果
pub struct CmdOutput {
  exit_code : Int
  stdout : String
  stderr : String
  elapsed_ms : UInt64
}

///|
/// 单次 git 操作的最大耗时（毫秒）
const GIT_TIMEOUT_MS : Int = 180000

///|
/// 探测 TLS 后端时使用的小仓库（体积小、必定存在）
const PROBE_REMOTE : String = "https://github.com/moonbitlang/x.git"

///|
/// 生成传给 git 的 `-c` 片段
pub fn backend_flag(b : GitBackend) -> String {
  match b {
    Default => ""
    Openssl => "-c http.sslBackend=openssl "
  }
}

///|
/// 把进程层输出转成本模块的 CmdOutput
fn to_cmd_output(out : @proc.Output) -> CmdOutput {
  {
    exit_code: out.exit_code,
    stdout: out.stdout,
    stderr: out.stderr,
    elapsed_ms: out.elapsed_ms,
  }
}

///|
/// 执行一条 git 命令（带上指定的 TLS 后端参数）
pub fn run_git(args : String, workdir : String, backend : GitBackend) -> Result[CmdOutput, SourceError] {
  let cmd = "git " + backend_flag(backend) + args
  match @proc.run(cmd, workdir, GIT_TIMEOUT_MS) {
    Ok(out) => Ok(to_cmd_output(out))
    Err(_) => Err(GitUnavailable)
  }
}

///|
/// 探测可用的 TLS 后端。
///
/// 先用 `Default` 试一次 `git ls-remote`；失败则用 openssl 再试。
/// 两次都失败时返回 Default（后续命令会照常失败并如实上报）。
///
/// 每次全流程只应调用一次，并把结果沿调用链传递。
pub fn detect_backend() -> GitBackend {
  let ok_default = match @proc.run("git ls-remote " + PROBE_REMOTE + " HEAD", "", GIT_TIMEOUT_MS) {
    Ok(out) => out.exit_code == 0
    Err(_) => false
  }
  if ok_default {
    return Default
  }
  let ok_ssl = match
    @proc.run(
      "git -c http.sslBackend=openssl ls-remote " + PROBE_REMOTE + " HEAD",
      "",
      GIT_TIMEOUT_MS,
    ) {
    Ok(out) => out.exit_code == 0
    Err(_) => false
  }
  if ok_ssl {
    Openssl
  } else {
    Default
  }
}

///|
/// 探测结果的可读描述（供 doctor 与报告使用）
pub fn backend_description(b : GitBackend) -> String {
  match b {
    Default => "系统默认（未显式指定后端）"
    Openssl => "openssl（系统默认后端不可用，已按命令显式指定）"
  }
}

///|
/// 探测远端是否可达
pub fn probe_remote(backend : GitBackend) -> Bool {
  match run_git("ls-remote " + PROBE_REMOTE + " HEAD", "", backend) {
    Ok(out) => out.exit_code == 0
    Err(_) => false
  }
}

///|
/// 把仓库克隆到指定目录。
///
/// - `depth` <= 0 表示完整克隆
/// - `git_ref` 非空时只检出该引用
pub fn clone_repo(
  c : Candidate,
  dest : String,
  depth : Int,
  backend : GitBackend,
) -> Result[CmdOutput, SourceError] {
  let depth_arg = if depth > 0 {
    "--depth " + depth.to_string() + " "
  } else {
    ""
  }
  let ref_arg = if c.git_ref.length() > 0 {
    "--branch " + c.git_ref + " "
  } else {
    ""
  }
  let args = "clone --quiet " + depth_arg + ref_arg + c.url + " \"" + dest + "\""
  match run_git(args, "", backend) {
    Ok(out) =>
      if out.exit_code == 0 {
        Ok(out)
      } else {
        Err(RemoteUnreachable(first_reason(out.stderr)))
      }
    Err(e) => Err(e)
  }
}

///|
/// 从 stderr 中提炼一条简短原因（取第一个非空行）
fn first_reason(stderr : String) -> String {
  for line in stderr.split("\n") {
    let t = line.to_owned().trim().to_owned()
    if t.length() > 0 {
      return t
    }
  }
  "未知原因"
}

///|
/// 检查目录是否为 MoonBit 模块（存在 moon.mod / moon.mod.json / moon.work）
pub fn is_moonbit_module(dir : String) -> Bool {
  @fs.is_file(@proc.join_path(dir, "moon.mod")) ||
  @fs.is_file(@proc.join_path(dir, "moon.mod.json")) ||
  @fs.is_file(@proc.join_path(dir, "moon.work"))
}

///|
/// 克隆并校验它确实是 MoonBit 模块。
/// 校验失败时返回 NotAMoonBitModule，由调用方决定是否清理目录。
pub fn clone_module(
  c : Candidate,
  dest : String,
  backend : GitBackend,
) -> Result[CmdOutput, SourceError] {
  match clone_repo(c, dest, 1, backend) {
    Err(e) => Err(e)
    Ok(out) =>
      if is_moonbit_module(dest) {
        Ok(out)
      } else {
        Err(NotAMoonBitModule(c.slug))
      }
  }
}
