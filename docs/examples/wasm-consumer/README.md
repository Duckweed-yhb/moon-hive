# wasm-consumer —— 非 native 消费者最小示例

证明 MoonHive 的**库核心**（`verify/diagnose`）是纯计算，可在 `wasm` / `js` 后端直接使用，**脱离 CLI 与 C FFI 独立可用**。

这个示例独立 `moon add Duckweed/moon-hive@0.2.1`，构造 `CheckOutcome` 调用 `classify`，断言归因结论。

```bash
moon test --target wasm     # 2 个测试全过
moon test --target js       # 2 个测试全过
moon test --target native   # 2 个测试全过
```

三个后端都能编译并跑通，说明归因逻辑不依赖任何平台能力——这正是 MoonHive 与"git clone + 脚本"的本质区别：**归因引擎是一个可以在任何环境被 import 的独立库**。

## 结构

```
wasm-consumer/
├── moon.mod        声明依赖 Duckweed/moon-hive@0.2.1
└── main/
    ├── moon.pkg    库包，supported_targets = all
    └── main.mbt    构造场景 → classify → 断言（2 个测试）
```

## 关键点

- 只 import `verify/diagnose`（纯计算包），不触碰 CLI 或 `platform/*` 的 C FFI
- `main.mbt` 里的两个测试分别覆盖 `ToolchainMismatch`（工具链不匹配）与 `NoManifest`（缺清单）两条判定路径
- 在浏览器 / Node / 其它 wasm 环境里复用同一套归因逻辑，是零改动的
