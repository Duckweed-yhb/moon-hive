test {
  // digest：解析有效 JSON 数组（含名称、描述、星数、语言、链接、更新时间）
  inspect(
    digest("[{\"name\":\"demo\",\"description\":\"a demo repo\",\"html_url\":\"https://github.com/x/demo\",\"stargazers_count\":42,\"language\":\"MoonBit\",\"updated_at\":\"2026-09-01T00:00:00Z\"}]"),
    content="今日推荐（1 个项目）\n" + dash_line(46) + "\n[1] demo  ⭐42  [MoonBit]\n    a demo repo\n    https://github.com/x/demo\n    更新: 2026-09-01T00:00:00Z\n",
  )
}

test {
  // digest：多项目默认按 score 排序（星数高的在前）
  let out = digest(
    "[{\"name\":\"a\",\"stargazers_count\":1},{\"name\":\"b\",\"stargazers_count\":2}]",
  )
  inspect(out, content="今日推荐（2 个项目）\n" + dash_line(46) + "\n[1] b  ⭐2\n\n[2] a  ⭐1\n")
}

test {
  // digest：字段缺失时安全降级为空串/0，不崩溃
  let out = digest("[{\"name\":\"a\"}]")
  assert_true(out.contains("a"))
  assert_true(out.contains("⭐0"))
}

test {
  // digest：非 JSON 非 Base64 的输入返回参数错误提示
  assert_true(digest("not-json").has_prefix("（参数解析失败"))
}

test {
  // digest：Base64 解码后仍是非法 JSON → 返回解析错误提示
  let b64 = base64_encode("not json")
  assert_true(digest(b64).has_prefix("（解析失败"))
}

test {
  // keep：从推荐中按编号选取并生成收藏 JSON
  let repos = "[{\"name\":\"a\",\"description\":\"A\",\"html_url\":\"https://github.com/x/a\",\"stargazers_count\":10,\"language\":\"MoonBit\",\"updated_at\":\"2026-09-01\"},{\"name\":\"b\",\"description\":\"B\",\"html_url\":\"https://github.com/x/b\",\"stargazers_count\":20,\"language\":\"MoonBit\",\"updated_at\":\"2026-09-01\"}]"
  let out = keep(repos, "1,2", "")
  assert_true(out.has_prefix("["))
  assert_true(out.contains("\"name\":\"a\""))
  assert_true(out.contains("\"name\":\"b\""))
  assert_true(out.contains("\"stars\":10"))
}

test {
  // keep：与旧收藏合并时按 url 去重，不重复收藏
  let repos = "[{\"name\":\"b\",\"description\":\"B\",\"html_url\":\"https://github.com/x/b\",\"stargazers_count\":20}]"
  let old = "[{\"name\":\"b\",\"desc\":\"B\",\"url\":\"https://github.com/x/b\",\"stars\":20,\"lang\":\"MoonBit\",\"saved\":\"2026-09-13\"}]"
  let out = keep(repos, "1", old)
  assert_true(count_occurrences(out, "\"url\":\"https://github.com/x/b\"") == 1)
}

test {
  // keep：编号越界返回提示
  let repos = "[{\"name\":\"a\"}]"
  assert_true(keep(repos, "9", "").has_prefix("（编号超出范围"))
}

test {
  // keep：非法编号返回提示
  let repos = "[{\"name\":\"a\"}]"
  assert_true(keep(repos, "x", "").has_prefix("（没有要保留的项目"))
}

test {
  // export：收藏 → Markdown 清单（按星数降序，链接正确）
  let favs = "[{\"name\":\"low\",\"desc\":\"\",\"url\":\"https://github.com/x/low\",\"stars\":10,\"lang\":\"\",\"saved\":\"2026-09-14\"},{\"name\":\"high\",\"desc\":\"top repo\",\"url\":\"https://github.com/x/high\",\"stars\":99,\"lang\":\"MoonBit\",\"saved\":\"2026-09-14\"}]"
  let md = export_md(favs)
  assert_true(md.has_prefix("# 我的 GitHub 项目收藏（2 个）"))
  assert_true(md.contains("high") && md.contains("low"))
  assert_true(md.split("low").to_array()[0].contains("high"))
  assert_true(md.contains("[high](https://github.com/x/high)"))
}

