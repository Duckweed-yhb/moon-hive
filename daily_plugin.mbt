///|
/// 每日 GitHub 项目投喂插件：解析 GitHub API 返回的项目 JSON，输出今日推荐卡片，
/// 支持收藏管理（keep）与 Markdown 导出（export）
///
/// 数据来源：GitHub Search API（由配套脚本 daily.ps1 拉取并精简字段后作为参数传入）
/// 输入格式：JSON 数组，字段沿用 GitHub API 原始字段名：
///   [{ "name": "...", "description": "...", "html_url": "...",
///      "stargazers_count": 123, "language": "MoonBit", "updated_at": "2026-09-01T00:00:00Z" }]
pub(all) struct DailyPlugin {}

///|
pub impl Plugin for DailyPlugin with name(_self) {
  "daily"
}

///|
pub impl Plugin for DailyPlugin with description(_self) {
  "每日 GitHub 项目投喂：digest 推荐 / keep 收藏 / export 导出 Markdown"
}

///|
pub impl Plugin for DailyPlugin with execute(_self, command, args) {
  match command {
    "digest" => {
      if args.length() < 1 {
        "用法: moon run cmd/main daily digest '<项目JSON>'\n支持直接 JSON 或 Base64 编码的 JSON"
      } else {
        digest(args[0])
      }
    }
    "keep" => {
      if args.length() < 2 {
        "用法: moon run cmd/main daily keep <项目JSON> <保留编号> [旧收藏JSON]\n示例: daily keep '<json>' '1,3'"
      } else {
        let old = if args.length() >= 3 { args[2] } else { "" }
        keep(args[0], args[1], old)
      }
    }
    "export" => {
      if args.length() < 1 {
        "用法: moon run cmd/main daily export <收藏JSON>"
      } else {
        export_md(args[0])
      }
    }
    _ => "未知命令: \{command}（支持: digest / keep / export）"
  }
}

///| 一个 GitHub 项目的精简信息（推荐用）
pub(all) struct Repo {
  name : String
  desc : String
  url : String
  stars : Int
  lang : String
  updated : String
}

///| 一个已收藏的项目（收藏清单用）
pub(all) struct Faved {
  name : String
  desc : String
  url : String
  stars : Int
  lang : String
  saved : String
}

///| 解码输入：直接 JSON（以 [ 开头）或 Base64 编码的 JSON
fn decode_input(json_str : String) -> Result[String, String] {
  if json_str.has_prefix("[") {
    Ok(json_str)
  } else {
    let dec = base64_decode(json_str)
    if dec.has_prefix("（解码失败") || dec == "" {
      Err("（参数解析失败：既不是 JSON 也不是有效的 Base64）")
    } else {
      Ok(dec)
    }
  }
}

///| 解析项目 JSON 数组为 Repo 列表
fn parse_repo_list(json_str : String) -> Result[Array[Repo], String] {
  let input = match decode_input(json_str) {
    Ok(s) => s
    Err(m) => return Err(m)
  }
  let items = try {
    @json.parse(input)
  } catch {
    err => return Err("（解析失败：\{err}）")
  }
  if items is Array(list) {
    let repos = []
    for item in list {
      repos.push(Repo::{
        name: get_str(item, "name"),
        desc: get_str(item, "description"),
        url: get_str(item, "html_url"),
        stars: get_int(item, "stargazers_count"),
        lang: get_str(item, "language"),
        updated: get_str(item, "updated_at"),
      })
    }
    Ok(repos)
  } else {
    Err("（解析失败：期望 JSON 数组，如 [{...},{...}]）")
  }
}

///| 解析收藏 JSON 数组为 Faved 列表
pub fn parse_fav_list(json_str : String) -> Result[Array[Faved], String] {
  let input = match decode_input(json_str) {
    Ok(s) => s
    Err(m) => return Err(m)
  }
  let items = try {
    @json.parse(input)
  } catch {
    err => return Err("（解析失败：\{err}）")
  }
  if items is Array(list) {
    let favs = []
    for item in list {
      favs.push(Faved::{
        name: get_str(item, "name"),
        desc: get_str(item, "desc"),
        url: get_str(item, "url"),
        stars: get_int(item, "stars"),
        lang: get_str(item, "lang"),
        saved: get_str(item, "saved"),
      })
    }
    Ok(favs)
  } else {
    Err("（解析失败：期望 JSON 数组，如 [{...},{...}]）")
  }
}

