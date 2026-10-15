///|
/// platform/http — 本地 HTTP 服务层
///
/// 只有本包（与 platform/proc、platform/fs）允许出现 C FFI。
/// 职责：在 127.0.0.1 上服务一个本地目录（静态文件 + 两个只读 API），
/// 供浏览器打开 MoonHive 验证仪表盘。

///|
/// 服务器错误码（对应 C 层 http_serve 的返回值）
pub enum ServeError {
  /// Winsock 初始化失败
  WsaInit
  /// 创建 socket 失败
  Socket
  /// 端口被占用或绑定失败
  Bind
  /// 监听失败
  Listen
  /// accept 循环异常退出
  Accept
}

///|
/// 启动本地 HTTP 服务并阻塞，直到进程终止。
///
/// - `root`：服务根目录（报告目录），可含中文路径
/// - `port`：监听端口（默认 8080，仅监听 127.0.0.1）
///
/// 正常路径下不返回（进程被 Ctrl+C 终止）；异常返回错误码。
pub fn serve(root : String, port : Int) -> ServeError? {
  let code = http_serve_ffi(root, port)
  if code == 0 {
    return None
  }
  if code == -1001 {
    return Some(WsaInit)
  } else if code == -1002 {
    return Some(Socket)
  } else if code == -1003 {
    return Some(Bind)
  } else if code == -1004 {
    return Some(Listen)
  } else {
    return Some(Accept)
  }
}

#borrow(root)
extern "C" fn http_serve_ffi(root : String, port : Int) -> Int = "http_serve"

// ---------- 纯计算工具（可离线单测） ----------

///|
/// 默认端口
pub fn default_port() -> Int {
  8080
}

///|
/// 端口合法性：1024–65535（本地服务不需要特权端口）
pub fn valid_port(p : Int) -> Bool {
  p >= 1024 && p <= 65535
}

///|
/// 最后一个 '.' 的位置；没有返回 None
fn last_dot_idx(s : String) -> Int? {
  let mut found = None
  let mut i = 0
  for c in s {
    if c == '.' {
      found = Some(i)
    }
    i = i + 1
  }
  found
}

///|
/// 按文件扩展名判断 MIME 类型（与 C 层一致，供测试对照）
pub fn mime_of(path : String) -> String {
  match last_dot_idx(path) {
    None => "application/octet-stream"
    Some(i) => {
      let ext = path[i:].to_owned()
      if ext == ".html" {
        "text/html; charset=utf-8"
      } else if ext == ".css" {
        "text/css; charset=utf-8"
      } else if ext == ".js" {
        "application/javascript"
      } else if ext == ".json" {
        "application/json; charset=utf-8"
      } else if ext == ".svg" {
        "image/svg+xml"
      } else if ext == ".png" {
        "image/png"
      } else if ext == ".md" {
        "text/markdown; charset=utf-8"
      } else {
        "application/octet-stream"
      }
    }
  }
}

///|
/// 报告文件名是否安全（只允许字母数字._-，禁止路径穿越）
pub fn safe_report_name(name : String) -> Bool {
  if name.length() == 0 || name.contains("/") || name.contains("\\") || name.contains("..") {
    return false
  }
  for c in name {
    let ok =
      (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') ||
        c == '.' || c == '_' || c == '-'
    if !ok {
      return false
    }
  }
  true
}

///|
/// 相对 URL 规范化（与 C 层约定一致）：拒绝 `..` 与空路径
pub fn normalize_rel(url : String) -> String? {
  if !url.has_prefix("/") {
    return None
  }
  let parts = url[1:].to_owned().split("/")
  let out : Array[String] = []
  for p in parts {
    let s = p.to_owned()
    if s == "" || s == "." {
      continue
    }
    if s == ".." {
      return None
    }
    out.push(s)
  }
  if out.length() == 0 {
    return None
  }
  Some(out.join("\\"))
}

// ---------- 单元测试 ----------

test "valid_port 拒绝特权端口与越界" {
  assert_true(valid_port(8080))
  assert_true(valid_port(65535))
  assert_false(valid_port(80))
  assert_false(valid_port(1023))
  assert_false(valid_port(65536))
  assert_false(valid_port(0))
}

test "mime_of 覆盖常见扩展名" {
  assert_eq(mime_of("index.html"), "text/html; charset=utf-8")
  assert_eq(mime_of("app.js"), "application/javascript")
  assert_eq(mime_of("report.json"), "application/json; charset=utf-8")
  assert_eq(mime_of("style.css"), "text/css; charset=utf-8")
  assert_eq(mime_of("noext"), "application/octet-stream")
}

test "safe_report_name 拒绝路径穿越" {
  assert_true(safe_report_name("2026-09-24.json"))
  assert_true(safe_report_name("a_b-c.json"))
  assert_false(safe_report_name("../report.json"))
  assert_false(safe_report_name("a/b.json"))
  assert_false(safe_report_name("a\\b.json"))
  assert_false(safe_report_name(".."))
  assert_false(safe_report_name(""))
}

test "normalize_rel 规范化与拒绝穿越" {
  match normalize_rel("/api/reports") {
    Some(r) => assert_eq(r, "api\\reports")
    None => fail("合法路径应通过")
  }
  match normalize_rel("/index.html") {
    Some(r) => assert_eq(r, "index.html")
    None => fail("合法路径应通过")
  }
  assert_eq(normalize_rel("/a/../b"), None)
  assert_eq(normalize_rel("/"), None)
  assert_eq(normalize_rel("index.html"), None)
}
