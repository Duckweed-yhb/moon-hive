# MoonHive

> 用真实 MoonBit 工具链验证生态里的包能不能编译、测试过不过。验证做得久了，顺手把实测过的示例整理成了学习资源。

[![CI](https://github.com/Duckweed-yhb/moon-hive/actions/workflows/ci.yml/badge.svg)](https://github.com/Duckweed-yhb/moon-hive/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## MoonHive 做什么

想要用生态里某个包时，能看到的多半是名字和 star 数。star 数不告诉你它能不能编译、测试过没过、依赖重不重、在你那套工具链上能不能跑。

MoonHive 把候选项目拉到本地，在隔离工作区里用真实工具链检它们，把结论分成九类：

| 结论 | 含义 |
|---|---|
| ✅ `Verified` | 编译 + 测试全绿，拿过来就能用 |
| ⚠️ `TestFailing` | 能编译，但测试挂，代码在演进中 |
| ❌ `DoesNotCompile` | 编译器报错，当前工具链上不可用 |
| 🚫 `ToolchainMismatch` | 诊断指向版本/API 不兼容，是工具链版本差异，不是包坏了 |
| 📦 `MissingDependency` | 依赖解析失败，不是自包含的 |
| 📄 `NoManifest` | 没有 `moon.mod`，不是 MoonBit 模块 |
| ⏱️ `TimedOut` | 超出时间预算 |
| 🔒 `Unsafe` | 含 FFI / 构建脚本，只做静态分析 |
| 🌐 `FetchFailed` | 获取仓库失败（网络 / 克隆 / 注册表拉取） |

判断能不能用，得握着工具链：要起子进程、读编译器诊断、管理真实工作区。这几步对话式 AI 和 GitHub 搜索都给不了。

### 一个真实例子

`moonbitlang/x` 是 MoonBit 生态里最活跃的库之一（167 个 `.mbt` 文件、约 30,000 行、58 个测试文件）。但在这台开发机的工具链上：

```
$ moon check --target native
Failed with 0 warnings, 14 errors.
  Type Bytes has no method exact_view.
```

MoonHive 把这个结果归类为 `🚫 ToolchainMismatch`，而不是"这个包坏了"：它能在别的工具链版本上正常工作。分不清这两者，会把生态里健康的库误标成不可用。

## 现在做到哪了

项目从 v1（每日项目投喂工具）重构为 v2（生态验证引擎）。v1 的 Base64 / Hex / digest / 收藏 / 统计等功能已全部移除，它们与"验证包能不能用"这条主线无关。

| 模块 | 状态 |
|---|---|
| `platform/proc` — FFI 子进程执行 / 文件读写 | ✅ 已完成 |
| `platform/fs` — FFI 目录遍历 / 复制 / 清理 | ✅ 已完成 |
| `platform/time` — 超时预算与耗时格式化 | ✅ 已完成 |
| `platform/http` — 本地 HTTP 服务（仪表盘后端） | ✅ 已完成 |
| `core/error` — 统一错误契约 | ✅ 已完成 |
| `verify/workspace` — 隔离工作区 / 配额 / 清理 | ✅ 已完成 |
| `verify/gitsource` — 候选解析 / git 克隆 / TLS 后端探测 | ✅ 已完成 |
| `verify/diagnose` — 九类结论分类器 | ✅ 已完成 |
| `verify/check` — 工具链驱动与验证编排 | ✅ 已完成 |
| `features/*` — survey / inspect / doctor / serve 四个命令 | ✅ 已完成 |
| `report/*` — Markdown / JSON / HTML 三种报告 | ✅ 已完成 |

测试 124 个用例全绿，构建 0 警告。`survey` 可同时产出三种报告，共用同一份数据模型：

| 格式 | 参数 | 用途 |
|---|---|---|
| Markdown | `--out report.md` | 给人读，可贴进仓库 |
| JSON | `--json report.json` | 给脚本读，可做趋势对比（含 `schemaVersion`） |
| HTML | `--site index.html` | 单文件、内联样式、零 JavaScript，可直接托管为静态站 |

三种格式的头部都记录验证环境（工具链版本 / 目标后端 / 时间戳）。工具链不同，结论就可能不同，报告头记录环境，结论才可复现。

### 实测效果

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

### 真实生态验证（2026-09-27）

对 mooncakes 上的 18 个真实包做了批量普查（完整结果见 [网页版报告](https://Duckweed-yhb.github.io/moon-hive/) 或 `reports/2026-09-27.md`）：

| 结论 | 数量 | 代表包 |
|---|---|---|
| ✅ Verified | 3 | `bobzhang/lexer`、`bobzhang/toml`、`moonbit-community/yaml` |
| ❌ DoesNotCompile | 3 | `moonbitlang/yacc`、`moon-loglens`、`MoonCheck` |
| 🚫 ToolchainMismatch | 2 | `moonhttp`、`jmespath` |
| 📄 NoManifest | 3 | `quickcheck`、`tempfile`、`duckdb` |
| 🔒 Unsafe | 7 | `x`、`async`、`parser`、`zlib`、`llm`、`moonmmdb` 等 |

可用率 16.7%，18 个包里只有 3 个开箱即用。这个数字只说明一件事：能不能用只能实测。star 数、README、搜索引擎都不会告诉你 `moonbitlang/yacc` 在当前工具链上编译不过。三轮普查（9/25–9/27）结果一致，结论可复现。同一个包 `bobzhang/toml`，注册表发布版编译与测试全部通过（✅ Verified），仓库默认分支此前曾报测试失败。哪个版本能用，同样需要实测。

## 怎么用

### 输入形式

`inspect` / `survey` 接受三种写法：

- `owner/repo` — 远端仓库（走 git 克隆）
- `https://github.com/owner/repo` — 完整 URL
- `C:\path\to\pkg` 或 `./pkg` — 本地目录，直接复制进隔离工作区验证，无需联网

加 `--registry` 后，候选被当作 mooncakes 包名（仍为 `owner/repo` 形式），改用 `moon fetch` 验证注册表发布版本。

### 两种获取方式

同一个包，`git clone` 拿到的是仓库默认分支的最新代码（可能是未发布的开发中代码），用户实际 `moon add` 装到的是注册表上的发布版本。两者可能给出不同结论，MoonHive 两种都支持：

```
$ moonhive inspect moonbit-community/yaml
[1/1] 📄 yaml   结论: NoManifest   （GitHub 默认分支没有 moon.mod）

$ moonhive inspect --registry moonbit-community/yaml
[1/1] ✅ moonbit-community/yaml   结论: Verified   （发布版 0.0.6，69 个测试全过）
```

默认走 `git clone`；加 `--registry` 验证注册表发布版本。用户会装到的那个版本能不能用，比仓库最新代码能不能用更贴近真实问题。

### 环境要求

- MoonBit 工具链（开发环境 `moon 0.1.20260904`）
- git（用于获取待验证的仓库）
- 构建产物路径必须为纯 ASCII，GNU assembler 无法处理含非 ASCII 字符的路径。仓库自带 `build.ps1` 会自动把产物重定向到系统临时目录，直接用它即可：

```powershell
./build.ps1              # 构建
./build.ps1 -Test        # 构建 + 测试
./build.ps1 -Examples    # 验证 examples/ 全部示例（编译运行 + 比对 expected.txt）
./build.ps1 -Run doctor  # 构建 + 运行 moonhive doctor
```

手工构建时需显式指定纯 ASCII 的产物目录：

```bash
moon build --target native --release --target-dir /path/to/ascii/dir
```

Windows 上还需确认 git 的 TLS 后端可用。`moonhive doctor` 会自动检测并给出修复建议（常见情况：系统配置了 `http.sslBackend = schannel` 而该后端不可用，执行 `git config --global http.sslBackend openssl` 即可）。

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
```

三个使用注意事项：

1. 用 127.0.0.1 访问，不要用 localhost。服务只监听 IPv4 回环，Windows 上 localhost 会优先解析 IPv6 ::1，导致连不上。
2. 8080 是常用端口，常被其他软件占用，启动报端口被占用就换 `--port`。
3. `build.ps1` 的 `-Run` 传参数，以 `-` 开头的选项要用数组形式（`@(...)`），否则 PowerShell 会把 `--dir` 当成 build.ps1 自己的参数而报错。

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

自检的意义在于，验证结论只有在环境正确时才有意义。doctor 把"看起来失败，其实是环境问题"这类误判挡在前面。

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

分层边界（可替换性声明）：

- 只有 `platform/*` 允许出现 C FFI。想换掉底层实现，只需替换这几个包。
- 只有 `verify/check` 知道如何调用 `moon` 命令。
- `core/*` 与 `report/*` 不知道文件系统与进程的存在，因此可以 100% 单元测试。

**为什么用 C FFI**：`moonbitlang/core` 不提供文件系统与进程模块（它们只在第三方的 `moonbitlang/async` 中）。本项目的核心能力，起进程跑工具链、读编译器诊断，必须依赖它们，因此自建 FFI 层而不是引入第三方包。

**仪表盘的网络层**：`platform/http` 是零第三方依赖的静态服务器，只监听回环地址、只允许 GET、拒绝路径穿越（`..`）。Windows 上 winsock 通过 `LoadLibrary("ws2_32.dll")` 在运行时加载，不参与静态链接（moon 的 `cc-link-flags` 不进入可执行链接）。

**为什么只在 native 后端构建**：C FFI 不支持 wasm 后端。这是有意的架构选择，本工具是本地 CLI，不需要在浏览器或 wasm 运行时里跑。

## 安全

验证陌生代码有固有风险，MoonHive 的策略是：

1. 永不执行仓库自带的构建脚本，只调用 MoonBit 官方工具链的 `check` / `build` / `test`
2. 所有验证在一次性临时工作区内进行，结束后可一键清理
3. 设超时上限与磁盘配额
4. 含 FFI 或自定义构建脚本的仓库只做静态分析，不执行

## 学习资源

验证引擎在验证生态包的同时，攒出一批实测过的 MoonBit 示例。每个示例都由工具链真实编译运行，输出不是手打的，`./build.ps1 -Examples` 可以一键复验。这些示例整理成两种学法的学习资源：

### MoonBit by Example

go-by-example 风格的主题示例库：每个示例一页，可运行代码 + 真实输出 + 要点讲解，适合按需查阅，想学 match 直接打开 match 示例。已完成 Day 01–05（hello / variables / types / functions / control），全部实测通过，目标覆盖基础到实战共 25 个主题。入口：[examples/README.md](examples/README.md)。

### 100 Days of MoonBit

python-100-days 风格的每日教程：每天一篇完整文章，概念引入、代码分段讲解、Windows 常见坑、动手练习、今日小结，适合从头系统学、靠节奏坚持。已完成 Day 01–02（初识 MoonBit / 变量与绑定），后续随示例推进。入口：[100days/README.md](100days/README.md)。

## 未来方向

- 同一包在不同 moon 版本上验证，把"包坏了"和"工具链演进"分开看
- 定时跑 survey，追踪生态包可用性的变化
- 把 examples/ 接入验证引擎，发布站点时自动标注每个示例的实测结果

## 许可证

MIT
