# 100 Days of MoonBit

按天推进的系统学习路线，**python-100-days 风格**：每天一篇完整教程文章——概念引入、代码分段讲解、常见坑、动手练习、今日小结，像读博客一样一天一篇。
适合想从头系统学、靠节奏感坚持的人。想按主题查内容？去 [MoonBit by Example](../examples/README.md)（go-by-example 风格，查字典用）。

## 双入口说明

MoonHive 学习库提供两种进入方式，**同一批示例，两种学法**：

| 入口 | 风格 | 组织方式 | 适合谁 |
|---|---|---|---|
| [By Example](../examples/README.md) | go-by-example 极简示例页 | 按主题查：想学 match 直接打开 match 示例 | 有明确目标、查字典式学习 |
| **100 Days（本目录）** | python-100-days 每日教程 | 按天走：Day 1 → Day 25 顺着学，每天一篇完整文章 | 从头系统学、打卡式坚持 |

## 怎么用

1. 每天读一篇 `DayNN.md`（约 40–60 分钟，像读一篇博客）
2. 跟着正文逐段理解概念，示例代码**自己动手运行一遍**
3. 做文末的动手练习——练习 1/2 要真的跑，练习 3 先猜再验证
4. 完成自我检查清单——卡住的问题记下来，比"看懂了"更有用

## 目录

### 阶段 1 · 基础（Day 01–10）

| Day | 主题 | 对应示例 | 状态 |
|---|---|---|---|
| [01](Day01.md) | Hello, MoonBit! · 入口与 println | [hello](../examples/hello/) | ✅ |
| [02](Day02.md) | 变量与绑定 · let / let mut | [variables](../examples/variables/) | ✅ |
| [03](Day03.md) | 基本类型 | [types](../examples/types/) | ✅ |
| [04](Day04.md) | 函数 | [functions](../examples/functions/) | ✅ |
| [05](Day05.md) | 控制流 · if / match / while | [control](../examples/control/) | ✅ |
| 06 | 元组 | 规划中 | |
| 07 | 数组 | 规划中 | |
| 08 | 结构体 | 规划中 | |
| 09 | 枚举与模式匹配 | 规划中 | |
| 10 | Trait 接口 | 规划中 | |

### 阶段 2 · 进阶（Day 11–20）· 规划中

trait-impl / generics / option / result / iter / string / json / cli / files / tests

### 阶段 3 · 实战（Day 21–25）· 规划中

plugin / base64 / date / sort / wasm

## 目录约定

| 文件 | 作用 |
|---|---|
| `DayNN.md` | 当天学习路径：目标 → 步骤 → 要点 → 练习 → 打卡 |

> 每个 Day 的代码与讲解复用 examples/ 下对应示例，本目录只做"怎么学"的引导。
