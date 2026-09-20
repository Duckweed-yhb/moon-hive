///|
/// verify/gitsource — 候选仓库的标识与解析（纯计算）
///
/// 这个文件只做字符串解析，不执行任何外部命令，因此可以完全离线单测。
/// 真正调用 git 的部分在 clone.mbt 中。

///|
/// 候选仓库在本地工作区里的坐标
pub struct Candidate {
  /// 仓库标识，形如 "owner/repo"（本地目录时为目录名）
  slug : String
  /// 克隆用的 HTTPS 地址
  url : String
  /// 要检出的分支或标签；空串表示远端默认分支
  git_ref : String
  /// 非空表示这是本地目录而非远端仓库——此时直接复制该目录，不联网
  local_path : String
}

///|
/// 解析结果错误
pub suberror CandidateError {
  /// slug 格式不合法（必须恰好是 owner/repo）
  BadSlug(String)
  /// URL 不是受支持的 HTTPS 地址
  BadUrl(String)
  /// 本地路径不存在或不是目录
  BadLocalPath(String)
}

///|
/// 判断输入是否是一个本地目录路径（而非 owner/repo）。
///
/// 识别规则：含路径分隔符、以 `.` 开头（相对路径）、含盘符、或本身是
/// 一个已存在的目录。这样 `C:\proj\pkg`、`./pkg`、`../pkg` 都会走本地路径。
pub fn looks_like_local_path(raw : String) -> Bool {
  let s = raw.trim().to_owned()
  if s.length() == 0 {
    return false
  }
  if s.contains(":\\") || s.has_prefix("./") || s.has_prefix("../") || s.has_prefix("/") {
    return true
  }
  // 已经是存在的目录
  @fs.is_dir(s)
}

///|
/// 从本地目录构造候选仓库。
/// `slug` 取目录名，用于展示与工作区子目录命名。
pub fn from_local(path : String) -> Result[Candidate, CandidateError] {
  let p = path.trim().to_owned()
  if !@fs.is_dir(p) {
    return Err(BadLocalPath(p))
  }
  let slug = basename(p)
  if slug.length() == 0 {
    return Err(BadLocalPath(p))
  }
  Ok({
    slug,
    url: p,
    git_ref: "",
    local_path: p,
  })
}

///|
/// 取出路径的最后一段作为名字
fn basename(p : String) -> String {
  let mut s = p
  while s.length() > 1 && (s.unsafe_get(s.length() - 1) == '/' || s.unsafe_get(s.length() - 1) == '\\') {
    s = s.substring(start=0, end=s.length() - 1)
  }
  let mut last = -1
  for i = 0; i < s.length(); i = i + 1 {
    let c = s.unsafe_get(i)
    if c == '/' || c == '\\' {
      last = i
    }
  }
  if last < 0 {
    s
  } else if last == s.length() - 1 {
    ""
  } else {
    s.substring(start=last + 1, end=s.length())
  }
}

///|
/// 是否为本地目录候选
pub fn is_local(c : Candidate) -> Bool {
  c.local_path.length() > 0
}

///|
/// 宽松规范化：去掉首尾空白、去掉末尾的 ".git"、去掉首尾斜杠
pub fn normalize_slug(raw : String) -> String {
  let mut s = raw.trim().to_owned()
  // 去掉可能的协议前缀与域名前缀
  if s.has_prefix("https://github.com/") {
    s = s.substring(start=19, end=s.length())
  } else if s.has_prefix("http://github.com/") {
    s = s.substring(start=18, end=s.length())
  } else if s.has_prefix("github.com/") {
    s = s.substring(start=11, end=s.length())
  }
  if s.has_suffix(".git") {
    s = s.substring(start=0, end=s.length() - 4)
  }
  while s.length() > 0 && s.unsafe_get(s.length() - 1) == '/' {
    s = s.substring(start=0, end=s.length() - 1)
  }
  while s.length() > 0 && s.unsafe_get(0) == '/' {
    s = s.substring(start=1, end=s.length())
  }
  s
}

///|
/// 判断 slug 是否形如 owner/repo 且两侧都非空、不含多余斜杠
pub fn is_valid_slug(slug : String) -> Bool {
  if slug.length() == 0 {
    return false
  }
  let mut slashes = 0
  let mut idx = -1
  for i = 0; i < slug.length(); i = i + 1 {
    if slug.unsafe_get(i) == '/' {
      slashes = slashes + 1
      idx = i
    }
  }
  if slashes != 1 {
    return false
  }
  idx > 0 && idx < slug.length() - 1
}

