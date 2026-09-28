# Day 01 · Hello, MoonBit!

> 对应示例：[examples/hello](../examples/hello/)
> 主题：程序入口与 println

## 今天学什么

跑通你的第一个 MoonBit 程序。搞清楚三件事：入口在哪、`println` 做什么、字符串长什么样。

## 步骤

1. **读示例**：打开 [main.mbt](../examples/hello/main.mbt)，一共 8 行，先自己猜每行在干什么
2. **运行它**：

```bash
cd examples/hello
moon run main.mbt --target-dir C:\Users\yhb\AppData\Local\Temp\mh-day01
```

3. **验证输出**：屏幕上出现 `Hello, MoonBit!` 就成功了。把 `expected.txt` 打开对比，应该一字不差

## 要点

- `fn main { ... }` 是程序入口——`moon run` 就是从这里开始执行的
- `println(...)` 打印一行文本，**自带换行**
- 字符串用双引号 `"..."` 包裹
- 文件按惯例叫 `main.mbt`，放在有 `moon.pkg`（executable 类型）的目录下

## 动手练习（5 分钟）

改 `println` 里的内容，让它打印你自己的昵称，比如：

```moonbit
println("Hello, Duckweed!")
```

然后试着**一次打印两行**：

```moonbit
println("第一行")
println("第二行")
```

看看输出是什么顺序？为什么？

> 答案：两行各打各的，`println` 每次自带换行，所以输出是两行。如果你想让两句在同一行，可以用 `print(...)`（不换行）——今天先记住这个区别就行。

## 打卡

- [ ] 我运行出了 `Hello, MoonBit!`
- [ ] 我改成了自己的昵称并跑通了
- [ ] 卡住的问题：______________________