///| 解析并输出今日推荐卡片（输入支持直接 JSON 或 Base64 编码 JSON）
pub fn digest(json_str : String) -> String {
  match parse_repo_list(json_str) {
    Ok(repos) => render_cards(repos)
    Err(msg) => msg
  }
}

///| 收藏管理：从推荐列表中按编号选取项目，与旧收藏合并（按 url 去重），输出新收藏 JSON
pub fn keep(repos_str : String, ids_str : String, old_str : String) -> String {
  let repos = match parse_repo_list(repos_str) {
    Ok(r) => r
    Err(msg) => return msg
  }
  let ids = parse_ids(ids_str)
  if ids.length() == 0 {
    return "（没有要保留的项目：编号格式如 1,3）"
  }
  let old = if old_str == "" {
    []
  } else {
    match parse_fav_list(old_str) {
      Ok(f) => f
      Err(msg) => return msg
    }
  }
  // 收集选中的项目（去重编号、过滤越界）
  let selected = []
  let seen = []
  for id in ids {
    if id >= 1 && id <= repos.length() && !seen.contains(id) {
      seen.push(id)
      selected.push(repos[id - 1])
    }
  }
  if selected.length() == 0 {
    return "（编号超出范围：有效 1..\{repos.length()}）"
  }
  // 合并：旧收藏全部保留，新选中项目 url 已存在则跳过（去重）
  let favs = []
  for f in old {
    favs.push(f)
  }
  let today = millis_to_date(@env.now())
  for s in selected {
    let mut dup = false
    for f in favs {
      if f.url == s.url {
        dup = true
        break
      }
    }
    if !dup {
      favs.push(Faved::{
        name: s.name,
        desc: s.desc,
        url: s.url,
        stars: s.stars,
        lang: s.lang,
        saved: today,
      })
    }
  }
  favs_to_json(favs)
}

///| 导出收藏为 Markdown 清单（按星数降序）
pub fn export_md(fav_str : String) -> String {
  let favs = match parse_fav_list(fav_str) {
    Ok(f) => f
    Err(msg) => return msg
  }
  if favs.length() == 0 {
    return "（收藏为空：还没有保留任何项目）"
  }
  // 简单选择排序：按星数降序
  let sorted = favs
  let mut i = 0
  while i < sorted.length() {
    let mut best = i
    let mut j = i + 1
    while j < sorted.length() {
      if sorted[j].stars > sorted[best].stars {
        best = j
      }
      j = j + 1
    }
    if best != i {
      let tmp = sorted[i]
      sorted[i] = sorted[best]
      sorted[best] = tmp
    }
    i = i + 1
  }
  let buf = StringBuilder()
  buf.write_string("# 我的 GitHub 项目收藏（\{sorted.length()} 个）\n\n")
  for f in sorted {
    buf.write_string("- **[\{f.name}](\{f.url})** ⭐\{f.stars}")
    if f.lang != "" {
      buf.write_string(" [\{f.lang}]")
    }
    buf.write_string("（\{f.saved} 收藏）\n")
    if f.desc != "" {
      buf.write_string("  \{f.desc}\n")
    }
    buf.write_string("\n")
  }
  buf.to_string()
}

///| 把收藏列表渲染为 JSON 字符串
fn favs_to_json(favs : Array[Faved]) -> String {
  let buf = StringBuilder()
  buf.write_string("[")
  let mut i = 0
  while i < favs.length() {
    let f = favs[i]
    buf.write_string(
      "{\"name\":\"\{escape_json(f.name)}\",\"desc\":\"\{escape_json(f.desc)}\",\"url\":\"\{escape_json(f.url)}\",\"stars\":\{f.stars},\"lang\":\"\{escape_json(f.lang)}\",\"saved\":\"\{escape_json(f.saved)}\"}",
    )
    if i < favs.length() - 1 {
      buf.write_string(",")
    }
    i = i + 1
  }
  buf.write_string("]")
  buf.to_string()
}