test {
  // export：空收藏返回提示
  assert_true(export_md("[]").contains("收藏为空"))
}

test {
  // millis_to_date：epoch 起点与 2000-01-01
  inspect(millis_to_date(0UL), content="1970-01-01")
  inspect(millis_to_date(946684800000UL), content="2000-01-01")
}

test {
  // favs_to_json → parse_fav_list 往返一致（含引号转义）
  let b64 = base64_encode("[{\"name\":\"a\\\"b\",\"desc\":\"line\\n1\",\"url\":\"https://x\",\"stars\":1,\"lang\":\"\",\"saved\":\"2026-09-14\"}]")
  let favs = match parse_fav_list(b64) {
    Ok(f) => f
    Err(_) => fail("should parse")
  }
  assert_true(favs.length() == 1)
  inspect(favs[0].name, content="a\"b")
  inspect(favs[0].desc, content="line\n1")
}

fn count_occurrences(s : String, sub : String) -> Int {
  s.split(sub).length() - 1
}

test {
  // filter：按语言筛选（大小写不敏感）
  let repos = "[{\"name\":\"a\",\"description\":\"\",\"html_url\":\"https://x/a\",\"stargazers_count\":5,\"language\":\"MoonBit\",\"updated_at\":\"\"},{\"name\":\"b\",\"description\":\"\",\"html_url\":\"https://x/b\",\"stargazers_count\":8,\"language\":\"Python\",\"updated_at\":\"\"}]"
  let out = filter(repos, "moonbit", 0, 0, "")
  assert_true(out.contains("[1] a"))
  assert_true(!out.contains("[1] b"))
}

test {
  // filter：按星数区间筛选
  let repos = "[{\"name\":\"a\",\"description\":\"\",\"html_url\":\"https://x/a\",\"stargazers_count\":5,\"language\":\"\",\"updated_at\":\"\"},{\"name\":\"b\",\"description\":\"\",\"html_url\":\"https://x/b\",\"stargazers_count\":42,\"language\":\"\",\"updated_at\":\"\"},{\"name\":\"c\",\"description\":\"\",\"html_url\":\"https://x/c\",\"stargazers_count\":100,\"language\":\"\",\"updated_at\":\"\"}]"
  let out = filter(repos, "", 10, 50, "")
  assert_true(!out.contains("a"))
  assert_true(out.contains("b"))
  assert_true(!out.contains("c"))
}

test {
  // filter：按关键词筛选（名称或描述，大小写不敏感）
  let repos = "[{\"name\":\"async-lib\",\"description\":\"async programming\",\"html_url\":\"https://x/a\",\"stargazers_count\":1,\"language\":\"\",\"updated_at\":\"\"},{\"name\":\"web-ui\",\"description\":\"UI framework\",\"html_url\":\"https://x/w\",\"stargazers_count\":1,\"language\":\"\",\"updated_at\":\"\"}]"
  let out = filter(repos, "", 0, 0, "ASYNC")
  assert_true(out.contains("async-lib"))
  assert_true(!out.contains("web-ui"))
}

test {
  // filter：组合条件（语言 + 星数 + 关键词）
  let repos = "[{\"name\":\"m1\",\"description\":\"http server\",\"html_url\":\"https://x/m1\",\"stargazers_count\":50,\"language\":\"MoonBit\",\"updated_at\":\"\"},{\"name\":\"m2\",\"description\":\"http client\",\"html_url\":\"https://x/m2\",\"stargazers_count\":3,\"language\":\"MoonBit\",\"updated_at\":\"\"},{\"name\":\"p1\",\"description\":\"http server\",\"html_url\":\"https://x/p1\",\"stargazers_count\":50,\"language\":\"Python\",\"updated_at\":\"\"}]"
  let out = filter(repos, "moonbit", 10, 0, "http")
  assert_true(out.contains("m1"))
  assert_true(!out.contains("m2"))
  assert_true(!out.contains("p1"))
}

test {
  // filter：无匹配返回提示
  let repos = "[{\"name\":\"a\",\"description\":\"\",\"html_url\":\"https://x/a\",\"stargazers_count\":1,\"language\":\"\",\"updated_at\":\"\"}]"
  assert_true(filter(repos, "", 100, 0, "").contains("没有符合筛选条件"))
}

