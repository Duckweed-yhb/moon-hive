# MoonHive

> **MoonBit 生态验证引擎** —— 用真实工具链验证生态中的包能不能真的用。

[![CI](https://github.com/Duckweed-yhb/moon-hive/actions/workflows/ci.yml/badge.svg)](https://github.com/Duckweed-yhb/moon-hive/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## 这个项目解决什么问题

想要用 MoonBit 生态里的某个包时，你通常只能看到它的名字和 star 数。**但 star 数不告诉你它能不能编译、测试过没过、依赖重不重、在你这套工具链上能不能跑。**

MoonHive 把候选项目真的拉到本地，在隔离工作区里用**真实的 MoonBit 工具链**检它们，然后把结论分类输出：

| 结论 | 含义 |
|---|---|
| ✅ `Verified` | 编译 + 测试全绿，拿过来就能用 |
| ⚠️ `TestFailing` | 能编译，但测试挂——代码在演进中，谨慎 |
| ❌ `DoesNotCompile` | 编译器报错，当前工具链上不可用 |
| 🚫 `ToolchainMismatch` | 诊断指向版本/API 不兼容——**不是包的错，是工具链版本差异** |
| 📦 `MissingDependency` | 依赖解析失败，不是自包含的 |
| 📄 `NoManifest` | 没有 `moon.mod`，不是 MoonBit 模块 |
| ⏱️ `Timeout` | 超时 |
| 🔒 `Unsafe` | 含 FFI / 构建脚本，只做静态分析 |

**为什么这件事必须由 MoonBit 来做**：判断"能不能真的用"需要握着工具链——要起子进程、要读编译器诊断、要管理真实工作区。这不是大模型对话能替代的，也不是 GitHub 搜索能给出的。

### 一个真实例子

`moonbitlang/x` 是 MoonBit 生态里最活跃的库之一（167 个 `.mbt` 文件、约 30,000 行、58 个测试文件）。但在这台开发机的工具链上：

```
$ moon check --target native
Failed with 0 warnings, 14 errors.
  Type Bytes has no method exact_view.
```

MoonHive 的价值就在于把这个结果**正确归类**：这不是"这个包坏了"，而是 `🚫 ToolchainMismatch`——它能在别的工具链版本上正常工作。分不清这一点，工具就会撒谎。

## 当前状态（诚实说明）

项目正在从 v1（每日项目投喂工具）重构为 v2（生态验证引擎）。**v1 的 Base64 / Hex / digest / 收藏 / 统计等功能已全部移除**——它们与"验证包能不能用"这条主线无关。

| 模块 | 状态 |
|---|---|
| `platform/proc` — FFI 进程执行 / 文件读写 | ✅ 已完成 |
| `core/error` — 统一错误契约 | ✅ 已完成 |
| `features/doctor` — 环境自检 | ✅ 已完成 |
| `verify/*` — 工作区 / 工具链驱动 / 诊断分类 | 🚧 开发中 |
| `report/*` — 报告与公开静态站 | 🚧 开发中 |

## 快速开始

### 环境要求

- MoonBit 工具链（开发环境 `moon 0.1.20260904`）
- git（用于获取待验证的仓库）
- **构建产物路径必须为纯 ASCII**——GNU assembler 无法处理含非 ASCII 字符的路径。
  仓库自带 `build.ps1` 会自动把产物重定向到系统临时目录，因此直接用它即可：

```powershell
./build.ps1              # 构建
./build.ps1 -Test        # 构建 + 测试
./build.ps1 -Run doctor  # 构建 + 运行 moonhive doctor
```

  手工构建时需显式指定纯 ASCII 的产物目录：

```bash
moon build --target native --release --target-dir /path/to/ascii/dir
```

> Windows 上还需确认 git 的 TLS 后端可用。`moonhive doctor` 会自动检测并给出修复建议
> （常见情况：系统配置了 `http.sslBackend = schannel` 而该后端不可用，
> 执行 `git config --global http.sslBackend openssl` 即可）。

### 运行

```bash
moon run cmd/moonhive --target native -- doctor
```

### 环境自检

```bash
$ moonhive doctor

MoonHive 环境自检
────────────────────────────────────────────────────
[ OK ] MoonBit 工具链
       moon 0.1.20260904 (94521db 2026-09-04)
[ OK ] git
       git version 2.51.1.windows.1
[WARN] git TLS 连通性
       当前 git 配置的 TLS 后端不可用，但 openssl 后端可用。建议执行: git config --global http.sslBackend openssl
[ OK ] 临时目录
       C:\Users\yhb\AppData\Local\Temp
────────────────────────────────────────────────────
结果: 3 项通过, 1 项警告, 0 项失败
```

自检的意义：验证结论只有在环境正确时才有意义。doctor 把"看起来失败，其实是环境问题"这类误判挡在前面。

## 架构

```
cmd/moonhive           CLI 入口，只做参数解析与分发
core/error             统一错误契约 + 退出码映射（纯计算，无平台依赖）
core/text              字符串 / 路径 / 表格渲染工具
platform/proc    ⭐     FFI：子进程执行、输出捕获、文件读写
platform/fs      ⭐     FFI：目录遍历、大小统计、清理
verify/workspace ⭐     隔离工作区生命周期 + 磁盘配额 + 并发调度
verify/check     ⭐     工具链驱动（moon check / build / test）
verify/diagnose  ⭐⭐   编译器诊断解析 → 失败分类
verify/report           结构化结果 + 人类可读结论
report/*                本地报告 / JSON 输出 / 公开静态站
features/*              命令实现（survey / inspect / doctor）
```

**分层边界（可替换性声明）**：
- 只有 `platform/*` 允许出现 C FFI。想换掉底层实现，只需替换这两个包。
- 只有 `verify/check` 知道如何调用 `moon` 命令。
- `core/*` 与 `report/*` 不知道文件系统与进程的存在，因此可以 100% 单元测试。

**为什么用 C FFI**：`moonbitlang/core` 不提供文件系统与进程模块（它们只在第三方的 `moonbitlang/async` 中）。本项目的核心能力——起进程跑工具链、读编译器诊断——必须依赖它们，因此自建 FFI 层而不是引入第三方包。

**为什么只在 native 后端构建**：C FFI 不支持 wasm 后端。这是有意的架构选择：本工具是本地 CLI，不需要在浏览器或 wasm 运行时里跑。

## 安全说明

验证陌生代码有固有风险，MoonHive 的策略是：

1. **永不执行仓库自带的构建脚本**——只调用 MoonBit 官方工具链的 `check` / `build` / `test`
2. 所有验证在**一次性临时工作区**内进行，结束后可一键清理
3. 设超时上限与磁盘配额
4. 含 FFI 或自定义构建脚本的仓库**只做静态分析**，不执行

## 许可证

MIT
