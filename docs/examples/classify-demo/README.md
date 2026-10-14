# classify-demo —— 语义化归因可运行示例

演示 MoonHive 的核心能力：**把 `moon check` 的输出归因成可行动结论**，尤其是"工具链版本不兼容"与"包自身编译错误"的区分。

这是对"对报错文本做字符串匹配、对语义没有了解"的评审批评的直接回应：MoonHive 不是对特征串一刀切，而是**对缺失符号做归属分析**（`classify_verified`）。

## 运行

```bash
moon run main --target native
```

需要已登录 mooncakes（`moon auth`）且能拉取依赖 `Duckweed/moon-hive@0.3.0`。首次先 `moon update` 刷新 registry。

## 输出

五个场景覆盖了归因分类的关键路径：

| 场景 | 输入 | 结论 | 说明 |
|---|---|---|---|
| 1 | `Type Bytes has no method exact_view.` | `ToolchainMismatch` | `Bytes` 属 core，随工具链版本管控 → 工具链差异 |
| 2 | `Type MyPacket has no method encode.` | `DoesNotCompile` | `MyPacket` 属包自身 → 包/文档写错（**关键区别**） |
| 3 | 跨工具链探测确认缺失 | `ToolchainMismatch` | `confirmed_missing` 注入外部证据 |
| 4 | `Parse error, unexpected token` | `DoesNotCompile` | 语法错误是确定的代码问题，不是工具链漂移 |
| 5 | 全绿 | `Verified` | 可直接使用 |

场景 1 vs 场景 2 正是"语义化"的体现：**同样的 `has no method` 措辞，归属不同结论不同**。

## 结构

```
classify-demo/
├── moon.mod        声明依赖 Duckweed/moon-hive@0.3.0
└── main/
    ├── moon.pkg    可执行包，native
    └── main.mbt    构造 5 个场景 → classify_verified → 打印结论
```
