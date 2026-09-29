# 变更记录

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/) 风格，版本号遵循语义化版本。

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

- 132 个单元测试，全部通过
- 构建 0 警告
- 仅依赖 MoonBit core 标准库与自建 C FFI 平台层，零第三方运行时依赖