///|
/// 从 slug 构造候选仓库
pub fn from_slug(raw : String) -> Result[Candidate, CandidateError] {
  let slug = normalize_slug(raw)
  if !is_valid_slug(slug) {
    return Err(BadSlug(raw))
  }
  Ok({ slug, url: "https://github.com/" + slug + ".git", git_ref: "", local_path: "" })
}

///|
/// 从完整 HTTPS URL 构造候选仓库
pub fn from_url(url : String) -> Result[Candidate, CandidateError] {
  if !url.has_prefix("https://") {
    return Err(BadUrl(url))
  }
  match from_slug(url) {
    Ok(c) => Ok(c)
    Err(_) => Err(BadUrl(url))
  }
}

///|
/// 指定检出引用（分支 / 标签 / 提交）
pub fn with_ref(c : Candidate, git_ref : String) -> Candidate {
  { slug: c.slug, url: c.url, git_ref, local_path: c.local_path }
}

///|
/// 把 slug 转成安全的目录名（去掉 '/'，避免产生子目录）
pub fn to_dir_name(slug : String) -> String {
  let b = StringBuilder()
  for c in slug {
    if c == '/' || c == '\\' || c == ':' {
      b.write_string("__")
    } else {
      b.write_char(c)
    }
  }
  b.to_string()
}

// ---------- 单元测试 ----------

test "normalize_slug 去掉协议、域名、.git 与斜杠" {
  assert_eq(normalize_slug("moonbitlang/x"), "moonbitlang/x")
  assert_eq(normalize_slug("moonbitlang/x.git"), "moonbitlang/x")
  assert_eq(normalize_slug("https://github.com/moonbitlang/x"), "moonbitlang/x")
  assert_eq(normalize_slug("https://github.com/moonbitlang/x.git"), "moonbitlang/x")
  assert_eq(normalize_slug("  moonbitlang/x  "), "moonbitlang/x")
  assert_eq(normalize_slug("/moonbitlang/x/"), "moonbitlang/x")
}

test "is_valid_slug 校验形态" {
  assert_true(is_valid_slug("a/b"))
  assert_true(is_valid_slug("moonbit-community/yaml"))
  assert_false(is_valid_slug(""))
  assert_false(is_valid_slug("justrepo"))
  assert_false(is_valid_slug("/repo"))
  assert_false(is_valid_slug("owner/"))
  assert_false(is_valid_slug("a/b/c"))
}

test "from_slug 构造候选仓库" {
  match from_slug("moonbitlang/x") {
    Ok(c) => {
      assert_eq(c.slug, "moonbitlang/x")
      assert_eq(c.url, "https://github.com/moonbitlang/x.git")
      assert_eq(c.git_ref, "")
    }
    Err(_) => fail("应解析成功")
  }
}

test "from_slug 接受完整 URL 形式" {
  match from_slug("https://github.com/moonbitlang/x.git") {
    Ok(c) => assert_eq(c.slug, "moonbitlang/x")
    Err(_) => fail("应解析成功")
  }
}

test "from_slug 拒绝非法输入" {
  assert_true(match from_slug("no-slash") {
    Err(BadSlug(_)) => true
    _ => false
  })
  assert_true(match from_slug("a/b/c") {
    Err(BadSlug(_)) => true
    _ => false
  })
}

test "from_url 只接受 https" {
  assert_true(match from_url("http://github.com/a/b") {
    Err(BadUrl(_)) => true
    _ => false
  })
  assert_true(match from_url("git://github.com/a/b") {
    Err(BadUrl(_)) => true
    _ => false
  })
  match from_url("https://github.com/a/b") {
    Ok(c) => assert_eq(c.slug, "a/b")
    Err(_) => fail("https 应接受")
  }
}

test "with_ref 保留其余字段" {
  let c = match from_slug("a/b") {
    Ok(c) => c
    Err(_) => fail("应解析成功")
  }
  let c2 = with_ref(c, "v1.2.3")
  assert_eq(c2.git_ref, "v1.2.3")
  assert_eq(c2.slug, "a/b")
  assert_eq(c2.url, "https://github.com/a/b.git")
}

test "to_dir_name 去掉路径分隔符" {
  assert_eq(to_dir_name("moonbitlang/x"), "moonbitlang__x")
  assert_eq(to_dir_name("plain"), "plain")
  assert_eq(to_dir_name("a:b"), "a__b")
}
