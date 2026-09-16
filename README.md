# MoonHive

[![CI](https://github.com/Duckweed-yhb/moon-hive/actions/workflows/ci.yml/badge.svg)](https://github.com/Duckweed-yhb/moon-hive/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

> 每日 GitHub 项目投喂 · digest / summary / filter / keep / export / stats / random / compare · 纯 core 零依赖 · 51 个测试

参赛：MoonBit 2026 九月黑客松
赛道：应用与内容工具

## 📖 项目简介

项目名 MoonHive：Moon 代表 MoonBit，Hive（蜂巢）寓意插件如同蜂巢中的独立巢室，可持续扩展。
一句话描述项目：基于 MoonBit 实现的插件化 CLI 工具基座，采用"万物皆插件"架构；核心插件为 **Daily 每日 GitHub 项目投喂**（digest 推荐 / summary 摘要 / filter 筛选 / keep 收藏 / export 导出 / stats 统计 / random 随机 / compare 对比 + daily.ps1 数据管道），并内置 Base64、Hex 编解码示例插件，可持续扩展新插件。

### 背景与目标

- 解决的真实问题：零散命令行工具相互独立，难以统一管理；本项目提供统一 CLI 基座，新增功能只需开发独立插件并注册，无需改动基座核心代码。
- 项目边界（本次开发范围）：插件基座 + Base64 / Hex 字符串编解码插件 + **Daily 每日 GitHub 项目投喂插件**（digest 推荐 / summary 摘要 / filter 筛选 / keep 收藏 / export 导出 / stats 统计 / random 随机 / compare 对比 + daily.ps1 数据管道），配套 51 个单元测试与可运行 Demo。
- 不做什么：不实现运行时动态加载插件；文件编解码、Web、嵌入式、CTF 其余工具仅作为后续规划，本次不编码；不实现 TUI、配置文件、命令补全。

## ✨ 核心功能

- [x] 插件基座：插件 Trait 定义、静态插件注册、子命令调度、统一错误处理
- [x] Base64 插件：字符串编码 / 解码（标准 Base64，支持中文与空串）
- [x] Hex 插件：字符串编码 / 解码（UTF-8 字节 ↔ 十六进制文本）
- [x] **Daily 插件（每日 GitHub 项目投喂）**：digest 命令解析 GitHub API 项目 JSON，输出今日推荐卡片（名称 / 星数 / 语言 / 描述 / 链接 / 更新时间）；支持直接 JSON 或 Base64 编码输入，规避命令行引号问题
- [x] **summary 项目摘要**："这个项目在讲什么" —— 一句话摘要 + 话题标签（自研关键词提取，过滤停用词）+ 项目类型判断（框架/绑定/CLI/库…）+ 相对更新时间（今天/昨天/N 天前）
- [x] **stats 生态统计**：语言分布（条形图）/ 星数分档（0 / 1-10 / 11-100 / 101+）/ 更新活跃度（7 天 / 30 天 / 更久）/ 汇总（总星数 / 平均 / 最多）
- [x] **多因子推荐排序**：digest 默认按 score 打分排序（60% 星数 log 归一化 + 40% 新鲜度衰减），支持 `--sort stars` / `--sort updated` / `--sort none`
- [x] **keep 收藏管理**：按编号从推荐中选取项目，与旧收藏按 url 合并去重，输出最新收藏 JSON
- [x] **filter 多维筛选**：按语言（大小写不敏感）/ 最低星数 / 最高星数 / 关键词（名称或描述）组合过滤
- [x] **random 随机推荐**：不按分数、随机抽取 N 个项目（自研 LCG 伪随机，纯 core 零依赖），每天换换口味
- [x] **compare 项目对比**：两个项目（编号或名称）逐字段对比 + 结论（星数/语言/更新时间/描述/链接）
- [x] **export 导出**：收藏清单 → Markdown（按星数降序），可直接贴进 README / 备忘录
- [x] 配套数据管道 `daily.ps1`：拉取 GitHub Search API → 精简字段 → Base64 编码 → digest 展示 → 输入编号收藏 → 保存 favorites.json → 可选导出 Markdown（完整闭环）
- [x] 单元测试：51 个用例覆盖编码/解码往返、中文、空串、非法输入、JSON 解析、收藏去重、导出格式、多维筛选、推荐排序、随机抽取、项目对比、项目摘要与生态统计（`moon test` 全部通过）
- [ ] 可选扩展（本次不做，后续迭代）
  - Web 工具插件：HTTP 请求、JSON 格式化、URL 编解码
  - 电气嵌入式插件：电路计算器、仿真日志解析
  - CTF 密码插件：凯撒密码、ROT13、字符频率统计

## 🚀 快速开始

### 环境依赖

- MoonBit 工具链：>= v0.1.200（开发环境 v0.1.20260904）
- 其他依赖：无（仅使用 MoonBit core 标准库）

### 构建 & 运行

```bash
# 编译
moon build

# 列出所有插件
moon run cmd/main

# Base64 编码 / 解码
moon run cmd/main base64 encode "hello world"
moon run cmd/main base64 decode "aGVsbG8gd29ybGQ="

# Hex 编码 / 解码
moon run cmd/main hex encode "hello"
moon run cmd/main hex decode "68656c6c6f"

# 每日 GitHub 项目投喂（推荐用法：运行配套脚本 daily.ps1）
powershell -ExecutionPolicy Bypass -File daily.ps1

# 也可以直接调用 digest（参数为 JSON 文本或 Base64 编码的 JSON，--sort 可选）
moon run cmd/main daily digest '[{"name":"demo","stargazers_count":42,"language":"MoonBit"}]'
moon run cmd/main daily digest '<项目JSON>' --sort stars

# 收藏：从推荐中保留编号 1、3（可追加旧收藏 JSON 实现增量合并）
moon run cmd/main daily keep '<项目JSON>' '1,3' '[旧收藏JSON]'

# 项目摘要：这个项目在讲什么（一句话 + 话题 + 类型 + 更新时间）
moon run cmd/main daily summary '<项目JSON>'

# 生态统计：语言分布 / 星数分档 / 更新活跃度 / 汇总
moon run cmd/main daily stats '<项目JSON>'

# 筛选：按语言/星数/关键词组合过滤（支持大小写不敏感）
moon run cmd/main daily filter '<项目JSON>' --lang MoonBit --min 10 --max 100 --kw async

# 随机推荐：从列表中随机抽 N 个（--count 可选，默认 3）
moon run cmd/main daily random '<项目JSON>' --count 5

# 项目对比：两个项目按编号或名称对比
moon run cmd/main daily compare '<项目JSON>' 1 2

# 导出收藏为 Markdown
moon run cmd/main daily export '<收藏JSON>'
```

### 运行示例

```
$ moon run cmd/main
可用插件：
- base64: Base64 编码/解码插件：支持字符串与文件的编码/解码
- hex: 十六进制编解码插件：支持字符串的编码/解码

$ moon run cmd/main base64 encode "hello world"
aGVsbG8gd29ybGQ=

$ moon run cmd/main base64 decode "aGVsbG8gd29ybGQ="
hello world

$ moon run cmd/main hex encode "你好"
e4bda0e5a5bd

$ moon run cmd/main hex decode "e4bda0e5a5bd"
你好

$ powershell -ExecutionPolicy Bypass -File daily.ps1
================ MoonHive 每日项目投喂 ================
搜索条件: language:moonbit | 数量: 5 | 排序: updated
正在从 GitHub 拉取项目...

今日推荐（5 个项目）
──────────────────────────────────────────────
[1] stb-image  ⭐1  [MoonBit]
    STB‑Image FFI binding for MoonBit(native‑only). Decode PNG/JPEG/BMP/GIF/WebP/HDR/PSD/PIC.
    https://github.com/toadium/stb-image
    更新: 2026-09-14T07:20:03Z
...

要保留哪些项目？(输入编号如 1,3，回车跳过) 1,3
已保存收藏：2 个项目 → E:\...\moon-hive\favorites.json
导出 Markdown 清单？(y/n，默认 n) y
已导出 → E:\...\moon-hive\favorites.md
```

## 🏗️ 架构说明

三层结构，插件与外壳解耦：

```
┌─────────────────────────────────────────────┐
│ main.mbt（入口外壳，从不修改）                  │
│ 读参数 → 查找插件 → 调用 execute → 打印结果      │
└─────────────────────────────────────────────┘
                    │ 查找
                    ▼
┌─────────────────────────────────────────────┐
│ registry.mbt（插件注册表，加插件改一行）          │
│ [Base64Plugin::{}, HexPlugin::{}, DailyPlugin::{}] │
└─────────────────────────────────────────────┘
                    │ 实现同一个 Plugin Trait
                    ▼
┌──────────────────┬──────────────────────────┬─────────────────────┐
│ base64_plugin.mbt │ hex_plugin.mbt           │ daily_plugin.mbt    │
│ name/description/ │ name/description/        │ digest 推荐引擎      │
│ execute           │ execute                  │ JSON 解析 + Base64   │
└──────────────────┴──────────────────────────┴─────────────────────┘
```

- **Plugin Trait**（插件合同）：`name`、`description`、`execute(Self, command, args)` 三个方法
- **静态注册**：插件在编译期注册进注册表，避开 MoonBit 暂不支持运行时动态加载的限制

## 🧩 如何新增一个插件

以新增 `md5` 插件为例，只需两步，**main 一行不改**：

1. 新建 `md5_plugin.mbt`，实现 Plugin Trait：

```moonbit
pub(all) struct Md5Plugin {}

pub impl Plugin for Md5Plugin with name(_self) { "md5" }

pub impl Plugin for Md5Plugin with execute(_self, command, args) {
  // 实现你的命令逻辑，返回 String
}
```

2. 在 `registry.mbt` 注册表登记一行：

```moonbit
pub fn all_plugins() -> Array[&Plugin] {
  [Base64Plugin::{}, HexPlugin::{}, Md5Plugin::{}]
}
```

## 📁 目录结构

```
moon-hive/
├── moon.mod                # 模块定义（Duckweed/moon-hive）
├── moon.pkg                # 根包（占位，实际代码在 lib/）
├── lib/                    # 核心库包
│   ├── moon.pkg            # 包配置（导入 core：utf8 / env / json / math / string）
│   ├── plugin.mbt          # Plugin Trait 定义
│   ├── registry.mbt        # 插件注册表与查找
│   ├── base64_plugin.mbt   # Base64 插件
│   ├── base64_test.mbt     # Base64 单元测试
│   ├── hex_plugin.mbt      # Hex 插件
│   ├── hex_test.mbt        # Hex 单元测试
│   ├── daily_plugin.mbt    # Daily 插件（推荐/摘要/筛选/收藏/导出/统计 + 排序引擎）
│   └── daily_plugin_test.mbt  # Daily 插件单元测试
├── cmd/
│   └── main/
│       ├── moon.pkg        # 可执行包配置（导入 lib 包）
│       └── main.mbt        # CLI 入口（调度外壳）
├── daily.ps1               # 数据管道脚本（GitHub API → Base64 → digest → 收藏）
├── .github/workflows/ci.yml  # GitHub Actions：build + test
├── README.md
└── LICENSE                 # MIT
```

## 💻 技术实现与 MoonBit 使用亮点

- MoonBit 特性：Trait 定义插件统一接口、强类型系统保障接口约束、core 标准库（UTF-8 编解码 / JSON 解析）、静态注册表。
- 核心模块设计：
  1. 插件基座：定义统一 Plugin Trait，维护插件注册表，解析 CLI 参数并分发至对应插件。
  2. Base64 插件：独立模块，实现标准 Base64 编码 / 解码（3 字节 → 4 字符，位运算分组）。
  3. Hex 插件：独立模块，实现 UTF-8 字节与十六进制文本互转。
  4. Daily 插件：解析 GitHub API 项目 JSON（core `@json` 模式匹配安全取值），输出结构化推荐卡片；支持 Base64 编码输入，规避命令行引号/空格问题。
- 难点与解决方案：采用**静态编译期注册插件**，避开 MoonBit 暂不支持运行时动态加载的限制；**数据管道与算法引擎分工**——GitHub API 拉取与字段精简由 `daily.ps1`（系统脚本）负责，推荐解析与展示由 MoonBit 纯 core 实现（零第三方依赖）。

## 🗺️ Roadmap

- [x] 插件基座 + Base64 / Hex 插件（首个闭环）
- [x] Daily 每日 GitHub 项目投喂：digest / keep / export（数据管道闭环）
- [x] filter 多维筛选 + summary 项目摘要 + 多因子推荐排序
- [x] stats 生态统计（语言分布 / 星数分档 / 更新活跃度）
- [x] random 随机推荐 + compare 项目对比
- [ ] daily.ps1 参数化（--sort / --filter 透传）与一键导出

## 🤖 AI 参与说明（赛事必填）

赛事要求：可使用 AI 辅助，但必须写清楚 AI 参与范围，参赛人掌握全部逻辑。
- AI 参与部分：代码片段生成、文档撰写、测试用例构思
- 参赛者掌握：全部业务逻辑、代码结构，能够完整解释所有实现细节
- 未直接复制成品，全部代码经过人工审阅、修改、调试
