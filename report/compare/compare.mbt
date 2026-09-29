///|
/// report/compare — 两份报告的对比（纯计算，可离线单测）

///|
/// 单条差异
pub(all) struct DiffRow {
  slug : String
  before : String
  after : String
  kind : String
}

///|
/// 对比结果汇总
pub(all) struct DiffSummary {
  added : Int
  removed : Int
  improved : Int
  regressed : Int
  neutral_change : Int
  unchanged : Int
}

///|
fn classify_change(before : String, after : String) -> String {
  let before_usable = before == "Verified"
  let after_usable = after == "Verified"
  if before_usable && !after_usable {
    "regressed"
  } else if !before_usable && after_usable {
    "improved"
  } else if before != after {
    "neutral"
  } else {
    "unchanged"
  }
}

///|
fn find_after(after_rows : Array[@model.ResultRow], slug : String) -> String? {
  for r in after_rows {
    if r.slug == slug {
      return Some(r.diagnosis)
    }
  }
  None
}

///|
fn find_before(before_rows : Array[@model.ResultRow], slug : String) -> String? {
  for r in before_rows {
    if r.slug == slug {
      return Some(r.diagnosis)
    }
  }
  None
}

///|
pub fn compare(before : @model.ReportModel, after : @model.ReportModel) -> Array[DiffRow] {
  let rows : Array[DiffRow] = []

  for b in before.rows {
    match find_after(after.rows, b.slug) {
      Some(after_diag) => {
        if b.diagnosis == after_diag {
          rows.push({ slug: b.slug, before: b.diagnosis, after: after_diag, kind: "unchanged" })
        } else {
          let kind = classify_change(b.diagnosis, after_diag)
          rows.push({ slug: b.slug, before: b.diagnosis, after: after_diag, kind: kind })
        }
      }
      None => {
        rows.push({ slug: b.slug, before: b.diagnosis, after: "", kind: "removed" })
      }
    }
  }

  for a in after.rows {
    if find_before(before.rows, a.slug) == None {
      rows.push({ slug: a.slug, before: "", after: a.diagnosis, kind: "added" })
    }
  }

  rows
}

///|
pub fn summarize(diffs : Array[DiffRow]) -> DiffSummary {
  let mut added = 0
  let mut removed = 0
  let mut improved = 0
  let mut regressed = 0
  let mut neutral = 0
  let mut unchanged = 0
  for d in diffs {
    if d.kind == "added" {
      added = added + 1
    } else if d.kind == "removed" {
      removed = removed + 1
    } else if d.kind == "improved" {
      improved = improved + 1
    } else if d.kind == "regressed" {
      regressed = regressed + 1
    } else if d.kind == "neutral" {
      neutral = neutral + 1
    } else {
      unchanged = unchanged + 1
    }
  }
  { added, removed, improved, regressed, neutral_change: neutral, unchanged }
}

///|
pub fn format_report(before : @model.ReportModel, after : @model.ReportModel, diffs : Array[DiffRow]) -> String {
  let s = summarize(diffs)
  let b = StringBuilder()

  b.write_string("对比结果\n")
  b.write_string("========\n")
  b.write_string("之前: ")
  b.write_string(before.toolchain)
  b.write_string(" (")
  b.write_string(before.rows.length().to_string())
  b.write_string(" 个包)\n")
  b.write_string("之后: ")
  b.write_string(after.toolchain)
  b.write_string(" (")
  b.write_string(after.rows.length().to_string())
  b.write_string(" 个包)\n\n")

  if s.improved > 0 {
    b.write_string("好转: ")
    b.write_string(s.improved.to_string())
    b.write_string(" 个\n")
  }
  if s.regressed > 0 {
    b.write_string("恶化: ")
    b.write_string(s.regressed.to_string())
    b.write_string(" 个\n")
  }
  if s.neutral_change > 0 {
    b.write_string("其他变化: ")
    b.write_string(s.neutral_change.to_string())
    b.write_string(" 个\n")
  }
  if s.added > 0 {
    b.write_string("新增: ")
    b.write_string(s.added.to_string())
    b.write_string(" 个\n")
  }
  if s.removed > 0 {
    b.write_string("消失: ")
    b.write_string(s.removed.to_string())
    b.write_string(" 个\n")
  }
  b.write_string("不变: ")
  b.write_string(s.unchanged.to_string())
  b.write_string(" 个\n\n")

  for d in diffs {
    if d.kind == "unchanged" {
      continue
    }
    if d.kind == "improved" {
      b.write_string("  ↑ ")
    } else if d.kind == "regressed" {
      b.write_string("  ↓ ")
    } else if d.kind == "added" {
      b.write_string("  + ")
    } else if d.kind == "removed" {
      b.write_string("  - ")
    } else {
      b.write_string("  · ")
    }
    b.write_string(d.slug)
    b.write_string("  ")
    b.write_string(d.before)
    b.write_string(" → ")
    b.write_string(d.after)
    b.write_char('\n')
  }

  b.to_string()
}