test {
  // digest：--sort none 保持传入顺序；--sort stars 按星数降序
  let repos = "[{\"name\":\"a\",\"stargazers_count\":1},{\"name\":\"b\",\"stargazers_count\":2}]"
  assert_true(digest(repos, sort_by="none").contains("[1] a"))
  assert_true(digest(repos, sort_by="stars").contains("[1] b"))
}

test {
  // digest：--sort updated 按更新时间降序（新的在前）
  let repos = "[{\"name\":\"old\",\"updated_at\":\"2020-01-01T00:00:00Z\"},{\"name\":\"new\",\"updated_at\":\"2026-09-01T00:00:00Z\"}]"
  assert_true(digest(repos, sort_by="updated").contains("[1] new"))
}

test {
  // days_from_civil：epoch 起点与 2000-01-01（公认值）
  inspect(days_from_civil(1970, 1, 1).to_string(), content="0")
  inspect(days_from_civil(2000, 1, 1).to_string(), content="10957")
}

test {
  // parse_iso_date：标准 ISO 字符串与非法输入
  inspect(parse_iso_date("1970-01-01T00:00:00Z").to_string(), content="0")
  inspect(
    parse_iso_date("2026-09-14T07:00:00Z").to_string(),
    content=days_from_civil(2026, 9, 14).to_string(),
  )
  inspect(parse_iso_date("").to_string(), content="-1")
  inspect(parse_iso_date("not-a-date").to_string(), content="-1")
}

test {
  // summary：基本结构完整
  let repos = "[{\"name\":\"async-lib\",\"description\":\"async programming library for MoonBit\",\"html_url\":\"https://x/a\",\"stargazers_count\":68,\"language\":\"MoonBit\",\"updated_at\":\"2026-09-14T00:00:00Z\"}]"
  let out = summary(repos)
  assert_true(out.contains("在讲什么"))
  assert_true(out.contains("话题"))
  assert_true(out.contains("类型"))
  assert_true(out.contains("更新"))
}

test {
  // summary：话题提取过滤停用词（a/for 不出现，library/web 出现）
  let repos = "[{\"name\":\"web\",\"description\":\"a library for the web\",\"html_url\":\"https://x/w\",\"stargazers_count\":1,\"language\":\"\",\"updated_at\":\"\"}]"
  let out = summary(repos)
  assert_true(out.contains("library"))
  assert_true(out.contains("web"))
  assert_true(!out.contains(" 话题：a "))
}

test {
  // summary：类型判断（framework → 框架 / binding → 语言绑定 / 无描述 → 暂无描述）
  let repos = "[{\"name\":\"ui\",\"description\":\"web UI framework\",\"html_url\":\"https://x/ui\",\"stargazers_count\":1,\"language\":\"\",\"updated_at\":\"\"},{\"name\":\"img\",\"description\":\"ffi binding\",\"html_url\":\"https://x/img\",\"stargazers_count\":1,\"language\":\"\",\"updated_at\":\"\"},{\"name\":\"no-desc\",\"description\":\"\",\"html_url\":\"https://x/n\",\"stargazers_count\":1,\"language\":\"\",\"updated_at\":\"\"}]"
  let out = summary(repos)
  assert_true(out.contains("类型：框架"))
  assert_true(out.contains("类型：语言绑定"))
  assert_true(out.contains("暂无描述"))
}

test {
  // summary：相对更新时间（昨天，动态计算昨天日期，避免测试随日期过期）
  let yesterday = millis_to_date(@env.now() - 86400000UL)
  let repos = "[{\"name\":\"a\",\"description\":\"demo\",\"html_url\":\"https://x/a\",\"stargazers_count\":1,\"language\":\"\",\"updated_at\":\"\{yesterday}T00:00:00Z\"}]"
  assert_true(summary(repos).contains("更新：昨天"))
}

test {
  // stats：基本结构完整
  let repos = "[{\"name\":\"a\",\"description\":\"\",\"html_url\":\"https://x/a\",\"stargazers_count\":5,\"language\":\"MoonBit\",\"updated_at\":\"2026-09-14T00:00:00Z\"},{\"name\":\"b\",\"description\":\"\",\"html_url\":\"https://x/b\",\"stargazers_count\":50,\"language\":\"Python\",\"updated_at\":\"2026-09-01T00:00:00Z\"},{\"name\":\"c\",\"description\":\"\",\"html_url\":\"https://x/c\",\"stargazers_count\":0,\"language\":\"MoonBit\",\"updated_at\":\"2020-01-01T00:00:00Z\"}]"
  let out = stats(repos)
  assert_true(out.contains("语言分布"))
  assert_true(out.contains("星数分档"))
  assert_true(out.contains("更新活跃度"))
  assert_true(out.contains("汇总"))
}

