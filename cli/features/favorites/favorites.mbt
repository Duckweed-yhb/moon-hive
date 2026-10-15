///|
/// 收藏夹数据结构
pub(all) struct Favorite {
  slug : String
  note : String
  conclusion : String?
  kind : String
  added_at : String
} derive(Eq, Debug)

///|
fn favorites_path() -> String {
  "favorites.json"
}

///|
/// 写收藏夹到文件（每行一条，| 分隔）
fn save(items : Array[Favorite]) -> Unit {
  let b = StringBuilder()
  for f in items {
    let conc = match f.conclusion {
      Some(c) => c
      None => ""
    }
    b.write_string(f.slug)
    b.write_string("|")
    b.write_string(f.note)
    b.write_string("|")
    b.write_string(conc)
    b.write_string("|")
    b.write_string(f.kind)
    b.write_string("|")
    b.write_string(f.added_at)
    b.write_string("\n")
  }
  ignore(@fs.write_text(favorites_path(), b.to_string()))
}

///|
/// 从文件读收藏夹
pub fn load() -> Array[Favorite] {
  if !@fs.exists(favorites_path()) {
    return []
  }
  let content = @fs.read_text(favorites_path())
  let items : Array[Favorite] = []
  let lines = content.split("\n").to_array()
  for line in lines {
    let l = line.trim().to_owned()
    if l == "" { continue }
    let parts = l.split("|").to_array()
    if parts.length() < 5 { continue }
    let conclusion = if parts[2].to_owned() == "" {
      None
    } else {
      Some(parts[2].to_owned())
    }
    items.push({
      slug: parts[0].to_owned(),
      note: parts[1].to_owned(),
      conclusion: conclusion,
      kind: parts[3].to_owned(),
      added_at: parts[4].to_owned(),
    })
  }
  items
}

///|
/// keep 命令
pub fn cmd_keep(args : Array[String]) -> Int {
  let mut slug = ""
  let mut note = ""
  let mut i = 0
  while i < args.length() {
    let a = args[i]
    if a == "--note" && i + 1 < args.length() {
      note = args[i + 1]
      i += 2
    } else if slug == "" {
      slug = a
      i += 1
    } else {
      i += 1
    }
  }
  if slug == "" {
    println("用法: moonhive keep <owner/repo> [--note \"备注\"]")
    return 14
  }
  let items = load()
  let mut found = false
  for j in 0..<items.length() {
    if items[j].slug == slug {
      items.set(j, { ..items[j], note: note })
      found = true
    }
  }
  if !found {
    items.push({
      slug: slug,
      note: note,
      conclusion: None,
      kind: "github",
      added_at: @env.now().to_string(),
    })
  }
  save(items)
  if found {
    println("已更新收藏: " + slug)
  } else {
    println("已收藏: " + slug)
  }
  0
}

///|
/// list 命令：生成 favorites.md
pub fn cmd_list() -> Int {
  let items = load()
  if items.length() == 0 {
    println("收藏夹为空。用 moonhive keep <owner/repo> --note \"备注\" 添加。")
    return 0
  }
  let b = StringBuilder()
  b.write_string("# 我的收藏夹\n\n")
  b.write_string("| 项目 | 类型 | 验证结论 | 备注 | 收藏时间戳 |\n")
  b.write_string("|---|---|---|---|---|\n")
  for f in items {
    let conc = match f.conclusion {
      Some(c) => c
      None => "—"
    }
    b.write_string("| `" + f.slug + "` | " + f.kind + " | " + conc + " | " + f.note + " | " + f.added_at + " |\n")
  }
  ignore(@fs.write_text("favorites.md", b.to_string()))
  println("共 " + items.length().to_string() + " 条收藏，已写入 favorites.md")
  println("")
  for f in items {
    let conc = match f.conclusion {
      Some(c) => c
      None => "—"
    }
    println("  " + f.slug + "  [" + conc + "]  " + f.note)
  }
  0
}

///|
/// forget 命令
pub fn cmd_forget(args : Array[String]) -> Int {
  if args.length() == 0 || args[0] == "" {
    println("用法: moonhive forget <owner/repo>")
    return 14
  }
  let slug = args[0]
  let items = load()
  let kept : Array[Favorite] = []
  let mut removed = false
  for f in items {
    if f.slug == slug {
      removed = true
    } else {
      kept.push(f)
    }
  }
  if removed {
    save(kept)
    println("已取消收藏: " + slug)
    0
  } else {
    println("未找到: " + slug)
    13
  }
}
