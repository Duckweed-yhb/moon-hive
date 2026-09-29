# 贡献指南

感谢你有兴趣参与 MoonHive。这是一个单人起步的开源项目，任何形式的贡献（报告问题、提建议、写示例、提 PR）都欢迎。

## 项目是什么

MoonHive = **MoonBit 生态验证引擎**。
用真实 MoonBit 工具链逐个验证生态包能否编译、测试是否通过，把失败归为九类可行动结论。

## 环境准备

- MoonBit 工具链（当前开发环境 `moon 0.1.20260904`，native 后端）
- git
- Windows 注意：**仓库路径含非 ASCII 字符时，直接用 `build.ps1`**——GNU assembler 无法处理中文路径，`build.ps1` 会把产物重定向到系统临时目录（纯 ASCII）

## 快速开始

```powershell
./build.ps1              # 构建
./build.ps1 -Test        # 构建 + 全部测试（当前 132 个，须保持全绿）
./build.ps1 -Run doctor  # 构建 + 运行环境自检
```

## 项目结构

分层边界请先读 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。三条硬规则：

1. **只有 `platform/*` 允许出现 C FFI**（core 不含文件系统与进程模块，这是自建 FFI 的原因）
2. 只有 `verify/check` 知道如何调用 `moon` 命令
3. `core/*` 与 `report/*` 不知道文件系统与进程的存在，因此可以 100% 单元测试

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
