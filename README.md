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
| ⏱️ `TimedOut` | 超出时间预算 |
| 🔒 `Unsafe` | 含 FFI / 构建脚本，只做静态分析 |
| 🌐 `FetchFailed` | 获取仓库失败（网络 / 克隆 / 注册表拉取失败） |

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
| `platform/proc` — FFI 子进程执行 / 文件读写 | ✅ 已完成 |
| `platform/fs` — FFI 目录遍历 / 复制 / 清理 | ✅ 已完成 |
| `platform/time` — 超时预算与耗时格式化 | ✅ 已完成 |
| `core/error` — 统一错误契约 | ✅ 已完成 |
| `verify/workspace` — 隔离工作区 / 配额 / 清理 | ✅ 已完成 |
| `verify/gitsource` — 候选解析 / git 克隆 / TLS 后端探测 | ✅ 已完成 |
| `verify/diagnose` — 九类结论分类器（核心资产） | ✅ 已完成 |
| `verify/check` — 工具链驱动与验证编排 | ✅ 已完成 |
| `features/doctor` — 环境自检 | ✅ 已完成 |
| `features/inspect` — 单包深度体检 | ✅ 已完成 |
| `features/survey` — 批量普查主命令 | ✅ 已完成 |
| `features/serve` — 本地仪表盘（浏览器 UI） | ✅ 已完成 |
| `report/model` — 报告数据模型 | ✅ 已完成 |
| `report/json` — 机器可读输出 | ✅ 已完成 |
| `report/site` — 公开静态站（单文件 HTML） | ✅ 已完成 |

**测试：119 个用例全绿。构建 0 警告。**

### 三种报告格式

`survey` 可同时产出三种格式，共用同一份数据模型：

| 格式 | 参数 | 用途 |
|---|---|---|
| Markdown | `--out report.md` | 给人读、可贴进仓库 |
| JSON | `--json report.json` | 给脚本读、可做趋势对比（含 `schemaVersion`） |
| HTML | `--site index.html` | 单文件、内联样式、零 JavaScript，可直接托管为公开静态站 |

三种格式的头部都强制记录**验证环境**（工具链版本 / 目标后端 / 时间戳）——
脱离环境的"能不能用"是没有意义的结论。

### 已验证的真实效果

```
$ moonhive inspect <模块目录> <另一个模块>

git TLS 后端: openssl（系统默认后端不可用，已按命令显式指定）
工作区: .../moonhive-workspaces/moonhive-workspace-1789913651020
目标后端: native

[1/4] ✅ Verified
   结论: Verified
   说明: 编译与测试通过，可以直接使用
   规模: 1 个 .mbt / 8 行 / 0 个测试文件 / 136 B
   耗时: check 179ms / test 2.8s

[2/4] ❌ DoesNotCompile
   证据: [ .../lib/a.mbt:2:3 ]

结论汇总（共 4 个）
  Verified: 1   DoesNotCompile: 1   NoManifest: 1   Unsafe: 1
```

### 真实生态验证（2026-09-26）