test {
  // stats：语言分布计数与未标注处理
  let repos = "[{\"name\":\"a\",\"description\":\"\",\"html_url\":\"https://x/a\",\"stargazers_count\":1,\"language\":\"MoonBit\",\"updated_at\":\"\"},{\"name\":\"b\",\"description\":\"\",\"html_url\":\"https://x/b\",\"stargazers_count\":1,\"language\":\"MoonBit\",\"updated_at\":\"\"},{\"name\":\"c\",\"description\":\"\",\"html_url\":\"https://x/c\",\"stargazers_count\":1,\"language\":\"\",\"updated_at\":\"\"}]"
  let out = stats(repos)
  assert_true(out.contains("MoonBit"))
  assert_true(out.contains("2 (66%)"))
  assert_true(out.contains("未标注"))
}

test {
  // stats：星数分档正确
  let repos = "[{\"name\":\"a\",\"description\":\"\",\"html_url\":\"https://x/a\",\"stargazers_count\":0,\"language\":\"\",\"updated_at\":\"\"},{\"name\":\"b\",\"description\":\"\",\"html_url\":\"https://x/b\",\"stargazers_count\":5,\"language\":\"\",\"updated_at\":\"\"},{\"name\":\"c\",\"description\":\"\",\"html_url\":\"https://x/c\",\"stargazers_count\":50,\"language\":\"\",\"updated_at\":\"\"},{\"name\":\"d\",\"description\":\"\",\"html_url\":\"https://x/d\",\"stargazers_count\":500,\"language\":\"\",\"updated_at\":\"\"}]"
  let out = stats(repos)
  assert_true(out.contains("⭐0       1"))
  assert_true(out.contains("⭐1-10    1"))
  assert_true(out.contains("⭐11-100  1"))
  assert_true(out.contains("⭐101+    1"))
}

test {
  // stats：汇总数字与空输入
  let repos = "[{\"name\":\"a\",\"description\":\"\",\"html_url\":\"https://x/a\",\"stargazers_count\":5,\"language\":\"\",\"updated_at\":\"\"},{\"name\":\"b\",\"description\":\"\",\"html_url\":\"https://x/b\",\"stargazers_count\":15,\"language\":\"\",\"updated_at\":\"\"}]"
  let out = stats(repos)
  assert_true(out.contains("总星数 20"))
  assert_true(out.contains("平均 10"))
  assert_true(out.contains("最多 b(15)"))
  assert_true(stats("[]").contains("没有可统计的项目"))
}

test {
  // digest：空数组返回提示
  inspect(digest("[]"), content="（没有可推荐的项目）")
}

test {
  // digest：支持 Base64 编码的 JSON 输入（配套脚本传参方式，规避命令行引号问题）
  let b64 = base64_encode("[{\"name\":\"b64repo\",\"stargazers_count\":7}]")
  assert_true(digest(b64).contains("b64repo"))
  assert_true(digest(b64).contains("⭐7"))
}

test {
  // digest：既不是 JSON 也不是 Base64 时给出明确提示
  assert_true(digest("@@@").has_prefix("（参数解析失败"))
}

test {
  // random：空数组返回提示
  assert_true(random("[]", 3).contains("没有可随机推荐"))
}

test {
  // random：固定 seed 可复现（确定性），抽取 2 个不同项目
  let repos = "[{\"name\":\"a\",\"description\":\"\",\"html_url\":\"https://x/a\",\"stargazers_count\":1,\"language\":\"\",\"updated_at\":\"\"},{\"name\":\"b\",\"description\":\"\",\"html_url\":\"https://x/b\",\"stargazers_count\":2,\"language\":\"\",\"updated_at\":\"\"},{\"name\":\"c\",\"description\":\"\",\"html_url\":\"https://x/c\",\"stargazers_count\":3,\"language\":\"\",\"updated_at\":\"\"}]"
  let out1 = random(repos, 2, seed=123UL)
  let out2 = random(repos, 2, seed=123UL)
  let same = out1 == out2
  assert_true(same)                 // 同 seed → 结果一致（确定性）
  assert_true(out1.contains("2 个项目"))
  assert_true(out1.contains("c"))   // 抽到了 c
  assert_true(out1.contains("a"))   // 抽到了 a
}

