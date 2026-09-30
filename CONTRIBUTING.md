# 贡献指南

感谢你有兴趣参与 MoonHive。这是一个单人起步的开源项目，任何形式的贡献（报告问题、提建议、写示例、提 PR）都欢迎。

## 项目是什么

MoonHive = **MoonBit 工具链输出的诊断归因库**，附带一个参考 CLI。
给它一段 `moon check` 的输出，判断这堆错误是"包真的坏了"还是"工具链版本对不上"——把健康的库标成不可用，比没有工具更糟。

库核心（归因分类器与报告渲染）是纯计算，在 `wasm` / `wasm-gc` / `js` / `native` 四个后端都可编译可测试；C FFI 与 CLI 链路限定 native。

## 环境准备

- MoonBit 工具链（当前开发环境 `moon 0.1.20260904`，native 后端）
- git
- Windows 注意：**仓库路径含非 ASCII 字符时，直接用 `build.ps1`**——GNU assembler 无法处理中文路径，`build.ps1` 会把产物重定向到系统临时目录（纯 ASCII）。`build.ps1` 必须存为 UTF-8 **带 BOM**（PowerShell 5.1 会把无 BOM 文件按 GBK 解码，中文注释会导致解析失败）

## 快速开始

```powershell
./build.ps1                 # 构建
./build.ps1 -Test           # 构建 + 全部测试（当前 140 个，须保持全绿）
./build.ps1 -CrossBackend   # 额外验证库核心在 wasm / wasm-gc / js 上可用（各 87 个）
./build.ps1 -Run doctor     # 构建 + 运行环境自检
```

## 项目结构

分层边界请先读 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。四条硬规则：

1. **只有 `platform/proc`、`platform/fs`、`platform/http` 允许出现 C FFI**（core 不含文件系统与进程模块，这是自建 FFI 的原因）
2. 只有 `verify/check` 知道如何调用 `moon` 命令
3. `core/*`、`verify/diagnose`、`report/*` 不知道文件系统与进程的存在，因此可以 100% 单元测试
4. **库核心不得引入平台依赖**——这条由各包 `supported_targets` 在构建期强制：改动若破坏了它，`moon test --target wasm` 会直接失败

## 如何贡献

### 报告问题

- 标题：一句话概括现象（如 `inspect 对本地目录报 NoManifest`）
- 内容包含：复现步骤、期望行为、实际行为、环境（`moon --version`、操作系统）
- 贴**完整**报错输出，含 warning——warning 往往比 error 信息量更大

### 提交代码

1. fork 仓库，新建分支（如 `feature/xxx` 或 `fix/xxx`）
2. 一个 PR 一个主题，改动保持最小
3. **新功能必须带测试**，提交前确认 `moon test` 全绿、构建零警告
4. 注释写"为什么"而不是"是什么"；用中文注释
5. PR 描述写清：改了什么、为什么、测试结果

## 代码规范

- 保持格式与现有代码一致（可参考 `moon fmt`）
- **不引入第三方依赖**——零第三方依赖是本项目的卖点（只用 `moonbitlang/core` + 自建 C FFI）。确有必要时，先开 issue 讨论
- 报告输出、文档用语保持简洁，不堆砌术语

## 行为准则

- 友善交流，对事不对人
- 新手贡献者同样欢迎，问题在 issue 里公开讨论，不私信打扰
- 本项目遵循 [Contributor Covenant](https://www.contributor-covenant.org/) 的精神
