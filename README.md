# MoonHive

[![CI](https://github.com/Duckweed-yhb/moon-hive/actions/workflows/ci.yml/badge.svg)](https://github.com/Duckweed-yhb/moon-hive/actions/workflows/ci.yml)

参赛：MoonBit 2026 九月黑客松
赛道：应用与内容工具

## 📖 项目简介

项目名 MoonHive：Moon 代表 MoonBit，Hive（蜂巢）寓意插件如同蜂巢中的独立巢室，可持续扩展。
一句话描述项目：基于 MoonBit 实现的插件化 CLI 工具基座，采用"万物皆插件"架构，首期实现 Base64、Hex 字符串编解码插件，后续可扩展 Web、电气嵌入式、CTF 类工具插件。

### 背景与目标

- 解决的真实问题：零散命令行工具相互独立，难以统一管理；本项目提供统一 CLI 基座，新增功能只需开发独立插件并注册，无需改动基座核心代码。
- 项目边界（本次开发范围）：实现插件基座 + Base64 / Hex 字符串编解码插件，配套单元测试与可运行 Demo。
- 不做什么：不实现运行时动态加载插件；文件编解码、Web、嵌入式、CTF 其余工具仅作为后续规划，本次不编码；不实现 TUI、配置文件、命令补全。

## ✨ 核心功能

- [x] 插件基座：插件 Trait 定义、静态插件注册、子命令调度、统一错误处理
- [x] Base64 插件：字符串编码 / 解码（标准 Base64，支持中文与空串）
- [x] Hex 插件：字符串编码 / 解码（UTF-8 字节 ↔ 十六进制文本）
- [x] 单元测试：10 个用例覆盖编码/解码往返、中文、空串与非法输入（`moon test` 全部通过）
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
│ [Base64Plugin::{}, HexPlugin::{}]             │
└─────────────────────────────────────────────┘
                    │ 实现同一个 Plugin Trait
                    ▼
┌──────────────────┬──────────────────────────┐
│ base64_plugin.mbt │ hex_plugin.mbt           │
│ name/description/ │ name/description/        │
│ execute           │ execute                  │
└──────────────────┴──────────────────────────┘
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
├── moon.mod               # 模块定义（Duckweed/moon-hive）
├── moon.pkg               # 根包配置（导入 core UTF-8 库）
├── plugin.mbt             # Plugin Trait 定义
├── base64_plugin.mbt      # Base64 插件
├── hex_plugin.mbt         # Hex 插件
├── registry.mbt           # 插件注册表与查找
├── cmd/
│   └── main/
│       ├── moon.pkg       # 可执行包配置
│       └── main.mbt       # CLI 入口（调度外壳）
├── README.md
└── LICENSE                # MIT
```

## 💻 技术实现与 MoonBit 使用亮点

- MoonBit 特性：Trait 定义插件统一接口、强类型系统保障接口约束、core 标准库（UTF-8 编解码）、静态注册表。
- 核心模块设计：
  1. 插件基座：定义统一 Plugin Trait，维护插件注册表，解析 CLI 参数并分发至对应插件。
  2. Base64 插件：独立模块，实现标准 Base64 编码 / 解码（3 字节 → 4 字符，位运算分组）。
  3. Hex 插件：独立模块，实现 UTF-8 字节与十六进制文本互转。
- 难点与解决方案：采用**静态编译期注册插件**，避开 MoonBit 暂不支持运行时动态加载的限制，在保持插件化架构思想的前提下降低工程难度。

## 🤖 AI 参与说明（赛事必填）

赛事要求：可使用 AI 辅助，但必须写清楚 AI 参与范围，参赛人掌握全部逻辑。
- AI 参与部分：代码片段生成、文档撰写、测试用例构思
- 参赛者掌握：全部业务逻辑、代码结构，能够完整解释所有实现细节
- 未直接复制成品，全部代码经过人工审阅、修改、调试

## 📜 开源合规

- License：MIT
- 第三方依赖：无 mooncake 外部依赖（仅 core 标准库）
- 移植说明：本项目为原创实现

## 📅 开发记录

- 仓库 commit 保留完整开发记录
- 开发周期：9 月 11 日 — 9 月 24 日
- 仓库地址：https://github.com/Duckweed-yhb/moon-hive

## 👥 团队信息

- 团队名称：Duckweed
- 成员：单人参赛
- 赛事群：已加入赛事交流群（满足奖金发放条件）

---