// ---------- 单元测试 ----------

fn row(slug : String, diag : String) -> @model.ResultRow {
  {
    slug,
    diagnosis: diag,
    explain: "",
    evidence: "",
    fetched: true,
    mbt_files: 0,
    source_lines: 0,
    test_files: 0,
    repo_bytes: 0L,
    check_ms: 0UL,
    test_ms: 0UL,
  }
}

fn make_model(rows : Array[@model.ResultRow]) -> @model.ReportModel {
  { generated_at: 1700000000000UL, target: "native", toolchain: "moon test", rows }
}

test "相同报告对比全部 unchanged" {
  let m = make_model([row("a", "Verified"), row("b", "NoManifest")])
  let diffs = compare(m, m)
  assert_eq(diffs.length(), 2)
  let s = summarize(diffs)
  assert_eq(s.unchanged, 2)
}

test "Verified 变成 DoesNotCompile 是 regressed" {
  let before = make_model([row("a", "Verified")])
  let after = make_model([row("a", "DoesNotCompile")])
  let diffs = compare(before, after)
  assert_eq(diffs[0].kind, "regressed")
}

test "DoesNotCompile 变成 Verified 是 improved" {
  let before = make_model([row("a", "DoesNotCompile")])
  let after = make_model([row("a", "Verified")])
  let diffs = compare(before, after)
  assert_eq(diffs[0].kind, "improved")
}

test "两个非 Verified 之间变化是 neutral" {
  let before = make_model([row("a", "DoesNotCompile")])
  let after = make_model([row("a", "NoManifest")])
  let diffs = compare(before, after)
  assert_eq(diffs[0].kind, "neutral")
}

test "新增的包标记为 added" {
  let before = make_model([row("a", "Verified")])
  let after = make_model([row("a", "Verified"), row("b", "NoManifest")])
  let diffs = compare(before, after)
  let s = summarize(diffs)
  assert_eq(s.added, 1)
  assert_eq(s.unchanged, 1)
}

test "消失的包标记为 removed" {
  let before = make_model([row("a", "Verified"), row("b", "NoManifest")])
  let after = make_model([row("a", "Verified")])
  let diffs = compare(before, after)
  let s = summarize(diffs)
  assert_eq(s.removed, 1)
}

test "format_report 输出包含关键信息" {
  let before = make_model([row("a", "Verified"), row("b", "DoesNotCompile")])
  let after = make_model([row("a", "DoesNotCompile"), row("b", "Verified"), row("c", "NoManifest")])
  let diffs = compare(before, after)
  let out = format_report(before, after, diffs)
  assert_true(out.contains("恶化: 1"))
  assert_true(out.contains("好转: 1"))
  assert_true(out.contains("新增: 1"))
}

test "空报告对比不崩溃" {
  let empty = make_model([])
  let diffs = compare(empty, empty)
  assert_eq(diffs.length(), 0)
}
