# 变更记录

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/) 风格，版本号遵循语义化版本。

## [Unreleased]

### 新增

- **跨工具链对比（`verify/compare` + `moonhive compare`）**：同一候选包用多个 moon 版本（工具链命令）各验证一遍，对比诊断结果，区分"包坏"（所有工具链一致失败，ConsistentFail）与"工具链演进"（有通过有失败，ToolchainDrift），以及"都失败但原因不同"（InconsistentFail）。这是对"归因依赖硬编码特征串、护城河弱"的直接回应：**行为是否随工具链变化不依赖任何编译器措辞**，是机制性证据。
  - `verify/compare` 为纯计算包（`wasm+wasm-gc+js+native` 四后端），含 15 个单测覆盖判定顺序、渲染与 JSON 输出；
  - `verify/check` 新增 `verify_candidate_toolchains`（多工具链执行）与私有泛化实现 `verify_with_toolchain`（工具链命令可配，`verify_candidate` 等价于 `"moon"`）；
  - CLI 新增 `compare` 子命令：`moonhive compare [--toolchains moon,moon-0.10.14] <候选>`，逐候选渲染结论 + 输出一行 JSON，任一候选非 AllGreen 时退出码 1。
- **`version` 对齐 moon.mod**：`moonhive version` 由写死的 0.2.0 修正为 0.2.4。
- **工具链不兼容判定语义化（`verify/diagnose`）**：不再对 `has no method` / `unresolved identifier` 等特征串一刀切判 `ToolchainMismatch`（回应九月赛评审"对语义没有了解"的批评）——命中特征后提取缺失符号并按**符号归属**判定：符号属 core 类型/模块（`Bytes`、`@json` 等，由工具链随附版本管控）→ `ToolchainMismatch`；属包自身/未知（如 `MyPacket`）→ `DoesNotCompile`（包/文档写错）。新增 `classify_verified(outcome, confirmed_missing)` 支持外部符号存在性证据注入；`classify(outcome)` 保持向后兼容并委托之。

### 修复

- **`proc` 层实现真正的进程级超时（`platform/proc`）**：原 `proc_run_capture` 用 `popen`/`fread`/`pclose` 全阻塞且 `(void)timeout_ms` 完全忽略超时——子进程挂死（实测 `moon fetch` 依赖 GitHub 拉取挂起）时 `proc.run` 永不返回，上层超时判定轮不到执行，survey 直接卡死。本次改为：Windows `CreateProcess` + `cmd.exe /c` + Job Object（超时 `TerminateJobObject` 整棵进程树强杀，Job 不可用时 fallback `TerminateProcess` + `taskkill /T`）；POSIX `fork` + `waitpid` 轮询 + `kill`。新增内部错误码 `-1005` → `ProcError::TimedOut`；`check.mbt` 把 fetch 阶段超时归为 `TimedOut` 诊断、check/test 阶段超时置 `timed_out`。修复后挂起包在限时内返回结论不再卡死（实测 mooncrypt 2.4s 归 ToolchainMismatch、mooncry 40.8s 归 TimedOut，此前均 >15 分钟永久挂起）。

### 质量基线

- `moon check` 0 错误；native 测试 **165** 全绿（较 0.2.4 的 146 增加 compare 与语义化归属判定等用例）；跨后端（`wasm` / `wasm-gc` / `js`）各 **111** 全绿（含 compare 15 项 + 语义化反例/归属测试新增）；native build 通过（端到端 `compare` 实测：健康包双工具链 → AllGreen，退出码 0）。

## [0.2.4] - 2026-10

### 修复

- **`rm_rf` 补上 Windows 宽字符分支**：A 版用 `FindFirstFileA` + `remove` + `_rmdir`，对含中文路径删除必然失败（真实目录是中文名，A 版 `'?'` 路径找不到）。宽字符版用 `FindFirstFileW` + `_wremove` + `_wrmdir` 递归删除，与 `path_kind` / `file_size` / `read_text` 的宽字符分支一致。此前本地（GBK 代码页）恰好能删、CI（UTF-8 代码页）必失败的差异由此消除。
- **非 Windows 平台的中文路径真正可用（`fs_str_to_ascii` UTF-8 编码）**：此前 `fs_str_to_ascii` 把所有非 ASCII 字符（含中文）替换成 `'?'`，导致 Linux / macOS 上含中文目录的本地候选 `copy_tree` 复制失败、整个路径层语义失真（实测 CI 中"复制含中文目录树"回归失败）。本次在非 Windows 分支将 MoonBit String（UTF-16，含代理对）真正编码为 UTF-8 字节，使中文路径在 POSIX 文件系统上原生可用——`mkdir_all` / `write_file` / `read_text` / `copy_tree` 等全部路径函数一并受益。

### 质量基线

