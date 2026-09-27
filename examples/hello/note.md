# 01 · Hello, MoonBit!

第一个程序——向世界打个招呼。

## 代码

```moonbit
fn main {
  println("Hello, MoonBit!")
}
```

## 运行

```bash
moon run main
```

## 输出

```
Hello, MoonBit!
```

## 要点

- `fn main` 是每个可执行程序的入口，程序从这里开始执行
- `println(...)` 打印一行文本，自带换行
- 字符串用双引号 `"..."` 包裹，里面可以是任意字符
- 代码文件按惯例命名为 `main.mbt`，放在带 `moon.pkg`（executable 类型）的目录下

> ✅ Verified by MoonHive（真实 MoonBit 工具链实测）
