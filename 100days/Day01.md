# Day 01 · 初识 MoonBit：你的第一个程序

> 对应示例：[examples/hello](../examples/hello/)
> 预计用时：40 分钟

## 今天学什么

任何一个语言学习之旅都从"让程序跑起来"开始。今天的目标很具体：**写出并运行你的第一个 MoonBit 程序**，同时搞明白三件基础但关键的事——程序从哪开始执行、怎么把内容打印到屏幕上、字符串是什么。

MoonBit 是一门新的编程语言，官方定位是"面向云计算与 WebAssembly 的现代语言"。你不需要现在理解这句话的全部含义，只要知道：它的语法干净、类型系统强，而且正在快速成长。今天先把门推开。

## 一、程序入口：一切从 `fn main` 开始

打开 [examples/hello/main.mbt](../examples/hello/main.mbt)，完整的程序只有 8 行：

```moonbit
/// 01 · Hello, MoonBit!
///
/// 每一个 MoonBit 程序都从这里开始。
/// `fn main` 是程序入口，`println` 把一行文本打到标准输出。

fn main {
  println("Hello, MoonBit!")
}
```

`fn` 是"函数"的意思（function），`main` 是函数的名字。在 MoonBit 里，**`main` 是约定的程序入口**——当你运行一个程序时，运行时就从 `fn main` 开始执行，执行完就结束。

你可以把 `fn main { ... }` 想成一段"从这里开始做事"的代码块。大括号 `{}` 圈住的部分，是 main 函数要执行的语句。

> 小知识：前几行以 `///` 开头的叫**文档注释**——它们不是代码，是给人读的说明。编译器会忽略它们，但好的注释能帮别人（包括未来的你）快速理解代码在干什么。

## 二、`println`：把内容打印到屏幕

```moonbit
  println("Hello, MoonBit!")
```

`println` 是 MoonBit 提供的**输出函数**：把括号里的内容打印到标准输出（也就是你的终端/命令行窗口），并且**自动换行**。

试着想一下：如果一行里有两个 `println`，输出会是两行还是挤在一行？答案是两行——`println` 每次打印完都会换行。这点和很多语言的 `print`（不换行）不同，写代码时要记得。

## 三、字符串：用双引号包起来的文本

`"Hello, MoonBit!"` 是一个**字符串字面量**（string literal）——用双引号 `"` 包裹的一串字符。字符串里可以是字母、数字、中文、标点，几乎任何你想表达的文字。

```moonbit
println("中文也完全没问题")
```

注意：字符串必须用**英文双引号**，不是中文引号。这是新手最常见的第一个报错来源。

## 四、运行你的程序

在 `examples/hello` 目录下运行：

```bash
moon run main.mbt --target-dir C:\Users\yhb\AppData\Local\Temp\mh-day01
```

如果一切正常，你会看到：

```
Hello, MoonBit!
```

这里有个 **Windows 特有的坑**：如果项目路径含有中文（比如 `E:\future\yhb\03-竞赛\moon-hive`），直接 `moon run` 会因 GNU assembler 无法处理中文路径而失败。`--target-dir` 参数把编译产物放到一个纯 ASCII 目录（如系统临时目录），就能绕开这个问题。仓库里的 `build.ps1` 就是为此存在的。

## 五、动手练习（10 分钟）

**练习 1**：把 `println` 里的内容改成你自己的昵称，运行验证：

```moonbit
println("Hello, Duckweed!")
```

**练习 2**：用两个 `println` 打印两行内容，观察输出的顺序和换行：

```moonbit
println("第一行")
println("第二行")
```

**练习 3（思考）**：如果把两个字符串放进**一个** `println` 里会怎样？比如 `println("Hello, " "MoonBit!")`——先猜，再试。报错也没关系，读一读报错信息，这是学习的一部分。

## 今日小结

- `fn main` 是程序入口，程序从这里开始执行
- `println(...)` 打印一行并自动换行
- 字符串用英文双引号包裹
- 代码文件通常叫 `main.mbt`，放在有 `moon.pkg`（executable 类型）的目录下
- Windows 下中文路径要配 `--target-dir` 或直接使用 `build.ps1`

## 自我检查

- [ ] 我运行出了 `Hello, MoonBit!`
- [ ] 我能说出 `println` 和"打印一行后换行"的关系
- [ ] 我把练习 3 试过了（无论成败），并读了一遍报错信息

> ✅ 本示例已由 MoonHive 验证引擎实测（真实 MoonBit 工具链编译运行，输出与 expected.txt 一致）
