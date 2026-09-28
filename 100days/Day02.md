# Day 02 · 变量与绑定

> 对应示例：[examples/variables](../examples/variables/)
> 主题：let / let mut 与字符串插值

## 今天学什么

MoonBit 里"变量"和别的语言不太一样：**默认只读**。今天搞懂 `let` 和 `let mut` 的区别——这是 MoonBit 帮你少写 bug 的第一个设计。

## 步骤

1. **读示例**：打开 [main.mbt](../examples/variables/main.mbt)，看 `let` 和 `let mut` 各在哪一行
2. **运行它**：

```bash
cd examples/variables
moon run main.mbt --target-dir C:\Users\yhb\AppData\Local\Temp\mh-day02
```

3. **对照输出**：`x = 42, y = 50`——想想 `y` 为什么是 50 不是 8

## 要点

- `let x = 42`：**不可变绑定**——绑一次，之后只读。想改？编译器会拦你
- `let mut y = 0`：**可变绑定**——可以重新赋值（`y = x + 8`）
- 字符串插值 `\{expr}`：把表达式的值嵌进字符串，比拼接 `"a" + b` 干净
- 默认不可变是刻意的：代码里"不会变的量"越多，越不容易被偷偷改出 bug

## 动手练习（5 分钟）

**练习 1**：把 `let x = 42` 后面加一行 `x = 100`，运行看看——编译器会报错。**这是好事**，读一读报错信息，它就是 MoonBit 在说"我帮你拦住了一个可能出问题的改动"。

**练习 2**：写一个程序：

```moonbit
fn main {
  let mut count = 0
  count = count + 1
  count = count + 1
  println("count = \{count}")
}
```

猜输出是什么，再运行验证。

> 答案：`count = 2`。`let mut` 允许 count 被连续加两次；如果这里用了 `let`，第二行就编译不过。

## 打卡

- [ ] 我跑出了 `x = 42, y = 50`
- [ ] 我故意写错 `let` 让编译器报错，并读懂了报错
- [ ] 卡住的问题：______________________
