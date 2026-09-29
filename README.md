# MoonHive

[![CI](https://github.com/Duckweed-yhb/moon-hive/actions/workflows/ci.yml/badge.svg)](https://github.com/Duckweed-yhb/moon-hive/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

MoonBit 生态包验证工具。把候选包拉进隔离工作区，用真实工具链逐个验证能否编译、测试是否通过，失败归为九类可行动结论。

star 数告诉你包火不火，MoonHive 告诉你包能不能用。

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

- **双获取方式**：`git clone` 验证仓库最新代码，`--registry` 验证 mooncakes 发布版本
- **三种报告格式**：Markdown（人读）、JSON（机器读，带 schemaVersion）、单文件 HTML（可直接托管）
- **隔离工作区**：一次性临时目录 + 磁盘配额 + 超时上限，不执行仓库自带构建脚本
- **本地仪表盘**：`serve` 把报告目录变成浏览器可访问的页面，仅监听 127.0.0.1
- **环境自检**：`doctor` 检测工具链、git TLS 后端、临时目录并给出修复建议
- **收藏夹**：`keep` / `list` / `forget` 收藏验证过的包，本地存 `favorites.json`

## 快速开始

### 环境要求

- MoonBit 工具链（开发环境 `moon 0.1.20260904`）
- git

仓库自带 `build.ps1` 处理中文路径问题（GNU assembler 无法处理非 ASCII 路径）：

```powershell
./build.ps1              # 构建
./build.ps1 -Test       # 构建 + 测试
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

可用率 16.7%。完整报告见 [GitHub Pages](https://Duckweed-yhb.github.io/moon-hive/)。

## 安全

验证陌生代码有固有风险。MoonHive 的策略：

1. 只调用 MoonBit 官方工具链的 `check` / `build` / `test`，不执行仓库自带构建脚本
2. 所有验证在一次性临时工作区内进行，结束后清理
3. 设超时上限与磁盘配额
4. 含 FFI 或自定义构建脚本的仓库仅做静态分析

## 已知限制

- 仅支持 native 后端：C FFI 不支持 wasm
- Windows 下项目路径含中文时用 `build.ps1`（直接 `moon build/run` 会失败）
- 远端克隆依赖本机 git 的 TLS 后端，`doctor` 可检测并修复
- 仪表盘仅监听 127.0.0.1，用 `127.0.0.1` 而非 `localhost` 访问

## 文档

- [架构设计](docs/ARCHITECTURE.md) — 分层边界、九类结论判定逻辑、安全设计
- [开发记录](docs/DEVELOPMENT.md) — 技术取舍与缺陷复盘
- [贡献指南](CONTRIBUTING.md) · [路线图](ROADMAP.md) · [变更日志](CHANGELOG.md)

## 许可证

MIT