///| 把项目列表渲染成终端推荐卡片
fn render_cards(repos : Array[Repo]) -> String {
  if repos.length() == 0 {
    return "（没有可推荐的项目）"
  }
  let buf = StringBuilder()
  buf.write_string("今日推荐（\{repos.length()} 个项目）\n")
  buf.write_string(dash_line(46) + "\n")
  let mut i = 0
  while i < repos.length() {
    let r = repos[i]
    buf.write_string("[\{i + 1}] \{r.name}  ⭐\{r.stars}")
    if r.lang != "" {
      buf.write_string("  [\{r.lang}]")
    }
    buf.write_string("\n")
    if r.desc != "" {
      buf.write_string("    " + r.desc + "\n")
    }
    if r.url != "" {
      buf.write_string("    " + r.url + "\n")
    }
    if r.updated != "" {
      buf.write_string("    更新: " + r.updated + "\n")
    }
    if i < repos.length() - 1 {
      buf.write_string("\n")
    }
    i = i + 1
  }
  buf.to_string()
}

///| 解析编号列表字符串（如 "1,3,5"），过滤非法项与重复项
fn parse_ids(s : String) -> Array[Int] {
  let out = []
  for part in s.split(",") {
    let t = part.trim()
    if t.length() > 0 {
      let n = try {
        @string.parse_int(t)
      } catch {
        _ => -1
      }
      if n > 0 && !out.contains(n) {
        out.push(n)
      }
    }
  }
  out
}

///| 毫秒时间戳 → 日期字符串 YYYY-MM-DD（公历 civil_from_days 算法）
pub fn millis_to_date(ms : UInt64) -> String {
  let days = (ms / 86400000UL).to_int()
  let z = days + 719468
  let era = (if z >= 0 { z } else { z - 146096 }) / 146097
  let doe = z - era * 146097
  let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  let y = yoe + era * 400
  let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
  let mp = (5 * doy + 2) / 153
  let d = doy - (153 * mp + 2) / 5 + 1
  let m = if mp < 10 { mp + 3 } else { mp - 9 }
  let year = if m <= 2 { y + 1 } else { y }
  "\{year}-\{pad2(m)}-\{pad2(d)}"
}

///| 月份/日期补零
fn pad2(n : Int) -> String {
  if n < 10 {
    "0\{n}"
  } else {
    "\{n}"
  }
}

///| JSON 字符串转义（" \ 换行 制表等）
fn escape_json(s : String) -> String {
  let buf = StringBuilder()
  for ch in s {
    if ch == '"' {
      buf.write_string("\\\"")
    } else if ch == '\\' {
      buf.write_string("\\\\")
    } else if ch == '\n' {
      buf.write_string("\\n")
    } else if ch == '\r' {
      buf.write_string("\\r")
    } else if ch == '\t' {
      buf.write_string("\\t")
    } else {
      buf.write_char(ch)
    }
  }
  buf.to_string()
}

///| 生成 n 个字符的分隔线
pub fn dash_line(n : Int) -> String {
  let buf = StringBuilder()
  let mut i = 0
  while i < n {
    buf.write_char('─')
    i = i + 1
  }
  buf.to_string()
}

///| 从 JSON 对象中安全读取字符串字段（字段缺失或为 null 时返回空串）
fn get_str(j : Json, key : String) -> String {
  if j is Object(obj) {
    match obj.get(key) {
      Some(v) => if v is String(s) { s } else { "" }
      None => ""
    }
  } else {
    ""
  }
}

///| 从 JSON 对象中安全读取整数字段（字段缺失或类型不符时返回 0）
fn get_int(j : Json, key : String) -> Int {
  if j is Object(obj) {
    match obj.get(key) {
      Some(v) => if v is Number(n, ..) { n.to_int() } else { 0 }
      None => 0
    }
  } else {
    0
  }
}
