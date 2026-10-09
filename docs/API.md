# MoonHive 库 API 参考

> 包路径：`verify/diagnose`
> 安装：`moon add Duckweed/moon-hive`，然后 `import "Duckweed/moon-hive/verify/diagnose" @diagnose`
> 后端：本包是**纯计算**（不 import 任何 C FFI 包），在 `wasm` / `wasm-gc` / `js` / `native` 四个后端均可编译运行

本文件是 `verify/diagnose` 的公开 API 契约。它把 MoonBit 工具链的输出归类为可行动的结论，核心是回答一个问题：**"这个包在我这套工具链上能不能用，失败该归因给谁"**。

---

## 类型

### `enum Diagnosis`

验证结论，共九种变体（`derive(Eq, Debug)`）：

| 变体 | 含义 |
|---|---|
| `Verified` | 编译与测试全绿，可直接使用 |
| `TestFailing(String)` | 能编译，但测试未通过 |
| `DoesNotCompile(String)` | 编译器报错（真正的代码问题） |
| `ToolchainMismatch(String)` | 诊断指向工具链版本 / API 不兼容——**不是包的错** |
| `MissingDependency(String)` | 依赖解析失败 |
| `NoManifest` | 不是 MoonBit 模块（没有 `moon.mod`） |
| `TimedOut` | 超出时间预算 |
| `Unsafe` | 含 FFI / 自定义构建脚本，只做静态分析不执行 |
| `FetchFailed(String)` | 克隆或准备工作区失败 |

带 `String` 负载的变体携带该结论的证据（首条诊断信息）。

### `struct CommandOutcome`

一次命令的结果，是诊断分类的最小输入单位：

```moonbit
struct CommandOutcome {
  exit_code : Int
  stdout    : String
  stderr    : String
}
```

### `struct CheckOutcome`

`classify` 的完整输入，汇总一次验证的所有可观察事实：

```moonbit
struct CheckOutcome {
  has_manifest     : Bool           // 目录里是否存在 moon.mod
  risky            : Bool           // 是否含 FFI / 构建脚本（安全起见不执行）
  timed_out        : Bool           // 是否超出时间预算
  check            : CommandOutcome // moon check 的结果
  test_outcome     : CommandOutcome? // moon test 的结果；未执行时为 None
  declared_targets : Array[String]  // 仓库声明的目标后端列表（空表示未声明）
  target           : String         // 本次实际使用的目标后端
}
```

---

## 核心函数

### `classify`

```moonbit
pub fn classify(o : CheckOutcome) -> Diagnosis
```

根据检查结果给出结论。**判定顺序有讲究**，见下方[判定顺序](#判定顺序)。

### `explain`

```moonbit
pub fn explain(d : Diagnosis) -> String
```

结论的简要解释（面向用户的中文说明）。例如 `ToolchainMismatch(_)` → `"版本/API 不兼容——不是包的问题，是工具链版本差异"`。

### `evidence`

```moonbit
pub fn evidence(d : Diagnosis) -> String
```

结论附带的证据（首条诊断信息）。`Verified`、`NoManifest`、`TimedOut`、`Unsafe` 返回空串；带负载的变体返回其负载。

### `label` / `mark`

```moonbit
pub fn label(d : Diagnosis) -> String
pub fn mark(d : Diagnosis) -> String
```

- `label`：结论的短标签（用于表格与 JSON），如 `"ToolchainMismatch"`。
- `mark`：结论的符号（用于终端展示），如 `✅` / `⚠️` / `❌` / `🚫`。

### `is_usable`

```moonbit
pub fn is_usable(d : Diagnosis) -> Bool
```

是否为"可用"的结论。目前仅 `Verified` 返回 `true`。

### `count_issues`

```moonbit
pub fn count_issues(text : String) -> (Int, Int)
```

统计诊断文本中的 `(errors, warnings)` 数量，解析 `Failed with N warnings, M errors` 这类汇总行。

### `extract_missing_symbols`

```moonbit
pub fn extract_missing_symbols(text : String) -> Array[String]
```

从诊断文本中提取缺失的符号名。例如从
`Type Bytes has no method exact_view.` 提取出 `Bytes.exact_view`，让"缺了什么"可被机器消费。

### `first_error_line`

```moonbit
pub fn first_error_line(text : String) -> String
```

从诊断文本中提取最有价值的一条错误描述。三轮筛选（实测校准过）：先取带 `error` 关键词且不是纯错误码的行；退而取"像诊断内容"的行；最后兜底取第一行非装饰性文本。**不能只取"第一行含 error"**——MoonBit 诊断常把 `Error: [4015]`（只有错误码、无内容）放在具体错误之前。

---

## 判定顺序

`classify` 的判定顺序（顺序错了会产生误导性结论）：

1. **前提**：`has_manifest` 为假 → `NoManifest`
2. **安全**：`risky` 为真 → `Unsafe`（含 FFI / 构建脚本，不执行）
3. **超时**：`timed_out` → `TimedOut`
4. **目标后端不匹配**：仓库声明了后端但不含本次 `target` → `ToolchainMismatch`
5. **check 失败**：按 `MissingDependency` → `ToolchainMismatch` → 真正的 `DoesNotCompile` 依次判定
6. **check 通过**：`test_outcome` 失败 → `TestFailing`；全过 → `Verified`

关键点：依赖缺失和工具链不兼容的特征经常同时出现，**必须优先判定依赖缺失**，否则会误归因。

---

## 完整示例

```moonbit
import "Duckweed/moon-hive/verify/diagnose" @diagnose

fn judge(outcome : @diagnose.CheckOutcome) -> Unit {
  let d = @diagnose.classify(outcome)
  match d {
    @diagnose.Verified => println("可以直接用")
    @diagnose.ToolchainMismatch(why) => println("不是包的错：" + why)
    @diagnose.DoesNotCompile(why) => println("包在当前工具链上不可用：" + why)
    _ => println(@diagnose.explain(d))
  }
}
```

---

## 已知限制

- 特征库（`toolchain_mismatch_markers` / `missing_dependency_markers` / `test_failure_markers`）是**内置硬编码**的字符串匹配，依赖 MoonBit 编译器的当前措辞；工具链措辞演进可能影响判定。`ToolchainMismatch` 的判定刻意保守（宁可判 `DoesNotCompile` 也不滥用），用真实 `moonc` 输出做过语料回归校准。
- 本包是纯计算层，只吃字符串、返回结论，不做文件系统与进程操作；需要端到端验证请使用 CLI 或上层 `verify/` 包。
