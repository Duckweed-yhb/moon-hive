# Day 04 · 函数：把一段逻辑装进一个名字

> 对应示例：[examples/functions](../examples/functions/)
> 预计用时：50 分钟

## 今天学什么

程序写多了，同一段计算会在很多地方重复出现。函数就是给一段逻辑起个名字，以后按名字调用。今天学 MoonBit 定义函数的三个规矩：参数要标类型、函数体最后一个表达式就是返回值、没有返回值的函数要写 `-> Unit`。第三条是我自己写代码时踩过的坑，今天拆开讲。

## 一、定义一个函数

打开 [examples/functions/main.mbt](../examples/functions/main.mbt)：

```moonbit
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
```

输出：

```
double(21) = 42
add(3, 4) = 7
Hello, Duckweed!
```

## 二、三个规矩，逐个看

**规矩 1：参数必须标类型。**

```moonbit
fn double(x: Int) -> Int
```

`x: Int` 表示"这个函数收一个叫 x 的整数"。MoonBit 不允许省略参数类型，`fn double(x)` 直接编译不过。原因是类型系统需要知道每个参数能做什么运算，写清楚类型，编译器才能检查你的调用有没有传错。

**规矩 2：函数体最后一个表达式就是返回值，不用写 return。**

```moonbit
fn double(x: Int) -> Int {
  x * 2
}
```

`double` 的函数体只有一行 `x * 2`，这一行就是它的返回值。调用 `double(21)` 得到 42。这不是"省略 return"，而是 MoonBit 的设计：函数体的值就是函数的值。读代码时看到函数体最后一行，基本就是在看这个函数会返回什么。

**规矩 3：没有返回值的函数，要写 `-> Unit`。**

```moonbit
fn greet(name: String) -> Unit {
  println("Hello, \{name}!")
}
```

`greet` 只打印一行，不返回任何有用的值。这种函数在 MoonBit 里要写 `-> Unit`，表示"这个函数没有返回值"（`Unit` 可以理解成"没有值"的类型）。**`main` 入口是唯一的例外，可以省略**。我最早写函数时漏了 `-> Unit`，编译器报错说返回类型不匹配，当时完全没看懂，后来才明白：不是所有函数都必须返回点什么，明确说"我不返回"和什么都不写，在 MoonBit 里是两回事。

## 三、函数定义顺序

注意 `main` 在文件最上面，`double` / `add` / `greet` 定义在它后面。这能跑吗？能。MoonBit 会先收集文件里的全部声明再编译，所以**先调用后定义没关系**，你不需要像某些语言那样把函数排在调用之前。把函数放在文件底部、main 放最上面，读代码时先看到主线再看到细节，是常见的组织方式。

## 四、动手练习（12 分钟）

**练习 1（动手）**：写一个求较大的数的函数，然后调用它：

```moonbit
fn max(a: Int, b: Int) -> Int {
  if a > b { a } else { b }
}

fn main {
  println("max(3, 7) = \{max(3, 7)}")
}
```

注意 `if a > b { a } else { b }`：if 的两个分支分别返回 `a` 和 `b`，整个 if 的值就是 `max` 的返回值。这就是 Day 05 会展开讲的"if 是表达式"。

**练习 2（故意犯错）**：把 `greet` 的 `-> Unit` 删掉再运行。报错会出现在 `greet` 的定义处，大意是返回类型不匹配。记住这个报错的样子，下次见到就知道是漏了 `-> Unit`。

**练习 3（思考）**：`println` 本身有没有返回值？试试 `let r = println("hi")` 能不能编译。能猜对最好，猜错也没关系，重点是想清楚"打印一行"和"返回一个值"是两件事。

## 今日小结

- `fn 名字(参数: 类型) -> 返回类型 { ... }` 是函数的基本形状
- 参数必须标类型
- 函数体最后一个表达式就是返回值，不用 return
- 没有返回值的函数写 `-> Unit`，`main` 入口除外
- 函数定义顺序无关，可以先调用后定义

## 自我检查

- [ ] 我能不查资料写出一个带参数、带返回值的函数
- [ ] 我能解释为什么 `greet` 要写 `-> Unit`
- [ ] 我把练习 2 的报错读了一遍，下次能认出"漏了 -> Unit"

> ✅ 本示例已由 MoonHive 验证引擎实测（真实 MoonBit 工具链编译运行，输出与 expected.txt 一致）