- native 测试 146 全绿（含中文路径回归；Windows 走宽字符分支、POSIX 走 UTF-8）

## [0.2.3] - 2026-10

### 修复

- **`copy_tree` / `copy_file` 补上 Windows 宽字符分支**：本地候选验证依赖把用户已有 checkout 复制进隔离工作区。`copy_tree` 的 Windows 分支此前用 `FindFirstFileA` + `fopen`，仓库位于含中文（非 ASCII）路径时复制必然失败（`verify_candidate` 因此对本地中文路径返回 `FetchFailed`）。本次为 `copy_tree` / `copy_file` 补上与 `write_text` 一致的宽字符分支（`FindFirstFileW` / `_wfopen`），并在中文路径回归测试中覆盖"复制含中文目录树"场景。

### 质量基线

- native 测试 146 全绿（含 copy_tree 中文复制回归）

## [0.2.2] - 2026-10

### 修复

- **Windows 中文路径全面支持（`platform/fs`）**：`fs_path_kind`（驱动 `is_dir` / `is_file` / `exists`）、`fs_file_size`、`fs_read_text` 此前走 `fs_str_to_ascii` + `stat`/`fopen`，路径中的非 ASCII 字符（如中文目录名）会被替换成 `'?'` 导致判断/读取必然失败；`fs_write_text` 却已有 `_WIN32` 宽字符分支，两侧处理不一致。本次为这三个函数补上与 `fs_write_text` 一致的 Windows 宽字符（`_wstat` / `_wfopen`）分支，仓库位于含中文的目录下也能正常验证。此为真实缺陷修复（此前已在含中文路径的项目上验证失败）。

### 质量基线

- native 测试 146 全绿（含中文路径回归验证）

## [Unreleased]

把项目定位从"一个 CLI 工具"修正为"**可移植的诊断归因库 + 仅 native 的参考 CLI**"，并把这条边界交给构建器强制。

### 新增

- **真实 moonc 输出语料回归**：新增 5 个由本机 `moonc v0.10.14` 对真实坏代码编译输出校准的测试，覆盖 `[3002] Parse error` / `[4074] 缺返回类型` / `[4080] 参数个数不符` / `[4139] 值不可忽略` / `[4015] has no method`——特征库不再只是措辞清单，而是被真实工具链输出锁定的行为契约
- **库边界由 `supported_targets` 在构建期强制**：库核心七个包（`verify/diagnose`、`report/model`、`report/json`、`report/compare`、`report/site`、`platform/time`、`core/error`）声明 `wasm+wasm-gc+js+native`；三个 C FFI 包与依赖它们的 CLI 链路声明 `native`。任何尝试让库核心引入 FFI 的改动都会在 `moon check` 阶段失败
- **库核心跨后端可用**：`moon test` 在 `wasm` / `wasm-gc` / `js` 上各跑通 **92** 个测试（此前整模块在这三个后端上根本无法编译）
- `build.ps1 -CrossBackend`：一条命令复现上述跨后端验证
- CI 新增三个非 native 后端的库核心测试步骤

### 修复

- **`Parse error` 不再被误判为工具链漂移**：`toolchain_mismatch_markers` 移除 `unexpected token`。语法解析错误是确定的代码错误，不是版本差异；此前含 `unexpected token` 的真实语法错误会被错误归为 `ToolchainMismatch`（已由语料回归测试锁定）
- `build.ps1` 头部补回 UTF-8 BOM。Windows PowerShell 5.1 会把无 BOM 文件按 ANSI（中文环境为 GBK）解码，中文注释被解成乱码后会直接导致语法解析失败
- **消除 `derive(Eq, Debug)` 弃用警告**：显式 `pub extend Diagnosis with Eq::{not_equal, equal}` 与 `@moonbitlang/core/debug.Debug::{to_repr}`，`moon.pkg` 显式导入 `moonbitlang/core/debug`，恢复真正 0 警告构建
- **发布包剔除本地探测目录 `_probe_import`**（已 gitignore、不属交付物），避免打进 mooncakes zip；删除后 native 测试 145、跨后端 92，全绿

### 文档

- 同步实测口径：MoonBit 源码 **5,527 行 / 20 包**（此前文档误写 5,944 / 21）、native 测试 **145**、跨后端 **92**（README / ARCHITECTURE / DEVELOPMENT / CONTRIBUTING / ROADMAP / CHANGELOG 已一致）

### 变更

- README 主叙事改为"库优先"：先说归因引擎与可移植性，CLI 作为参考消费者
- `docs/ARCHITECTURE.md` 的分层图标注每条链路的可用后端，并说明约束为何是构建期强制的

### 质量基线

- 145 个单元测试全绿（native）；92 个 × 3 后端全绿（wasm / wasm-gc / js）
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

