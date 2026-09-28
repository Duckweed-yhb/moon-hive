# 05 · 控制流

`if` / `match` / `while` 三件套。重点：`if` 和 `match` 是表达式，有值。

## 代码

```moonbit
fn main {
  let score = 85
  let grade = if score >= 90 {
    "A"
  } else if score >= 60 {
    "B"
  } else {
    "C"
  }
  println("score = \{score}, grade = \{grade}")

  let day = "Mon"
  let cn = match day {
    "Mon" => "周一"
    "Tue" => "周二"
    "Wed" => "周三"
    _ => "其他"
  }
  println("day = \{day}, 中文 = \{cn}")

  let mut i = 0
  let mut sum = 0
  while i < 5 {
    sum = sum + i
    i = i + 1
  }
  println("sum(0..<5) = \{sum}")
}
```

## 运行

```bash
moon run main.mbt --target-dir <纯ASCII临时目录>
```

## 输出

```
score = 85, grade = B
day = Mon, 中文 = 周一
sum(0..<5) = 10
```

## 要点

- **if 是表达式**：每个分支返回同一个类型的值，整个 `if` 的结果直接赋给 `grade`
- **match 是表达式**：按值分支，`=>` 左边是模式、右边是结果；`_` 是兜底；编译器要求覆盖所有情况（穷尽性检查）
- **while 循环**：条件为真就重复执行，配合 `let mut` 计数
- `sum(0..<5) = 10`：0 + 1 + 2 + 3 + 4，`<5` 表示不含 5

> ✅ Verified by MoonHive（真实 MoonBit 工具链实测）