test {
  // random：count 超过数量时全部返回（去重，不重复抽）
  let repos = "[{\"name\":\"a\",\"description\":\"\",\"html_url\":\"https://x/a\",\"stargazers_count\":1,\"language\":\"\",\"updated_at\":\"\"},{\"name\":\"b\",\"description\":\"\",\"html_url\":\"https://x/b\",\"stargazers_count\":2,\"language\":\"\",\"updated_at\":\"\"}]"
  let out = random(repos, 99, seed=42UL)
  assert_true(out.contains("2 个项目"))
  assert_true(out.contains("a"))
  assert_true(out.contains("b"))
}

test {
  // random：count 非法（<=0）时回退默认 3
  let repos = "[{\"name\":\"a\",\"description\":\"\",\"html_url\":\"https://x/a\",\"stargazers_count\":1,\"language\":\"\",\"updated_at\":\"\"},{\"name\":\"b\",\"description\":\"\",\"html_url\":\"https://x/b\",\"stargazers_count\":2,\"language\":\"\",\"updated_at\":\"\"},{\"name\":\"c\",\"description\":\"\",\"html_url\":\"https://x/c\",\"stargazers_count\":3,\"language\":\"\",\"updated_at\":\"\"},{\"name\":\"d\",\"description\":\"\",\"html_url\":\"https://x/d\",\"stargazers_count\":4,\"language\":\"\",\"updated_at\":\"\"},{\"name\":\"e\",\"description\":\"\",\"html_url\":\"https://x/e\",\"stargazers_count\":5,\"language\":\"\",\"updated_at\":\"\"}]"
  let out = random(repos, -1, seed=7UL)
  assert_true(out.contains("3 个项目"))
}

test {
  // compare：按编号对比，包含两个项目名与星数
  let repos = "[{\"name\":\"alpha\",\"description\":\"a lib\",\"html_url\":\"https://x/a\",\"stargazers_count\":68,\"language\":\"MoonBit\",\"updated_at\":\"\"},{\"name\":\"beta\",\"description\":\"b tool\",\"html_url\":\"https://x/b\",\"stargazers_count\":12,\"language\":\"Rust\",\"updated_at\":\"\"}]"
  let out = compare(repos, "1", "2")
  assert_true(out.contains("alpha  vs  beta"))
  assert_true(out.contains("⭐68"))
  assert_true(out.contains("⭐12"))
  assert_true(out.contains("alpha 更受欢迎"))
}

test {
  // compare：按名称对比 + 星数判断反向
  let repos = "[{\"name\":\"alpha\",\"description\":\"\",\"html_url\":\"https://x/a\",\"stargazers_count\":5,\"language\":\"\",\"updated_at\":\"\"},{\"name\":\"beta\",\"description\":\"\",\"html_url\":\"https://x/b\",\"stargazers_count\":99,\"language\":\"\",\"updated_at\":\"\"}]"
  let out = compare(repos, "alpha", "beta")
  assert_true(out.contains("beta 更受欢迎"))
}

test {
  // compare：编号越界给出明确提示
  let repos = "[{\"name\":\"alpha\",\"description\":\"\",\"html_url\":\"https://x/a\",\"stargazers_count\":5,\"language\":\"\",\"updated_at\":\"\"},{\"name\":\"beta\",\"description\":\"\",\"html_url\":\"https://x/b\",\"stargazers_count\":9,\"language\":\"\",\"updated_at\":\"\"}]"
  assert_true(compare(repos, "9", "2").contains("找不到项目: 9"))
  assert_true(compare(repos, "alpha", "nope").contains("找不到项目: nope"))
}

test {
  // compare：项目少于 2 个时提示
  let repos = "[{\"name\":\"only\",\"description\":\"\",\"html_url\":\"https://x/o\",\"stargazers_count\":1,\"language\":\"\",\"updated_at\":\"\"}]"
  assert_true(compare(repos, "1", "1").contains("至少需要 2 个项目"))
}
