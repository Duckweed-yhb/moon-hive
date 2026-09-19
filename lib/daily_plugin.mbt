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
  "每日 GitHub 项目投喂：digest 推荐 / random 随机 / compare 对比 / keep 收藏 / export 导出"
}

///|
pub impl Plugin for DailyPlugin with execute(_self, command, args) {
  match command {
    "digest" => {
      if args.length() < 1 {
        "用法: moon run cmd/main daily digest '<项目JSON>' [--sort score|stars|updated|none] [--why]\n支持直接 JSON 或 Base64 编码的 JSON\n--why: 为每个项目生成一句话推荐理由"
      } else {
        let mut sort_by = "score"
        let mut why = false
        let mut i = 1
        while i < args.length() {
          if args[i] == "--sort" && i + 1 < args.length() {
            sort_by = args[i + 1]
            i = i + 1
          } else if args[i] == "--why" {
            why = true
          }
          i = i + 1
        }
        digest(args[0], sort_by=sort_by, why=why)
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
    "stats" => {
      if args.length() < 1 {
        "用法: moon run cmd/main daily stats '<项目JSON>'\n支持直接 JSON 或 Base64 编码的 JSON"
      } else {
        stats(args[0])
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
        "用法: moon run cmd/main daily filter <项目JSON> [--lang 语言] [--min 星数] [--max 星数] [--kw 关键词] [--json]\n示例: daily filter '<json>' --lang MoonBit --min 10 --kw async\n--json: 输出纯 JSON（供脚本管道复用）"
      } else {
        let mut lang = ""
        let mut min = 0
        let mut max = 0
        let mut kw = ""
        let mut json_mode = false
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
            "--json" => {
              json_mode = true
            }
            _ => ()
          }
          i = i + 1
        }
        if json_mode {
          filter_json(args[0], lang, min, max, kw)
        } else {
          filter(args[0], lang, min, max, kw)
        }
      }
    }
    "random" => {
      if args.length() < 1 {
        "用法: moon run cmd/main daily random <项目JSON> [--count 数量]\n示例: daily random '<json>' --count 5\n支持直接 JSON 或 Base64 编码的 JSON"
      } else {
        let mut count = 3
        let mut i = 1
        while i < args.length() {
          if args[i] == "--count" && i + 1 < args.length() {
            count = try {
              @string.parse_int(args[i + 1])
            } catch {
              _ => 3
            }
            i = i + 1
          }
          i = i + 1
        }
        random(args[0], count)
      }
    }
    "compare" => {
      if args.length() < 3 {
        "用法: moon run cmd/main daily compare <项目JSON> <A编号或名称> <B编号或名称>\n示例: daily compare '<json>' 1 2"
      } else {
        compare(args[0], args[1], args[2])
      }
    }
    _ => "未知命令: \{command}（支持: digest / summary / filter / keep / export / stats / random / compare）"
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
///| why: 为每个项目追加一句话推荐理由（确定性规则，见 why_reason）
pub fn digest(json_str : String, sort_by? : String = "score", why? : Bool = false) -> String {
  match parse_repo_list(json_str) {
    Ok(repos) => {
      let today = (@env.now() / 86400000UL).to_int()
      let sorted = sort_repos(repos, sort_by, today)
      render_cards(sorted, "今日推荐", why=why, today=today)
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

///| 按条件筛选项目，返回纯 JSON 数组字符串（供脚本管道复用，如 daily.ps1 筛选后重新编码）
pub fn filter_json(
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
    return "[]"
  }
  repos_to_json(filtered)
}

///| 把项目列表渲染为 JSON 数组字符串（字段与 GitHub API 输入保持一致，供 digest 等命令直接复用）
fn repos_to_json(repos : Array[Repo]) -> String {
  let buf = StringBuilder()
  buf.write_string("[")
  let mut i = 0
  while i < repos.length() {
    let r = repos[i]
    buf.write_string(
      "{\"name\":\"\{escape_json(r.name)}\",\"description\":\"\{escape_json(r.desc)}\",\"html_url\":\"\{escape_json(r.url)}\",\"stargazers_count\":\{r.stars},\"language\":\"\{escape_json(r.lang)}\",\"updated_at\":\"\{escape_json(r.updated)}\"}",
    )
    if i < repos.length() - 1 {
      buf.write_string(",")
    }
    i = i + 1
  }
  buf.write_string("]")
  buf.to_string()
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
///| why: 为每个项目追加一行"💡 推荐理由"；today: 用于计算相对更新时间（digest/filter/random 传入）
fn render_cards(repos : Array[Repo], title : String, why? : Bool = false, today? : Int = -1) -> String {
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
    if why && today >= 0 && r.updated != "" {
      let days = today - parse_iso_date(r.updated)
      buf.write_string("    💡 " + why_reason(r, days) + "\n")
    }
    if i < repos.length() - 1 {
      buf.write_string("\n")
    }
    i = i + 1
  }
  buf.to_string()
}

///| 推荐理由：结合新鲜度/星数/方向关键词，生成一句话"为什么推荐"（确定性规则，可测试）
///| days: 距上次更新的天数（0 = 今天更新）
pub fn why_reason(r : Repo, days : Int) -> String {
  // 方向识别（名称+描述关键词）
  let dir = detect_direction(r)
  // 新鲜度信号
  let fresh = if days <= 0 {
    "今天刚更新"
  } else if days <= 3 {
    "最近 3 天持续活跃"
  } else if days <= 7 {
    "本周有更新"
  } else if days <= 30 {
    "近一个月在维护"
  } else {
    "更新节奏偏慢"
  }
  // 星数信号
  let star = if r.stars >= 1000 {
    "生态级千星项目"
  } else if r.stars >= 100 {
    "已被社区认可（百星）"
  } else if r.stars >= 10 {
    "正在积累口碑"
  } else {
    "早期的年轻项目"
  }
  // 组合判定句（星数 × 活跃度 决策树）
  let verdict = if r.stars >= 100 && days <= 7 {
    "活跃维护的热门项目，值得跟进"
  } else if r.stars >= 100 && days > 30 {
    "成熟项目，更新放缓但仍值得参考"
  } else if r.stars < 10 && days <= 3 {
    "刚起步的新项目，趁早关注"
  } else if r.stars < 10 && days > 30 {
    "早期探索项目，先看看方向"
  } else if days <= 7 {
    "正在成长中，社区在持续投入"
  } else {
    "有一定积累，可以了解一下"
  }
  // 组装：前缀标签（MoonBit 原生 / 方向）+ 新鲜度 + 星数 + 判定句
  let parts = []
  if is_moonbit(r) {
    parts.push("MoonBit 原生")
  }
  if dir != "" {
    parts.push(dir)
  }
  parts.push(fresh)
  parts.push(star)
  parts.join(" · ") + "：" + verdict
}

///| 语言是否为 MoonBit（大小写不敏感）
fn is_moonbit(r : Repo) -> Bool {
  r.lang.to_lower().contains("moonbit")
}

///| 从名称+描述识别项目方向（工具链/界面/Web/工程质量/游戏/编译器），未命中返回空串
fn detect_direction(r : Repo) -> String {
  let text = (r.name + " " + r.desc).to_lower()
  if contains_any(text, ["gui", "framework", "component", "react"]) {
    "界面/框架方向"
  } else if contains_any(text, ["cli", "command", "tool", "utility"]) {
    "工具链方向"
  } else if contains_any(text, ["web", "http", "server", "client"]) {
    "Web/服务端方向"
  } else if contains_any(text, ["test", "bench", "quality"]) {
    "工程质量方向"
  } else if contains_any(text, ["game", "sprite"]) {
    "游戏方向"
  } else if contains_any(text, ["compiler", "parser", "lexer", "interpreter"]) {
    "编译器/解析器方向"
  } else {
    ""
  }
}

///| 文本是否包含任一关键词
fn contains_any(s : String, kws : Array[String]) -> Bool {
  let mut found = false
  for kw in kws {
    if s.contains(kw) {
      found = true
    }
  }
  found
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

///| 生态统计：语言分布（条形图）/ 星数分档 / 更新活跃度 / 汇总
pub fn stats(json_str : String) -> String {
  match parse_repo_list(json_str) {
    Ok(repos) => {
      if repos.length() == 0 {
        return "（没有可统计的项目）"
      }
      let today = (@env.now() / 86400000UL).to_int()
      let n = repos.length()
      let buf = StringBuilder()
      buf.write_string("生态统计（\{n} 个项目）\n")
      buf.write_string(dash_line(46) + "\n")

      // 语言分布（按数量降序 + 条形图）
      buf.write_string("语言分布：\n")
      let lnames : Array[String] = []
      let lcounts : Array[Int] = []
      for r in repos {
        let l = if r.lang == "" { "未标注" } else { r.lang }
        let mut found = false
        let mut k = 0
        while k < lnames.length() {
          if lnames[k] == l {
            lcounts[k] = lcounts[k] + 1
            found = true
          }
          k = k + 1
        }
        if !found {
          lnames.push(l)
          lcounts.push(1)
        }
      }
      sort_desc(lnames, lcounts)
      let mut i = 0
      while i < lnames.length() {
        let bar_len = lcounts[i] * 10 / n
        let bar = StringBuilder()
        let mut b = 0
        while b < bar_len {
          bar.write_string("█")
          b = b + 1
        }
        buf.write_string("  \{lnames[i]}  \{bar.to_string()}\{lcounts[i]} (\{lcounts[i] * 100 / n}%)\n")
        i = i + 1
      }
      buf.write_string("\n")

      // 星数分档
      let mut b0 = 0
      let mut b1 = 0
      let mut b2 = 0
      let mut b3 = 0
      let mut total_stars = 0
      let mut max_stars = 0
      let mut max_name = ""
      for r in repos {
        total_stars = total_stars + r.stars
        if r.stars > max_stars {
          max_stars = r.stars
          max_name = r.name
        }
        if r.stars == 0 {
          b0 = b0 + 1
        } else if r.stars <= 10 {
          b1 = b1 + 1
        } else if r.stars <= 100 {
          b2 = b2 + 1
        } else {
          b3 = b3 + 1
        }
      }
      buf.write_string("星数分档：\n")
      buf.write_string("  ⭐0       \{b0}\n")
      buf.write_string("  ⭐1-10    \{b1}\n")
      buf.write_string("  ⭐11-100  \{b2}\n")
      buf.write_string("  ⭐101+    \{b3}\n")
      buf.write_string("\n")

      // 更新活跃度
      let mut f7 = 0
      let mut f30 = 0
      let mut fold = 0
      for r in repos {
        let days = today - parse_iso_date(r.updated)
        if days <= 7 {
          f7 = f7 + 1
        } else if days <= 30 {
          f30 = f30 + 1
        } else {
          fold = fold + 1
        }
      }
      buf.write_string("更新活跃度：\n")
      buf.write_string("  7 天内    \{f7}\n")
      buf.write_string("  8-30 天   \{f30}\n")
      buf.write_string("  更久      \{fold}\n")
      buf.write_string("\n")

      // 汇总
      buf.write_string("汇总：\{n} 个项目 · 总星数 \{total_stars} · 平均 \{total_stars / n} · 最多 \{max_name}(\{max_stars})\n")
      buf.to_string()
    }
    Err(msg) => msg
  }
}

///| 按 count 降序同步排序 keys/vals（选择排序）
fn sort_desc(keys : Array[String], vals : Array[Int]) -> Unit {
  let n = vals.length()
  let mut i = 0
  while i < n {
    let mut best = i
    let mut j = i + 1
    while j < n {
      if vals[j] > vals[best] {
        best = j
      }
      j = j + 1
    }
    if best != i {
      let tk = keys[i]
      keys[i] = keys[best]
      keys[best] = tk
      let tv = vals[i]
      vals[i] = vals[best]
      vals[best] = tv
    }
    i = i + 1
  }
}

///| 随机推荐：从项目列表中随机抽取 N 个（LCG 伪随机，纯 core 自研，不重复）
///| seed 可选：默认用当前时间毫秒做种子；传固定 seed 可复现（用于测试）
pub fn random(json_str : String, count : Int, seed? : UInt64 = 0UL) -> String {
  let repos = match parse_repo_list(json_str) {
    Ok(r) => r
    Err(msg) => return msg
  }
  if repos.length() == 0 {
    return "（没有可随机推荐的项目）"
  }
  let n = if count <= 0 { 3 } else { count }
  let mut s = if seed == 0UL { @env.now() } else { seed }
  let picked = []
  while picked.length() < n && picked.length() < repos.length() {
    s = lcg_next(s)
    let idx = (s % repos.length().to_uint64()).to_int()
    if !picked.contains(idx) {
      picked.push(idx)
    }
  }
  let out = []
  for idx in picked {
    out.push(repos[idx])
  }
  render_cards(out, "随机推荐（不按分数，换换口味）")
}

///| 线性同余生成器（LCG）：next = (a * seed + c) & (2^63 - 1)，UInt64 乘法自动回绕
fn lcg_next(seed : UInt64) -> UInt64 {
  (6364136223846793005UL * seed + 1442695040888963407UL) & 0x7FFFFFFFFFFFFFFFUL
}

///| 项目对比：两个项目（编号 1..N 或项目名称）逐字段对比输出
pub fn compare(json_str : String, a_key : String, b_key : String) -> String {
  let repos = match parse_repo_list(json_str) {
    Ok(r) => r
    Err(msg) => return msg
  }
  if repos.length() < 2 {
    return "（项目太少：至少需要 2 个项目才能对比）"
  }
  let a = find_repo(repos, a_key)
  let b = find_repo(repos, b_key)
  if a is None {
    return "（找不到项目: \{a_key}，可用编号 1..\{repos.length()} 或项目名称）"
  }
  if b is None {
    return "（找不到项目: \{b_key}，可用编号 1..\{repos.length()} 或项目名称）"
  }
  let (ra, rb) = match (a, b) {
    (Some(x), Some(y)) => (x, y)
    _ => (
      Repo::{ name: "", desc: "", url: "", stars: 0, lang: "", updated: "" },
      Repo::{ name: "", desc: "", url: "", stars: 0, lang: "", updated: "" },
    )
  }
  let buf = StringBuilder()
  buf.write_string("对比：\{ra.name}  vs  \{rb.name}\n")
  buf.write_string(dash_line(46) + "\n")
  buf.write_string("星数：   ⭐\{ra.stars}  vs  ⭐\{rb.stars}\n")
  buf.write_string("语言：   \{fmt_or(ra.lang)}  vs  \{fmt_or(rb.lang)}\n")
  buf.write_string("更新：   \{fmt_or(ra.updated)}  vs  \{fmt_or(rb.updated)}\n")
  buf.write_string("描述：   \{fmt_or(ra.desc)}  vs  \{fmt_or(rb.desc)}\n")
  buf.write_string("链接：   \{fmt_or(ra.url)}  vs  \{fmt_or(rb.url)}\n")
  buf.write_string("\n")
  if ra.stars > rb.stars {
    buf.write_string("→ \{ra.name} 更受欢迎（⭐\{ra.stars} > ⭐\{rb.stars}）\n")
  } else if rb.stars > ra.stars {
    buf.write_string("→ \{rb.name} 更受欢迎（⭐\{rb.stars} > ⭐\{ra.stars}）\n")
  } else {
    buf.write_string("→ 两者星数相当\n")
  }
  buf.to_string()
}

///| 按编号（1..N）或名称查找项目
fn find_repo(repos : Array[Repo], key : String) -> Option[Repo] {
  let ids = parse_ids(key)
  if ids.length() > 0 {
    let id = ids[0]
    if id >= 1 && id <= repos.length() {
      return Some(repos[id - 1])
    }
    return None
  }
  for r in repos {
    if r.name == key {
      return Some(r)
    }
  }
  None
}

///| 空字符串显示为 "-"
fn fmt_or(s : String) -> String {
  if s == "" { "-" } else { s }
}
