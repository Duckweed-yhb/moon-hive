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
        "用法: moon run cmd/main daily digest '<项目JSON>' [--sort score|stars|updated|none]\n支持直接 JSON 或 Base64 编码的 JSON"
      } else {
        let mut sort_by = "score"
        let mut i = 1
        while i < args.length() {
          if args[i] == "--sort" && i + 1 < args.length() {
            sort_by = args[i + 1]
            i = i + 1
          }
          i = i + 1
        }
        digest(args[0], sort_by=sort_by)
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
    "summary" => {
      if args.length() < 1 {
        "用法: moon run cmd/main daily summary '<项目JSON>'\n支持直接 JSON 或 Base64 编码的 JSON"
      } else {
        summary(args[0])
      }
    }
    "filter" => {
      if args.length() < 1 {
        "用法: moon run cmd/main daily filter <项目JSON> [--lang 语言] [--min 星数] [--max 星数] [--kw 关键词]\n示例: daily filter '<json>' --lang MoonBit --min 10 --kw async"
      } else {
        let mut lang = ""
        let mut min = 0
        let mut max = 0
        let mut kw = ""
        let mut i = 1
        while i < args.length() {
          match args[i] {
            "--lang" => {
              if i + 1 < args.length() {
                lang = args[i + 1]
                i = i + 1
              }
            }
            "--min" => {
              if i + 1 < args.length() {
                min = try {
                  @string.parse_int(args[i + 1])
                } catch {
                  _ => 0
                }
                i = i + 1
              }
            }
            "--max" => {
              if i + 1 < args.length() {
                max = try {
                  @string.parse_int(args[i + 1])
                } catch {
                  _ => 0
                }
                i = i + 1
              }
            }
            "--kw" => {
              if i + 1 < args.length() {
                kw = args[i + 1]
                i = i + 1
              }
            }
            _ => ()
          }
          i = i + 1
        }
        filter(args[0], lang, min, max, kw)
      }
    }
    _ => "未知命令: \{command}（支持: digest / filter / keep / export）"
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
///| sort_by: score（星数+新鲜度加权打分，默认）/ stars / updated / none（保持传入顺序）
pub fn digest(json_str : String, sort_by? : String = "score") -> String {
  match parse_repo_list(json_str) {
    Ok(repos) => {
      let today = (@env.now() / 86400000UL).to_int()
      let sorted = sort_repos(repos, sort_by, today)
      render_cards(sorted, "今日推荐")
    }
    Err(msg) => msg
  }
}

///| 按指定策略对项目排序（选择排序，原地交换）
fn sort_repos(repos : Array[Repo], sort_by : String, today : Int) -> Array[Repo] {
  if sort_by == "none" {
    return repos
  }
  let scores = if sort_by == "score" { compute_scores(repos, today) } else { [] }
  let mut i = 0
  while i < repos.length() {
    let mut best = i
    let mut j = i + 1
    while j < repos.length() {
      let better = match sort_by {
        "stars" => repos[j].stars > repos[best].stars
        "updated" => parse_iso_date(repos[j].updated) > parse_iso_date(repos[best].updated)
        "score" => scores[j] > scores[best]
        _ => false
      }
      if better {
        best = j
      }
      j = j + 1
    }
    if best != i {
      let tmp = repos[i]
      repos[i] = repos[best]
      repos[best] = tmp
      if scores.length() > 0 {
        let st = scores[i]
        scores[i] = scores[best]
        scores[best] = st
      }
    }
    i = i + 1
  }
  repos
}

///| 多因子打分：60% 星数（log 尺度归一化）+ 40% 新鲜度（30 天内线性衰减）
fn compute_scores(repos : Array[Repo], today : Int) -> Array[Double] {
  let mut max_stars = 0
  for r in repos {
    if r.stars > max_stars {
      max_stars = r.stars
    }
  }
  let scores = []
  for r in repos {
    let ns = if max_stars > 0 {
      @math.log10((r.stars + 1).to_double()) / @math.log10((max_stars + 1).to_double())
    } else {
      0.0
    }
    let days = today - parse_iso_date(r.updated)
    let fresh = if days <= 0 {
      1.0
    } else if days >= 30 {
      0.0
    } else {
      1.0 - days.to_double() / 30.0
    }
    scores.push(0.6 * ns + 0.4 * fresh)
  }
  scores
}

///| 解析 ISO 日期（YYYY-MM-DD...）为 epoch 天数；非法返回 -1
pub fn parse_iso_date(iso : String) -> Int {
  if iso.length() < 10 {
    return -1
  }
  let y = try {
    @string.parse_int(iso[0:4])
  } catch {
    _ => -1
  }
  let m = try {
    @string.parse_int(iso[5:7])
  } catch {
    _ => -1
  }
  let d = try {
    @string.parse_int(iso[8:10])
  } catch {
    _ => -1
  }
  if y < 0 || m < 1 || m > 12 || d < 1 || d > 31 {
    -1
  } else {
    days_from_civil(y, m, d)
  }
}

///| 公历日期 → epoch 天数（civil days 算法）
pub fn days_from_civil(y : Int, m : Int, d : Int) -> Int {
  let yy = if m <= 2 { y - 1 } else { y }
  let era = (if yy >= 0 { yy } else { yy - 399 }) / 400
  let yoe = yy - era * 400
  let mp = (m + 9) % 12
  let doy = (153 * mp + 2) / 5 + d - 1
  let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
  era * 146097 + doe - 719468
}

///| 按条件筛选项目：语言（大小写不敏感）/ 最低星数 / 最高星数 / 关键词（名称或描述，大小写不敏感）
pub fn filter(
  repos_str : String,
  lang : String,
  min_stars : Int,
  max_stars : Int,
  keyword : String,
) -> String {
  let repos = match parse_repo_list(repos_str) {
    Ok(r) => r
    Err(msg) => return msg
  }
  let l = lang.to_lower()
  let k = keyword.to_lower()
  let filtered = []
  for r in repos {
    let mut ok = true
    if l != "" && r.lang.to_lower() != l {
      ok = false
    }
    if ok && min_stars > 0 && r.stars < min_stars {
      ok = false
    }
    if ok && max_stars > 0 && r.stars > max_stars {
      ok = false
    }
    if ok && k != "" && !r.name.to_lower().contains(k) && !r.desc.to_lower().contains(k) {
      ok = false
    }
    if ok {
      filtered.push(r)
    }
  }
  if filtered.length() == 0 {
    return "（没有符合筛选条件的项目）"
  }
  render_cards(filtered, "筛选结果（条件: \{describe_cond(lang, min_stars, max_stars, keyword)}）")
}

///| 描述筛选条件（用于结果标题）
fn describe_cond(lang : String, min_stars : Int, max_stars : Int, keyword : String) -> String {
  let parts = []
  if lang != "" {
    parts.push("语言=" + lang)
  }
  if min_stars > 0 {
    parts.push("星数>=" + min_stars.to_string())
  }
  if max_stars > 0 {
    parts.push("星数<=" + max_stars.to_string())
  }
  if keyword != "" {
    parts.push("关键词=" + keyword)
  }
  if parts.length() == 0 {
    "无"
  } else {
    parts.join(",")
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
fn render_cards(repos : Array[Repo], title : String) -> String {
  if repos.length() == 0 {
    return "（没有可推荐的项目）"
  }
  let buf = StringBuilder()
  buf.write_string(title + "（\{repos.length()} 个项目）\n")
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

///| 项目摘要："在讲什么" —— 一句话 + 话题标签 + 类型判断 + 相对更新时间
pub fn summary(json_str : String) -> String {
  match parse_repo_list(json_str) {
    Ok(repos) => {
      let today = (@env.now() / 86400000UL).to_int()
      let buf = StringBuilder()
      buf.write_string("项目摘要（\{repos.length()} 个）\n")
      buf.write_string(dash_line(46) + "\n")
      let mut i = 0
      while i < repos.length() {
        let r = repos[i]
        let tags = top_topics(r).join(" · ")
        let days = today - parse_iso_date(r.updated)
        let when = if days <= 0 {
          "今天"
        } else if days == 1 {
          "昨天"
        } else {
          "\{days} 天前"
        }
        buf.write_string("[\{i + 1}] \{r.name}  ⭐\{r.stars}  [\{r.lang}]\n")
        buf.write_string("    在讲什么：\{one_liner(r)}\n")
        buf.write_string("    话题：\{tags}\n")
        buf.write_string("    类型：\{type_of(r)}\n")
        buf.write_string("    更新：\{when}\n")
        if i + 1 < repos.length() {
          buf.write_string("\n")
        }
        i = i + 1
      }
      buf.to_string()
    }
    Err(msg) => msg
  }
}

///| 一句话摘要：描述截断到 80 字符；无描述时给出提示
fn one_liner(r : Repo) -> String {
  if r.desc.length() > 0 {
    if r.desc.length() > 80 {
      r.desc[:80].to_owned() + "…"
    } else {
      r.desc
    }
  } else {
    "暂无描述（凭名称与星数判断是否值得点开）"
  }
}

///| 话题标签：名称+描述分词 → 过滤停用词 → 按词频取 Top 4
fn top_topics(r : Repo) -> Array[String] {
  let words : Array[String] = []
  let counts : Array[Int] = []
  for w in split_words(r.name + " " + r.desc) {
    if w.length() > 1 && !is_stopword(w) {
      let mut found = false
      let mut k = 0
      while k < words.length() {
        if words[k] == w {
          counts[k] = counts[k] + 1
          found = true
        }
        k = k + 1
      }
      if !found {
        words.push(w)
        counts.push(1)
      }
    }
  }
  // 按词频降序选择排序，取前 4
  let n = words.length()
  let mut i = 0
  while i < n {
    let mut best = i
    let mut j = i + 1
    while j < n {
      if counts[j] > counts[best] {
        best = j
      }
      j = j + 1
    }
    if best != i {
      let tw = words[i]
      words[i] = words[best]
      words[best] = tw
      let tc = counts[i]
      counts[i] = counts[best]
      counts[best] = tc
    }
    i = i + 1
  }
  let limit = if n < 4 { n } else { 4 }
  let top = []
  let mut t = 0
  while t < limit {
    top.push(words[t])
    t = t + 1
  }
  top
}

///| 简单分词：按空白与常见标点切分，统一转小写
fn split_words(s : String) -> Array[String] {
  let cleaned = StringBuilder()
  for c in s {
    if c == ' ' || c == ',' || c == '.' || c == ';' || c == ':' || c == '(' ||
      c == ')' || c == '/' || c == '|' || c == '&' || c == '+' || c == '\'' ||
      c == '"' || c == '!' || c == '?' || c == '-' || c == '_' || c == '[' ||
      c == ']' || c == '{' || c == '}' || c == '#' || c == '@' {
      cleaned.write_char(' ')
    } else {
      cleaned.write_char(c)
    }
  }
  let result = []
  for w in cleaned.to_string().split(" ") {
    if w.length() > 0 {
      result.push(w.to_owned().to_lower())
    }
  }
  result
}

///| 英文停用词表（高频无信息量词）
fn is_stopword(w : String) -> Bool {
  let stops = [
    "a", "an", "the", "and", "or", "for", "of", "with", "without", "to", "in",
    "on", "at", "by", "from", "into", "onto", "is", "are", "was", "were", "be",
    "been", "being", "has", "have", "had", "do", "does", "did", "will", "would",
    "can", "could", "should", "may", "might", "must", "shall", "this", "that",
    "these", "those", "it", "its", "as", "not", "no", "so", "but", "if", "then",
    "than", "too", "very", "just", "also", "etc", "using", "use", "used", "based",
  ]
  let mut i = 0
  while i < stops.length() {
    if stops[i] == w {
      return true
    }
    i = i + 1
  }
  false
}

///| 项目类型判断：基于名称+描述的关键词匹配
fn type_of(r : Repo) -> String {
  let d = (r.name + " " + r.desc).to_lower()
  if d.contains("framework") {
    "框架"
  } else if d.contains("binding") || d.contains("ffi") {
    "语言绑定"
  } else if d.contains("compiler") || d.contains("interpreter") || d.contains("language") {
    "语言/编译器"
  } else if d.contains("cli") || d.contains("command") || d.contains("terminal") ||
    d.contains("tool") {
    "命令行工具"
  } else if d.contains("library") || d.contains(" lib") {
    "库"
  } else if d.contains("demo") || d.contains("example") || d.contains("sample") {
    "示例"
  } else if d.contains("web") || d.contains("http") || d.contains("server") {
    "Web"
  } else if d.contains("game") {
    "游戏"
  } else {
    "项目"
  }
}
