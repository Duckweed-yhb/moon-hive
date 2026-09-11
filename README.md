# MoonHive
参赛：MoonBit 2026 九月黑客松
赛道：应用与内容工具

## 📖 项目简介
项目名 MoonHive：Moon 代表 MoonBit，Hive（蜂巢）寓意插件如同蜂巢中的独立巢室，可持续扩展。
一句话描述项目：基于 MoonBit 实现插件化CLI工具基座，采用万物皆插件架构，首期实现 Base64、Hex 编解码插件，后续可扩展Web、电气嵌入式、CTF类工具插件。

### 背景与目标
- 解决的真实问题：零散命令行工具相互独立，难以统一管理；本项目提供统一CLI基座，新增功能只需开发独立插件，无需改动基座核心代码。
- 项目边界（本次开发范围）：实现插件基座 + Base64 / Hex 编解码插件，配套单元测试与可运行Demo。
- 不做什么：不实现运行时动态加载插件；Web、嵌入式、CTF其余工具仅作为后续规划，本次不编码；不实现TUI、配置文件、命令补全。

## ✨ 核心功能
- [x] 插件基座：插件Trait定义、静态插件注册、子命令调度、统一错误处理
- [x] Base64 编解码插件：支持字符串、文件编码/解码
- [x] Hex 十六进制编解码插件：支持字符串、文件编码/解码
- [x] 基础单元测试
- [ ] 可选扩展（本次hackathon不做，后续迭代）
  - Web工具插件：HTTP请求、JSON格式化、URL编解码
  - 电气嵌入式插件：电路计算器、仿真日志解析
  - CTF密码插件：凯撒密码、ROT13、字符频率统计

## 🚀 快速运行
### 环境依赖
- MoonBit 版本：>= v0.1.200
- 其他依赖：无

### 构建 & 执行
```bash
# 编译
moon build

# 运行示例
# Base64编码字符串
moon run src/main.mbt base64 encode "hello world"
# Base64解码
moon run src/main.mbt base64 decode "SGVsbG8gV29ybGQ="
# Hex编码
moon run src/main.mbt hex encode "hello"
# Hex解码
moon run src/main.mbt hex decode "68656c6c6f"

# 执行单元测试
moon test
```

演示示例
```
> moon run src/main.mbt base64 encode "hello world"
aGVsbG8gd29ybGQ=
```

## 🧪 测试说明
测试覆盖模块：插件基座调度模块、Base64插件、Hex插件
测试文件位置：test/
如何执行：`moon test`

## 💻 技术实现与 MoonBit 使用亮点
- MoonBit 特性：使用Trait定义插件统一接口，包管理mooncake，强类型系统保障插件接口约束，内置文件IO与字符串处理。
- 核心模块设计
  1. 插件基座：定义统一插件Trait，维护插件注册表，解析CLI参数并分发任务至对应插件。
  2. Base64插件：独立模块，实现标准Base64编码、解码，支持字符串与文件输入输出。
  3. Hex插件：独立模块，实现十六进制字符串互转。
- 难点与解决方案：采用**静态编译期注册插件**，避开MoonBit暂不支持运行时动态加载的限制，在保持插件化架构思想前提下降低工程难度。

## 🤖 AI 参与说明（赛事必填！AI可解释项）
赛事要求：可使用AI辅助，但必须写清楚AI参与范围，参赛人掌握全部逻辑
AI参与部分：代码片段生成、文档撰写、测试用例构思
参赛者掌握：全部业务逻辑、代码结构，能够完整解释所有实现细节
未直接复制成品，全部代码经过人工审阅、修改、调试

## 📜 开源合规
License：MIT
第三方依赖：无mooncake外部依赖
移植说明：本项目为原创实现

## 📅 开发记录
仓库commit保留完整开发记录，Issues记录需求迭代
开发周期：9月11日 — 9月24日
仓库地址：https://github.com/Duckweed-yhb/moon-hive

## 👥 团队信息
团队名称：Duckweed
成员：单人参赛
赛事群：已加入赛事交流群（满足奖金发放条件）

---
