# MoonHive

[![CI](https://github.com/Duckweed-yhb/moon-hive/actions/workflows/ci.yml/badge.svg)](https://github.com/Duckweed-yhb/moon-hive/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**MoonBit 工具链输出的诊断归因库。** 可被任何 MoonBit 项目 import，在 `wasm` / `wasm-gc` / `js` / `native` 四个后端都能编译运行；附带的 CLI 只是它的参考消费者。

给它一段 `moon check` 的输出，它告诉你这堆错误到底意味着什么——是包真的坏了，还是你的工具链版本对不上。

每个快速演进的语言生态最后都会长出这类工具：Rust 有 `cargo-msrv` 与 `cargo-semver-checks`，Java 有 Revapi。**MoonBit 还没有**——这是这个库存在的理由。

```moonbit
// 库核心与平台能力完全解耦：这里不 import 任何 C FFI 包
let outcome : @diagnose.CheckOutcome = { .. }
match @diagnose.classify(outcome) {
  ToolchainMismatch(why) => println("不是包的错：" + why)
  DoesNotCompile(why)    => println("包在当前工具链上不可用：" + why)
  Verified               => println("可以直接用")
  _                      => ()
}
```

star 数告诉你包火不火，MoonHive 告诉你包能不能用。

## 为什么归因是独立的一件事

`moon check` 失败只给你一个非零退出码和一堆错误文本。**把错误文本读成结论，才是难点**：

实测 `moonbitlang/x`（生态里最活跃的库之一，167 个 `.mbt` 文件）在某台工具链上：

```
$ moon check --target native
Failed with 0 warnings, 14 errors.
  Type Bytes has no method exact_view.
```

一句 `git clone && moon check` 脚本会把这个包记成"编译失败"。**但它没有坏——是工具链版本差了一档。** 把健康的库标成不可用，比没有工具更糟。

区分这两者需要理解 MoonBit 编译器的错误措辞（`has no method` / `unresolved identifier` / `unknown type` …），并且**判定顺序不能错**：依赖缺失和工具链不兼容的特征经常同时出现，顺序错了就会给出误导性结论。详见 [九类结论与判定顺序](docs/ARCHITECTURE.md#九类结论与判定顺序)。

## 库核心是全后端可移植的（构建期强制，不是文档口号）

仓库里有一条硬边界：**C FFI 只允许出现在 `platform/proc`、`platform/fs`、`platform/http` 三个包**（`extern "C"` 要起子进程、读文件、开 socket）。其余全是纯计算。

这条边界由各包的 `supported_targets` 声明、由工具链在构建期强制——任何人试图把 FFI 拖进库核心，`moon check` 立刻失败：

| 层 | 包 | 后端 |
|---|---|---|
| **库核心**（纯计算，零平台依赖） | `verify/diagnose`、`report/model`、`report/json`、`report/compare`、`report/site`、`platform/time`、`core/error` | `wasm` `wasm-gc` `js` `native` |
| 平台层（唯一允许 C FFI） | `platform/proc`、`platform/fs`、`platform/http` | 仅 `native` |
| 参考 CLI | `cmd/moonhive`、`features/*`、`verify/check`、`verify/workspace`、`verify/gitsource` | 仅 `native` |

因此库核心能在浏览器/Wasm 环境里直接用，CI 会在四个后端上分别编译并跑测试：

```powershell
./build.ps1 -CrossBackend   # => wasm / wasm-gc / js 各 93 测试全绿，native 146
```

## 其它语言生态里的对标工具

"这个包在我这套工具链上还能不能编译"是所有快速演进的语言都要单独造工具去回答的问题。MoonBit 现在没有这个工具——这就是 MoonHive 的位置：

| 生态 | 对标工具 | 回答的问题 |
|---|---|---|
| Rust | [`cargo-msrv`](https://github.com/foresterre/cargo-msrv) | 一个 crate 的最低支持 Rust 版本是多少（其定义即为"**does compile with a toolchain of a certain version**"） |
| Rust | [`cargo-semver-checks`](https://github.com/obi1kenobi/cargo-semver-checks) | 新版本是否破坏了 API 兼容性 |
| Java | [Revapi](https://revapi.org/) | 二进制/源码兼容性是否被破坏 |
| Python | `caniusepython3` / 各版本 CI 矩阵 | 依赖在目标版本上是否可用 |
| Node.js | [`npm view`](https://docs.npmjs.com/cli/commands/npm-view) 的 `engines` 字段 | 包声明的运行时版本范围 |
| **MoonBit** | **MoonHive** | **这个包在本机这套工具链上到底能不能用，失败该归因给谁** |

## 与 MoonBit 生态已有工具的关系

生态里已有一个依赖健康诊断工具 [`Tino-hue/depsight`](https://mooncakes.io/docs/Tino-hue/depsight)（被称作 MoonBit 版的 `cargo audit`）。它和 MoonHive **不重合，因为输入与结论类型都不同**：

| | depsight | MoonHive |
|---|---|---|
| 输入 | `moon.mod` / 注册表 / 依赖图元数据 | **真实工具链对真实代码的编译输出** |
| 手段 | 静态分析、语义化版本比对、SPDX 识别 | 在隔离工作区**真的 clone 下来编译与跑测试** |
| 输出 | 0–100 健康分（新鲜度/合规/体积/弃用/活跃度） | **九类可行动结论**（能用 / 编译不过 / 工具链不匹配 / 依赖缺失 …） |
| 回答 | "这个依赖值不值得选" | "这个包在我这套工具链上**能不能用**，失败该怪谁" |
| 运行环境 | JS 后端（Node.js ≥ 18） | **库核心四个后端通用**，CLI 走 native |

关键区别可以用一句话检验：**一个包在 depsight 上拿 94/100 分，仍然可能在本机编译不过**——因为它考的是依赖健康度，不是可编译性；而工具链版本漂移恰恰是元数据看不出来的。两者互补：depsight 帮你在选型阶段挑依赖，MoonHive 在你踩到"编译失败"时判断这到底是不是包的错。

MoonHive 也是独立的第三方项目，与 MoonBit 官方的 mooncakes.io 发布审计**没有功能重叠**：官方审计的是"包能否正确发布"，MoonHive 审计的是"已发布的包在特定工具链上能否使用"。


差别在于归因：上面多数工具假定"编译失败 = 包有问题"，MoonHive 会先判断这次失败是不是**工具链版本差异**造成的假阳性。MoonBit 工具链迭代很快，这个区分是刚需。

## 结论分类

| 结论 | 含义 |
|---|---|
| `Verified` | 编译与测试全通过，可直接使用 |
| `TestFailing` | 能编译，但测试失败 |
| `DoesNotCompile` | 编译器报错，当前工具链上不可用 |
| `ToolchainMismatch` | 错误指向版本或 API 不兼容，是工具链差异而非包损坏 |
| `MissingDependency` | 依赖解析失败 |
| `NoManifest` | 缺少 `moon.mod`，不是 MoonBit 模块 |
| `TimedOut` | 超出时间预算 |
| `Unsafe` | 含 FFI 或构建脚本，仅做静态分析 |
| `FetchFailed` | 仓库获取失败 |

## 特性

- **库核心零平台依赖**：归因分类器与报告渲染是纯计算，可在 `wasm` / `wasm-gc` / `js` / `native` 四个后端编译运行（边界由 `supported_targets` 在构建期强制）
- **双获取方式**：`git clone` 验证仓库最新代码，`--registry` 验证 mooncakes 发布版本
- **三种报告格式**：Markdown（人读）、JSON（机器读，带 schemaVersion）、单文件 HTML（可直接托管）
- **隔离工作区**：一次性临时目录 + 磁盘配额 + 超时上限，不执行仓库自带构建脚本
- **本地仪表盘**：`serve` 把报告目录变成浏览器可访问的页面，仅监听 127.0.0.1
- **环境自检**：`doctor` 检测工具链、git TLS 后端、临时目录并给出修复建议
- **收藏夹**：`keep` / `list` / `forget` 收藏验证过的包，本地存 `favorites.json`
- **报告对比**：`report/compare` 模块对比两轮验证结果，区分好转（不可用→可用）、恶化（可用→不可用）、新增、消失

## 快速开始

### 环境要求

- MoonBit 工具链（开发环境 `moon 0.1.20260904`）
- git

仓库自带 `build.ps1` 处理中文路径问题（GNU assembler 无法处理非 ASCII 路径）：

```powershell
./build.ps1                 # 构建
./build.ps1 -Test           # 构建 + 测试
./build.ps1 -CrossBackend   # 额外验证库核心在 wasm / wasm-gc / js 上可用
```

### 常用命令

```powershell
# 环境自检
./build.ps1 -Run doctor

# 体检一个远端仓库（git clone 默认分支）
./build.ps1 -Run @("inspect", "moonbit-community/yaml")

# 体检注册表发布版本（moon fetch）
./build.ps1 -Run @("inspect", "--registry", "moonbit-community/yaml")

# 批量普查多个包
./build.ps1 -Run @("survey", "moonbit-community/yaml", "bobzhang/toml", "--out", "report.md", "--json", "report.json", "--site", "index.html")

# 本地仪表盘
./build.ps1 -Run @("serve", "--dir", "reports", "--port", "9090")
```

### 输入格式

`inspect` / `survey` 接受三种写法：

- `owner/repo` — 远端仓库（git clone）
- `https://github.com/owner/repo` — 完整 URL
- `./pkg` — 本地目录，无需联网

## 实测数据

对 mooncakes 上 18 个真实包跑了三轮验证（9/25–9/27），结果一致：

| 结论 | 数量 | 代表包 |
|---|---|---|
| Verified | 3 | `bobzhang/lexer`、`bobzhang/toml`、`moonbit-community/yaml` |
| DoesNotCompile | 3 | `moonbitlang/yacc`、`moon-loglens`、`MoonCheck` |
| ToolchainMismatch | 2 | `moonhttp`、`jmespath` |
| NoManifest | 3 | `quickcheck`、`tempfile`、`duckdb` |
| Unsafe | 7 | `x`、`async`、`parser`、`zlib`、`llm`、`moonmmdb` 等 |

可用率 16.7%。完整报告见 [GitHub Pages](https://Duckweed-yhb.github.io/moon-hive/)，原始数据在 [`reports/`](reports/)。

## 质量基线

| 指标 | 数值 |
|---|---|
| MoonBit 源码 | 5,944 行 / 21 个包 |
| C FFI 平台层 | 1,863 行（fs 774 / http 741 / proc 348） |
| 单元测试 | **146 个，全绿**（`moon test --target native`） |
| 跨后端测试 | **93 个 × 3 后端**（`wasm` / `wasm-gc` / `js` 上的库核心） |
| 第三方运行时依赖 | **0**（仅 `moonbitlang/core` + 自建 C FFI 层） |
| CI | GitHub Actions，Linux / Windows 双平台矩阵 |

## 安全

验证陌生代码有固有风险。MoonHive 的策略：

1. 只调用 MoonBit 官方工具链的 `check` / `build` / `test`，不执行仓库自带构建脚本
2. 所有验证在一次性临时工作区内进行，结束后清理
3. 设超时上限与磁盘配额
4. 含 FFI 或自定义构建脚本的仓库仅做静态分析

## 已知限制

- **参考 CLI 仅支持 native 后端**：它需要起子进程、读文件、开 socket（C FFI 不支持 wasm）。**库核心不受此限制**——归因分类器与报告渲染在四个后端都能用
- Windows 下项目路径含中文时用 `build.ps1`（直接 `moon build/run` 会失败）。`build.ps1` 必须以 UTF-8 **带 BOM** 保存，否则 Windows PowerShell 5.1 会把中文注释按 GBK 解码而解析失败
- 远端克隆依赖本机 git 的 TLS 后端，`doctor` 可检测并修复
- 仪表盘仅监听 127.0.0.1，用 `127.0.0.1` 而非 `localhost` 访问

## 文档

- [架构设计](docs/ARCHITECTURE.md) — 分层边界与后端可移植性、九类结论判定逻辑、安全设计
- [开发记录](docs/DEVELOPMENT.md) — 技术取舍与缺陷复盘
- [贡献指南](CONTRIBUTING.md) · [路线图](ROADMAP.md) · [变更日志](CHANGELOG.md)

## 许可证

MIT
