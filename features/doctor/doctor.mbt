///|
/// features/doctor — 环境自检
///
/// 为什么需要它：MoonHive 的验证能力依赖外部工具（git、moon 工具链）和
/// 临时目录。任何一环不满足，验证结果都会失真——最危险的是"看起来失败，
/// 其实是我的环境有问题"。doctor 把这些前置条件全部显式化。
///
/// 实测背景：开发环境里系统 git 配置 `http.sslBackend = schannel`，
/// 导致所有 HTTPS 操作报 SEC_E_NO_CREDENTIALS。doctor 必须能检出它。

///|
/// 单项检查的结论
pub enum Status {
  Ok
  Warn
  Fail
} derive(Eq)

///|
/// 一条检查记录
pub struct Check {
  name : String
  status : Status
  detail : String
}

///|
/// 自检汇总
pub struct Report {
  checks : Array[Check]
}

///|
/// 单项超时（毫秒）——自检必须快速返回
const PROBE_TIMEOUT_MS : Int = 20000

///|
/// 运行一条命令并返回 (退出码, stdout, stderr)
fn probe(cmd : String) -> (Int, String, String) {
  match @proc.run(cmd, "", PROBE_TIMEOUT_MS) {
    Ok(out) => (out.exit_code, out.stdout, out.stderr)
    Err(_) => (-1, "", "")
  }
}

///|
/// 取命令输出的第一行（已去掉首尾空白）
fn first_line(s : String) -> String {
  for line in s.split("\n") {
    let t = line.to_owned().trim().to_owned()
    if t.length() > 0 {
      return t
    }
  }
  ""
}

///|
/// 生成一条水平分隔线
fn rule(n : Int) -> String {
  let b = StringBuilder()
  for _ in 0..<n {
    b.write_string("─")
  }
  b.to_string()
}

///|
/// 检查 1：moon 工具链是否可用，版本是多少
fn check_moon() -> Check {
  let (code, stdout, _) = probe("moon version")
  if code != 0 {
    return {
      name: "MoonBit 工具链",
      status: Fail,
      detail: "找不到可执行的 moon；请确认已安装并将 ~/.moon/bin 加入 PATH",
    }
  }
  let version = first_line(stdout)
  if version.length() == 0 {
    return { name: "MoonBit 工具链", status: Warn, detail: "moon 可执行但版本输出为空" }
  }
  { name: "MoonBit 工具链", status: Ok, detail: version }
}

///|
/// 检查 2：git 是否可用（仓库获取与注册表访问都依赖它）
fn check_git() -> Check {
  let (code, stdout, _) = probe("git --version")
  if code != 0 {
    return {
      name: "git",
      status: Fail,
      detail: "找不到可执行的 git；无法获取待验证的仓库",
    }
  }
  { name: "git", status: Ok, detail: first_line(stdout) }
}

///|
/// 检查 3：git 的 TLS 后端是否能正常工作
///
/// 这是本环境实测踩到的坑：系统配置 schannel 时，
/// 所有 HTTPS 操作会失败并报 SEC_E_NO_CREDENTIALS。
fn check_git_tls() -> Check {
  let (code, _, stderr) = probe("git ls-remote https://github.com/moonbitlang/x.git HEAD")
  if code == 0 {
    return { name: "git TLS 连通性", status: Ok, detail: "可访问 github.com（HTTPS 正常）" }
  }
  // 二次尝试：显式切到 openssl 后端
  let (code2, _, _) = probe(
    "git -c http.sslBackend=openssl ls-remote https://github.com/moonbitlang/x.git HEAD",
  )
  if code2 == 0 {
    return {
      name: "git TLS 连通性",
      status: Warn,
      detail: "当前 git 配置的 TLS 后端不可用，但 openssl 后端可用。" +
        "建议执行: git config --global http.sslBackend openssl",
    }
  }
  {
    name: "git TLS 连通性",
    status: Fail,
    detail: "无法访问 github.com；stderr 片段: " + first_line(stderr),
  }
}

