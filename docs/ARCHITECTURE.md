# MoonHive 架构说明

## 一句话

MoonHive 把候选 MoonBit 包拉到隔离工作区，**用真实的 MoonBit 工具链**验证它能不能编译、测试过不过，并把失败归类成九种可行动的结论。

## 为什么这件事需要专门做

GitHub 搜索能告诉你一个仓库有多少 star，搜索能告诉你它用什么语言，但**没有任何工具能告诉你"这个包在我这套工具链上跑不跑得起来"**。

实测证据：`moonbitlang/x` 是 MoonBit 生态里最活跃的库之一（167 个 `.mbt` 文件、约 30,000 行、58 个测试文件），但在一台工具链版本不同的机器上：

```
$ moon check --target native
Failed with 0 warnings, 14 errors.
  Type Bytes has no method exact_view.
```

**这不是"这个包坏了"，而是工具链版本差异。** 分不清这两者，工具就会撒谎——把生态里健康的库标成不可用，比没有工具更糟。MoonHive 的核心价值就在于**正确归因**。

## 分层与边界

```
cmd/moonhive              CLI 入口：参数解析与分发，不含业务逻辑
  │
features/                应用层：把能力组装成命令
  ├── doctor             环境自检
  ├── inspect            单包体检
  └── survey             批量普查 + 报告
  │
verify/                  验证层
  ├── workspace    ⭐     隔离工作区：生命周期、归属校验、配额、清理
  ├── gitsource    ⭐     候选解析、git 克隆、TLS 后端探测
  ├── check        ⭐     工具链驱动：编排"取仓库 → 预检 → check → test"
  └── diagnose     ⭐⭐    诊断分类：把工具链输出归类为九种结论（核心资产）
  │
platform/                平台层：唯一允许出现 C FFI 的地方
  ├── proc         ⭐     子进程执行、输出捕获、捕获文件读回
  ├── fs           ⭐     目录遍历/复制/清理、文本读写（UTF-8 编解码）
  └── time                超时预算与耗时格式化（纯计算）
  │
core/
  └── error               统一错误契约、类别与退出码映射（纯计算）
```

### 三条可替换性声明

1. **只有 `platform/*` 出现 C FFI。** 想换掉底层实现（例如改用别的进程 API、或把文件操作换成第三方库），只需替换这一层，`verify/` 与 `features/` 一行不动。
2. **只有 `verify/check` 知道怎么调用 `moon` 命令。** 工具链的调用方式（参数、超时、输出解析）全部收敛在这一个文件里。
3. **`core/` 与 `verify/diagnose` 不知道文件系统与进程的存在。** 它们只吃字符串、返回结论，因此能做到 100% 离线单元测试——这也是测试数能从 61 继续往上走而不依赖网络的原因。

### 为什么会有 `platform/` 这一层

`moonbitlang/core` **不提供文件系统与进程模块**（它们只存在于第三方的 `moonbitlang/async`）。而 MoonHive 的核心能力——起进程跑工具链、读编译器诊断、管理真实工作区——**必须**依赖它们。

因此这里做了一个明确取舍：**自建 C FFI 层，而不是引入第三方包**。这样做的收益是依赖面为零、行为完全可控；代价是需要自己处理跨平台差异（Winsock/POSIX）与 C/MoonBit 边界上的类型转换。

## 数据流

```
候选输入（owner/repo | HTTPS URL | 本地目录）
   │
   ├─ gitsource.from_slug / from_local ─────────► Candidate
   │
   ├─ workspace.create ─────────────────────────► Workspace（临时目录下的唯一根）
   │
   ├─ workspace.alloc(slug) ────────────────────► 该候选的独立子目录
   │
   ├─ gitsource.clone_repo / fs.copy_tree ──────► 代码就位
   │     └─ 远端经 git（TLS 后端自动探测）；本地目录直接复制
   │
   ├─ 静态预检（不执行仓库代码）
   │     ├─ is_moonbit_module → moon.mod / moon.mod.json / moon.work
   │     ├─ detect_declared_targets → 保守识别声明的后端
   │     ├─ detect_unsafe → native-stub / cc-link-flags / 自带 .c
   │     └─ measure_repo → .mbt 数量 / 行数 / 测试文件数 / 体积
   │
   ├─ proc.run("moon check --target <t>") ──────► CommandOutcome
   │     └─ 仅在 check 通过且允许时才继续跑 moon test
   │
   ├─ diagnose.classify(CheckOutcome) ──────────► Diagnosis（九类之一）
   │
   └─ survey.render_markdown / inspect.render_result ──► 报告与终端输出
```

## 九类结论与判定顺序

判定顺序是刻意设计的——**顺序错了会产生误导性结论**。

