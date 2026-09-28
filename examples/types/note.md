# 03 · 基本类型

五种基本类型：整数、浮点、字符串、布尔、字符。

## 代码

```moonbit
fn main {
  let n: Int = 42
  let pi: Float = 3.14
  let name: String = "MoonBit"
  let ok: Bool = true
  let letter: Char = 'M'
  let inferred = 2026

  println("n = \{n}")
  println("pi = \{pi}")
  println("name = \{name}")
  println("ok = \{ok}")
  println("letter = \{letter}")
  println("inferred = \{inferred}")
}
```

## 运行

```bash
moon run main.mbt --target-dir <纯ASCII临时目录>
```

## 输出

```
n = 42
pi = 3.140000104904175
name = MoonBit
ok = true
letter = M
inferred = 2026
```

## 要点

- **Int** 32 位整数、**Float** 64 位浮点、**String** 文本、**Bool** 布尔、**Char** 单个字符（单引号）
- 类型可以显式标注（`let n: Int = 42`），也可以靠字面量推断（`let inferred = 2026` 自动是 Int）
- `pi = 3.140000104904175` 不是 bug：Float 按完整精度打印，`3.14` 的二进制表示有微小误差
- 字符串插值用 `\{expr}`，把表达式的结果嵌进字符串

> ✅ Verified by MoonHive（真实 MoonBit 工具链实测）
