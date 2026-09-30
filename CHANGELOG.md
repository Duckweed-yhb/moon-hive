# 变更记录

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/) 风格，版本号遵循语义化版本。

## [Unreleased]

把项目定位从"一个 CLI 工具"修正为"**可移植的诊断归因库 + 仅 native 的参考 CLI**"，并把这条边界交给构建器强制。

### 新增

- **库边界由 `supported_targets` 在构建期强制**：库核心七个包（`verify/diagnose`、`report/model`、`report/json`、`report/compare`、`report/site`、`platform/time`、`core/error`）声明 `wasm+wasm-gc+js+native`；三个 C FFI 包与依赖它们的 CLI 链路声明 `native`。任何尝试让库核心引入 FFI 的改动都会在 `moon check` 阶段失败
- **库核心跨后端可用**：`moon test` 在 `wasm` / `wasm-gc` / `js` 上各跑通 **87** 个测试（此前整模块在这三个后端上根本无法编译）
- `build.ps1 -CrossBackend`：一条命令复现上述跨后端验证
- CI 新增三个非 native 后端的库核心测试步骤

### 修复

- `build.ps1` 头部补回 UTF-8 BOM。Windows PowerShell 5.1 会把无 BOM 文件按 ANSI（中文环境为 GBK）解码，中文注释被解成乱码后会直接导致语法解析失败

### 变更

- README 主叙事改为"库优先"：先说归因引擎与可移植性，CLI 作为参考消费者
- `docs/ARCHITECTURE.md` 的分层图标注每条链路的可用后端，并说明约束为何是构建期强制的

### 质量基线

- 140 个单元测试全绿（native）；87 个 × 3 后端全绿（wasm / wasm-gc / js）
- 构建 0 警告
- 仅依赖 MoonBit core 标准库与自建 C FFI 平台层，零第三方运行时依赖

## [0.2.0] - 2026-09

生态验证引擎版本。把候选 MoonBit 包拉进隔离工作区，用真实工具链验证能否编译、测试是否通过，失败归为可行动的结论。

### 新增

- `survey` 批量普查：对多个候选包逐个验证，一次产出 Markdown / JSON / HTML 三种报告
- `inspect` 单包体检：拉取并验证指定仓库
- `doctor` 环境自检：检测工具链、git、TLS 后端、临时目录，给出修复命令
- `serve` 本地仪表盘：把报告目录变成浏览器可访问的页面，仅监听 127.0.0.1
- 九类诊断结论：Verified / TestFailing / DoesNotCompile / ToolchainMismatch / MissingDependency / NoManifest / TimedOut / Unsafe / FetchFailed
- 双获取方式：`git clone` 验证仓库最新代码，`--registry` 验证 mooncakes 发布版本
- 隔离工作区：一次性临时目录 + 磁盘配额 + 超时上限，不执行仓库自带构建脚本
- 收藏夹：keep / list / forget 三个命令，本地存 favorites.json
- GitHub Actions CI（Linux / Windows 矩阵）

### 质量基线

- 132 个单元测试，全部通过（后增至 140）
- 构建 0 警告
- 仅依赖 MoonBit core 标准库与自建 C FFI 平台层，零第三方运行时依赖

