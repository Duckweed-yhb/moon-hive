# 04 · 函数

`fn` 定义函数，参数必须标注类型。

## 代码

```moonbit
fn main {
  println("double(21) = \{double(21)}")
  println("add(3, 4) = \{add(3, 4)}")
  greet("Duckweed")
}

fn double(x: Int) -> Int {
  x * 2
}

fn add(a: Int, b: Int) -> Int {
  a + b
}

fn greet(name: String) -> Unit {
  println("Hello, \{name}!")
}
```

## 运行

```bash
moon run main.mbt --target-dir <纯ASCII临时目录>
```

## 输出

```
double(21) = 42
add(3, 4) = 7
Hello, Duckweed!
```

## 要点

- 函数体**最后一个表达式就是返回值**，不需要 `return`（`x * 2` 就是 `double` 的返回值）
- 有返回值写 `-> Int` 这样的返回类型；没有返回值写 `-> Unit`（`main` 入口除外）
- 函数先定义后使用，或者定义在调用之后也没关系（MoonBit 会先收集全部声明）

> ✅ Verified by MoonHive（真实 MoonBit 工具链实测）
