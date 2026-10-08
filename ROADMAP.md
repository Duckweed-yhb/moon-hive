# Roadmap

MoonHive 的当前状态与下一步计划。作为新项目，规划是持续更新的：每完成一块就勾掉，新想法加进来。

## 现状（2026-09）

- ✅ v2 验证引擎：145 测试全绿、构建零警告、零第三方依赖
- ✅ **库边界构建期强制**：库核心七个包在 `wasm` / `wasm-gc` / `js` / `native` 四个后端都可编译可测试（92 测试 × 3 后端），CLI 链路明确限定 native
- ✅ 真实生态普查：mooncakes 18 包三轮验证（9/25–27），结果完全一致，可用率 16.7%
- ✅ 报告三格式：Markdown / JSON / 静态 HTML（Pages 在线报告已部署）
- ✅ 收藏夹：keep / list / forget 三个命令，本地存 favorites.json

## 短期（2026-10）

- [x] 发布到 mooncakes.io（**0.2.1 已发布**，`moon add Duckweed/moon-hive` 即可使用；发布包已剔除本地探测目录）——**库声明可移植之后，这一步的意义从"顺手发个包"变成"让别人真的能 `moon add` 用上归因引擎"**
- [x] 真实工具链语料回归：用 `moonc v0.10.14` 固化错误码语料，修复 `[3002] Parse error` 误归为 `ToolchainMismatch` 的缺陷
- [ ] 公开 API 参考：把 `classify` / `explain` / `evidence` / `count_issues` / `extract_missing_symbols` 的契约写成文档（当前靠 doc comment）
- [ ] 治理收尾：CONTRIBUTING / ROADMAP 落定（即本文档）

## 中期

- [ ] **库与 CLI 拆成两个模块**（`moon.work` 工作区）：目前靠 `supported_targets` 在同一模块内划边界，已能满足"库核心可移植"；进一步拆成独立模块后，消费方可以只 `moon add` 纯核心、完全不把 CLI 与 C FFI 拉进依赖图
- [ ] **一个非 native 消费者的最小示例**：在 wasm/js 环境里直接调用 `classify`，证明库脱离 CLI 也能用
- [ ] **多工具链对比**：同一包在不同 moon 版本上验证，用数据区分"包坏了"与"工具链演进"
- [ ] **趋势追踪**：定时运行 survey，追踪生态包可用性随时间的变化
- [ ] **网页 Badge**：像 shields.io 那样给每个 mooncakes 包提供验证状态标识

## 长期

- [ ] 成为 **MoonBit 生态的验证基础设施**：回答"这个包在特定工具链上能不能用"
- [ ] 持续追踪：每周自动跑普查，生态健康仪表盘
- [ ] 接受社区提交的候选包清单

## 参与方式

- 提 issue / 提 PR：见 [CONTRIBUTING.md](CONTRIBUTING.md)
- 想优先验证哪些包？在 issue 里提"候选清单"建议