对 mooncakes 上的 **18 个真实包**做了批量普查（完整结果见 [网页版报告](https://Duckweed-yhb.github.io/moon-hive/) 或 `reports/2026-09-26.md`）：

| 结论 | 数量 | 代表包 |
|---|---|---|
| ✅ Verified | 3 | `bobzhang/lexer`、`bobzhang/toml`、`moonbit-community/yaml` |
| ❌ DoesNotCompile | 3 | `moonbitlang/yacc`、`moon-loglens`、`MoonCheck` |
| 🚫 ToolchainMismatch | 2 | `moonhttp`、`jmespath` |
| 📄 NoManifest | 3 | `quickcheck`、`tempfile`、`duckdb` |
| 🔒 Unsafe | 7 | `x`、`async`、`parser`、`zlib`、`llm`、`moonmmdb` 等 |

**可用率 16.7%**——18 个包里只有 3 个开箱即用。这不是"生态很差"的结论，而是"能不能用需要实测"的直接证据：star 数、README、搜索引擎都不会告诉你 `moonbitlang/yacc` 在当前工具链上编译不过——MoonHive 会。同一个包 `bobzhang/toml` 在注册表发布版上编译与测试全部通过（✅ Verified），而仓库默认分支此前曾报测试失败——**"哪个版本能用"同样需要实测。**

### 输入形式

`inspect` / `survey` 接受三种写法：

- `owner/repo` — 远端仓库（走 git 克隆）
- `https://github.com/owner/repo` — 完整 URL
- `C:\path\to\pkg` 或 `./pkg` — **本地目录**，直接复制进隔离工作区验证，无需联网
  （适合验证你手上已有的 checkout，也便于离线复现结论）

加 `--registry` 后，候选被当作 **mooncakes 包名**（仍为 `owner/repo` 形式），改用 `moon fetch` 验证注册表发布版本。

### 两种获取方式：仓库最新代码 vs 注册表发布版

同一个包，`git clone` 拿到的是**仓库默认分支的最新代码**（可能是未发布的开发中代码），而用户实际 `moon add` 装到的是**注册表上的发布版本**。两者可能给出截然不同的结论——MoonHive 两种都支持：

```
# 走 git clone，验证仓库默认分支的最新代码
$ moonhive inspect moonbit-community/yaml
[1/1] 📄 yaml   结论: NoManifest   （GitHub 默认分支没有 moon.mod）

# 走注册表，验证用户真正会装到的发布版本
$ moonhive inspect --registry moonbit-community/yaml
[1/1] ✅ moonbit-community/yaml   结论: Verified   （发布版 0.0.6，69 个测试全过）
```

默认走 `git clone`；加 `--registry` 后候选按 mooncakes 包名处理，用 `moon fetch` 拉取发布版本再验证。**"用户会装到的那个版本能不能用"比"仓库最新代码能不能用"更贴近真实问题。**

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
# 环境自检（会检出 git TLS 后端问题并给出修复建议）
moon run cmd/moonhive --target native -- doctor

# 体检一个远端仓库（走 git clone，验证默认分支最新代码）
moon run cmd/moonhive --target native -- inspect moonbit-community/yaml

# 体检一个注册表包（moon fetch 发布版本，用户真正会装到的那个）
moon run cmd/moonhive --target native -- inspect --registry moonbit-community/yaml

# 体检一个本地目录（无需联网）
moon run cmd/moonhive --target native -- inspect ./some-package

# 把报告目录变成浏览器仪表盘（本地 HTTP，仅监听 127.0.0.1）
# 仓库路径含中文时请用 build.ps1（直接 moon run 会因汇编器无法处理中文路径而失败）：
./build.ps1 -Run @("serve","--dir","reports","--port","9090")
# 然后浏览器打开 http://127.0.0.1:9090/

# 三个使用注意事项：
#   1. 用 127.0.0.1 访问，不要用 localhost——服务只监听 IPv4 回环，
#      而 Windows 上 localhost 会优先解析 IPv6 ::1，导致连不上
#   2. 8080 是常用端口，常被其他软件占用——启动报"端口被占用"就换 --port
#   3. build.ps1 的 -Run 传参数要以 - 开头的选项需用数组形式（@(...)），
#      否则 PowerShell 会把 --dir 当成 build.ps1 自己的参数而报错
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
platform/http    ⭐     FFI：本地 HTTP 服务（仪表盘后端，仅监听 127.0.0.1）
verify/workspace ⭐     隔离工作区生命周期 + 磁盘配额 + 并发调度
verify/check     ⭐     工具链驱动（moon check / build / test）
verify/diagnose  ⭐⭐   编译器诊断解析 → 失败分类
report/model            报告数据模型（纯计算，与验证层解耦）
report/json             机器可读输出（含 schemaVersion 与完整转义）
report/site             公开静态站（单文件 HTML，零依赖）
features/*              命令实现（survey / inspect / doctor / serve）
```

**分层边界（可替换性声明）**：
- 只有 `platform/*` 允许出现 C FFI。想换掉底层实现，只需替换这几个包。
- 只有 `verify/check` 知道如何调用 `moon` 命令。
- `core/*` 与 `report/*` 不知道文件系统与进程的存在，因此可以 100% 单元测试。

**为什么用 C FFI**：`moonbitlang/core` 不提供文件系统与进程模块（它们只在第三方的 `moonbitlang/async` 中）。本项目的核心能力——起进程跑工具链、读编译器诊断——必须依赖它们，因此自建 FFI 层而不是引入第三方包。

**仪表盘的网络层**：`platform/http` 是零第三方依赖的静态服务器——只监听回环地址、只允许 GET、拒绝路径穿越（`..`）。Windows 上 winsock 通过 `LoadLibrary("ws2_32.dll")` 在运行时加载，不参与静态链接（moon 的 `cc-link-flags` 不进入可执行链接）。

**为什么只在 native 后端构建**：C FFI 不支持 wasm 后端。这是有意的架构选择：本工具是本地 CLI，不需要在浏览器或 wasm 运行时里跑。

## 安全说明

验证陌生代码有固有风险，MoonHive 的策略是：

1. **永不执行仓库自带的构建脚本**——只调用 MoonBit 官方工具链的 `check` / `build` / `test`
2. 所有验证在**一次性临时工作区**内进行，结束后可一键清理
3. 设超时上限与磁盘配额
4. 含 FFI 或自定义构建脚本的仓库**只做静态分析**，不执行

## 未来方向

- **多工具链对比**：同一包在不同 moon 版本上验证，区分"包坏了"与"工具链演进"
- **趋势追踪**：定时运行 survey，追踪生态包可用性的变化
- **MoonBit by Example**：基于验证引擎构建示例驱动的学习资源——每个示例经真实工具链编译运行验证、带实测标记，填补 MoonBit 生态的示例学习空白

## 许可证

MIT
