# MoonBit by Example

MoonBit 语言**示例驱动**的主题素材库：每个示例 = 可运行代码 + 真实输出 + 要点讲解，
由 **MoonHive 验证引擎**逐个编译运行（✅ 标记 = 真实工具链实测，非手打输出）。

## 双入口说明

学习库提供两种进入方式，**同一批示例，两种学法**：

| 入口 | 组织方式 | 适合谁 |
|---|---|---|
| **By Example（本目录）** | 按主题查：想学 match 直接打开 match 示例 | 有明确目标、查字典式学习 |
| [100 Days](../100days/README.md) | 按天走：Day 1 → Day 25 顺着学，每天一个主题+练习 | 需要节奏感、打卡式坚持 |

## 如何运行示例

```bash
cd examples/hello
moon run main.mbt --target-dir <任意纯ASCII临时目录>
```

> 注：仓库路径含非 ASCII 字符（`03-竞赛`）时，GNU assembler 无法处理，
> 需用 `--target-dir` 指向纯 ASCII 目录（如 `C:\Users\yhb\AppData\Local\Temp\mh-examples`）。

## 示例清单

### 阶段 1 · 基础（语法入门，Day 01–10）

| Day | 示例 | 主题 | 状态 |
|---|---|---|---|
| 01 | [hello](hello/) | Hello, MoonBit! · 入口与 println | ✅ Verified |
| 02 | [variables](variables/) | 变量与绑定 · let / let mut | ✅ Verified |
| 03 | [types](types/) | 基本类型 | ✅ Verified |
| 04 | [functions](functions/) | 函数 | ✅ Verified |
| 05 | [control](control/) | 控制流 · if / match / while | ✅ Verified |
| 06 | tuples | 元组 | 规划中 |
| 07 | arrays | 数组 | 规划中 |
| 08 | structs | 结构体 | 规划中 |
| 09 | enums | 枚举与模式匹配 | 规划中 |
| 10 | trait | Trait 接口 | 规划中 |

### 阶段 2 · 进阶（Day 11–20）· 规划中

trait-impl / generics / option / result / iter / string / json / cli / files / tests

### 阶段 3 · 实战（Day 21–25）· 规划中

plugin / base64 / date / sort / wasm

## 目录约定

每个示例目录包含：

| 文件 | 作用 |
|---|---|
| `main.mbt` | 示例代码（可独立运行） |
| `moon.mod` + `moon.pkg` | 独立包声明（executable） |
| `expected.txt` | 期望输出（验证引擎比对用） |
| `note.md` | 讲解：标题 + 代码 + 输出 + 要点 |
