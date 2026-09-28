/// 05 · 控制流
///
/// if / match / while 是控制流三件套。
/// 注意：if 和 match 是"表达式"——它们有值，可以直接赋给变量。

fn main {
  // if 是表达式：每个分支返回同一个类型的值
  let score = 85
  let grade = if score >= 90 {
    "A"
  } else if score >= 60 {
    "B"
  } else {
    "C"
  }
  println("score = \{score}, grade = \{grade}")

  // match 按值分支：必须覆盖所有情况，_ 是兜底
  let day = "Mon"
  let cn = match day {
    "Mon" => "周一"
    "Tue" => "周二"
    "Wed" => "周三"
    _ => "其他"
  }
  println("day = \{day}, 中文 = \{cn}")

  // while 循环：条件满足就重复执行
  let mut i = 0
  let mut sum = 0
  while i < 5 {
    sum = sum + i
    i = i + 1
  }
  println("sum(0..<5) = \{sum}")
}