| 顺序 | 结论 | 触发条件 | 为什么排在这个位置 |
|---|---|---|---|
| 1 | `NoManifest` | 没有模块清单 | 前提不成立，后面都是无意义的 |
| 2 | `Unsafe` | 含 FFI / 自定义构建配置 | 安全优先于一切，且此时**不应执行工具链** |
| 3 | `TimedOut` | 超出时间预算 | 时间用尽后继续判定会得出不可靠结论 |
| 4 | `ToolchainMismatch` | 声明的目标后端不含本次使用的后端 | 环境不匹配时，编译结果不能归因于代码 |
| 5 | `MissingDependency` | 依赖解析失败 | 优先于工具链判定：两者特征常同时出现，而依赖问题更具体 |
| 6 | `ToolchainMismatch` | 诊断含"方法/类型不存在"等版本漂移特征 | 与真正的编译错误区分开——**这是本项目最关键的一次判断** |
| 7 | `DoesNotCompile` | 其余编译失败 | 排除以上所有之后，才能归因于代码本身 |
| 8 | `TestFailing` | check 通过但测试失败 | 能编译说明接口可用，只是质量未达标 |
| 9 | `Verified` | 全绿 | 唯一"可以直接使用"的结论 |

`FetchFailed` 是第 0 类：获取阶段就失败，未进入判定流程。

### 工具链不兼容的特征库

区分工具链问题与代码问题，靠的是一组**具体的**特征串：

```
has no method          引用当前工具链不存在的 API
no method named
unknown method
unresolved identifier
unknown type / type not found
unsupported target
no such field
unexpected token       语法层面的漂移
```

这组特征刻意保守：**宁可把工具链问题判成代码问题（冤枉一个包），也不要把代码问题判成工具链问题（掩盖一个坏包）**。前者用户自己会发现，后者会让工具撒谎。

## 安全设计

验证陌生代码有固有风险。MoonHive 的策略是**限制自己能做什么**：

1. **只调用官方工具链的 `check` 与 `test`**，不用 `build`。原因是 `build` 会在目标平台编译 C stub，编译过程可能执行未受控的构建逻辑。
2. **静态预检在前**：检出 `native-stub`、`cc-link-flags`、自带 `.c` 文件的仓库直接判为 `Unsafe`，**根本不执行工具链**。
3. **一次性隔离工作区**：所有验证在临时目录下的独立根内进行，完成后逐个释放、整体销毁。
4. **删除前做归属校验**：`workspace.release` 检查目标是否真的在工作区根之下，`fs.rm_rf` 在 C 侧额外拒绝过短路径与驱动器根。
5. **超时与配额**：单条命令有超时上限；工作区有磁盘占用统计与配额判定。

## 已知约束

| 约束 | 原因 | 应对 |
|---|---|---|
| 构建产物路径必须为纯 ASCII | Windows 上 native 后端调用 GNU assembler，汇编器无法处理非 ASCII 路径 | 仓库自带 `build.ps1` 自动把产物重定向到 ASCII 目录 |
| 只支持 native 后端 | C FFI 不支持 wasm 后端 | 这是有意的架构选择：本工具是本地 CLI，不需要在 wasm 运行时里跑 |
| 需要 git 与 moon 工具链 | 仓库获取与验证都依赖它们 | `moonhive doctor` 检查二者是否可用 |
| Windows 上可能需要 openssl TLS 后端 | 部分环境系统配置了 `http.sslBackend = schannel` 而该后端取不到凭据 | 自动探测并**只在本条命令上**用 `-c` 传入，不修改用户全局配置；`doctor` 会给出修复建议 |

## 错误处理约定

- 对外 API 一律返回 `Result[T, E]`，错误类型用 `suberror` 定义并可穷尽匹配。
- **非零退出码不是错误**——编译器报错就是非零退出码，它是正常结果，因此 `proc.run` 成功路径也返回 `Output`。
- 进程层内部错误码统一定义在 `-1000` 以下，与真实退出码彻底分离（早期版本的 `-1` 冲突导致"命令正常失败"被误报成"无法创建进程"）。
- CLI 退出码：`0` 成功 / `10` 环境 / `11` 进程 / `12` 文件 / `13` 未找到 / `14` 参数 / `15` 工具链。

## C FFI 边界的实现要点

在 C 与 MoonBit 之间传递数据有两个容易出错的地方，都在实现中显式处理了：

1. **UTF-8 ↔ UTF-16**：MoonBit 的 `String` 是 UTF-16。若把文件字节逐字节当作 UTF-16 码元，多字节字符会变成乱码（实测：编译器输出里的框线字符变成 `âââ`）。因此所有文本读取都做正规的 UTF-8 解码，写入时做 UTF-8 编码，均处理代理对、BOM 与非法序列。
2. **符号唯一性**：两个 C stub 文件最终链接进同一个可执行文件，同名符号会导致 `multiple definition`。因此 `proc` 侧的文件操作使用 `proc_` 前缀（`proc_read_file` / `proc_remove_file`），与 `fs` 侧的通用实现区分开。