///|
/// 检查 4：临时目录是否可写（验证工作区依赖它）
fn check_temp_dir() -> Check {
  let dir = @proc.temp_dir()
  if dir.length() == 0 {
    return { name: "临时目录", status: Fail, detail: "无法确定临时目录路径" }
  }
  let probe_file = @proc.join_path(dir, "moonhive-doctor-probe.tmp")
  // 用 shell 写一个探针文件再删除，避免额外增加 C FFI 面
  let write_cmd = "echo moonhive > \"" + probe_file + "\""
  let (code, _, _) = probe(write_cmd)
  if code != 0 {
    return { name: "临时目录", status: Fail, detail: dir + " 不可写（验证工作区无法创建）" }
  }
  let existed = @fs.read_text(probe_file).length() > 0
  let removed = @fs.remove_file(probe_file)
  if !existed {
    return { name: "临时目录", status: Warn, detail: dir + " 可写但回读失败" }
  }
  if !removed {
    return { name: "临时目录", status: Warn, detail: dir + " 可写，但清理探针文件失败" }
  }
  { name: "临时目录", status: Ok, detail: dir }
}

///|
/// 运行全部自检
pub fn run_doctor() -> Report {
  {
    checks: [
      check_moon(),
      check_git(),
      check_git_tls(),
      check_temp_dir(),
    ],
  }
}

///|
/// 统计某个状态的检查数量
pub fn count_status(report : Report, status : Status) -> Int {
  let mut n = 0
  for c in report.checks {
    if c.status == status {
      n = n + 1
    }
  }
  n
}

///|
/// 是否存在失败项（决定退出码）
pub fn has_failure(report : Report) -> Bool {
  count_status(report, Fail) > 0
}

///|
/// 渲染为人类可读文本
pub fn render(report : Report) -> String {
  let buf = StringBuilder()
  buf.write_string("MoonHive 环境自检\n")
  buf.write_string(rule(52))
  buf.write_string("\n")
  for c in report.checks {
    let mark = match c.status {
      Ok => "[ OK ]"
      Warn => "[WARN]"
      Fail => "[FAIL]"
    }
    buf.write_string(mark + " " + c.name + "\n")
    buf.write_string("       " + c.detail + "\n")
  }
  buf.write_string(rule(52))
  buf.write_string("\n")
  let ok = count_status(report, Ok)
  let warn = count_status(report, Warn)
  let fail = count_status(report, Fail)
  buf.write_string(
    "结果: " +
    ok.to_string() +
    " 项通过, " +
    warn.to_string() +
    " 项警告, " +
    fail.to_string() +
    " 项失败\n",
  )
  if fail > 0 {
    buf.write_string("请先解决失败项，否则验证结论不可信。\n")
  } else if warn > 0 {
    buf.write_string("存在警告项，验证可以继续，但结论中会记录该限制。\n")
  }
  buf.to_string()
}

// ---------- 单元测试（不依赖真实环境的纯逻辑） ----------

test "count_status: 空报告全为 0" {
  let r = { checks: [] }
  assert_eq(count_status(r, Ok), 0)
  assert_eq(count_status(r, Fail), 0)
  assert_false(has_failure(r))
}

test "count_status: 分类计数正确" {
  let r = {
    checks: [
      { name: "a", status: Ok, detail: "" },
      { name: "b", status: Ok, detail: "" },
      { name: "c", status: Warn, detail: "" },
      { name: "d", status: Fail, detail: "" },
    ],
  }
  assert_eq(count_status(r, Ok), 2)
  assert_eq(count_status(r, Warn), 1)
  assert_eq(count_status(r, Fail), 1)
  assert_true(has_failure(r))
}

test "has_failure: 只有警告时为 false" {
  let r = {
    checks: [{ name: "a", status: Warn, detail: "x" }],
  }
  assert_false(has_failure(r))
}

test "render: 包含所有检查名与结论行" {
  let r = {
    checks: [
      { name: "MoonBit 工具链", status: Ok, detail: "moon 1.0" },
      { name: "git", status: Warn, detail: "有问题" },
    ],
  }
  let text = render(r)
  assert_true(text.contains("MoonBit 工具链"))
  assert_true(text.contains("git"))
  assert_true(text.contains("[ OK ]"))
  assert_true(text.contains("[WARN]"))
  assert_true(text.contains("1 项通过"))
}

test "render: 有失败时给出提示" {
  let r = {
    checks: [{ name: "x", status: Fail, detail: "y" }],
  }
  assert_true(render(r).contains("验证结论不可信"))
}
