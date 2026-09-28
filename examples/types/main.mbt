/// 03 · 基本类型
///
/// MoonBit 常见的五种基本类型：整数、浮点、字符串、布尔、字符。
/// 类型可以靠字面量推断，也可以显式标注。

fn main {
  // Int：32 位有符号整数
  let n: Int = 42

  // Float：64 位双精度浮点
  let pi: Float = 3.14

  // String：文本
  let name: String = "MoonBit"

  // Bool：只有 true / false
  let ok: Bool = true

  // Char：单引号，存一个 Unicode 字符
  let letter: Char = 'M'

  // 通常可以靠字面量推断，不必都写出来
  let inferred = 2026

  println("n = \{n}")
  println("pi = \{pi}")
  println("name = \{name}")
  println("ok = \{ok}")
  println("letter = \{letter}")
  println("inferred = \{inferred}")
}
