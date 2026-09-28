/// 04 · 函数
///
/// `fn` 定义函数：参数要写类型，有返回值就写返回类型。
/// 没有返回值的函数要写 `-> Unit`（main 入口除外）。

fn main {
  println("double(21) = \{double(21)}")
  println("add(3, 4) = \{add(3, 4)}")
  greet("Duckweed")
}

// 一个参数，返回 Int
fn double(x: Int) -> Int {
  x * 2
}

// 两个参数
fn add(a: Int, b: Int) -> Int {
  a + b
}

// 没有返回值：要写 -> Unit（main 入口除外）
fn greet(name: String) -> Unit {
  println("Hello, \{name}!")
}
