///|
/// platform/time — 耗时与超时判定（纯计算）
///
/// 这些逻辑与文件系统、进程无关，本可以放在 `core/`。
/// 但调用方是 `verify/workspace` 与 `verify/check`——它们已经在平台层之上，
/// 因此放在这里可以避免为一个小模块单独引入 `core/time` 包。
/// 如果将来 core 层也需要它，再上移即可。

///|
/// 一次执行的时间预算
pub struct Budget {
  /// 上限（毫秒）；<= 0 表示不限制
  limit_ms : Int
  /// 已消耗（毫秒）
  spent_ms : UInt64
}

///|
/// 新建预算
pub fn budget(limit_ms : Int) -> Budget {
  { limit_ms, spent_ms: 0UL }
}

///|
/// 记录消耗时间
pub fn spend(b : Budget, elapsed_ms : UInt64) -> Budget {
  { limit_ms: b.limit_ms, spent_ms: b.spent_ms + elapsed_ms }
}

///|
/// 是否已超时
pub fn is_timed_out(b : Budget) -> Bool {
  if b.limit_ms <= 0 {
    return false
  }
  b.spent_ms > b.limit_ms.to_uint64()
}

///|
/// 剩余毫秒数。不限制时返回 limit（即原值）；已超时返回 0。
pub fn remaining_ms(b : Budget) -> Int {
  if b.limit_ms <= 0 {
    return b.limit_ms
  }
  let limit = b.limit_ms.to_uint64()
  if b.spent_ms >= limit {
    0
  } else {
    (limit - b.spent_ms).to_int()
  }
}

///|
/// 已消耗毫秒数
pub fn spent_ms(b : Budget) -> UInt64 {
  b.spent_ms
}

///|
/// 把毫秒格式化为人类可读的耗时（用于报告）
pub fn format_ms(ms : UInt64) -> String {
  if ms < 1000UL {
    return ms.to_string() + "ms"
  }
  let seconds = ms / 1000UL
  let rem = ms % 1000UL
  if seconds < 60UL {
    return seconds.to_string() + "." + (rem / 100UL).to_string() + "s"
  }
  let minutes = seconds / 60UL
  let sec = seconds % 60UL
  minutes.to_string() + "m" + sec.to_string() + "s"
}

// ---------- 单元测试 ----------

test "budget: 未消耗时不超时" {
  let b = budget(1000)
  assert_false(is_timed_out(b))
  assert_eq(remaining_ms(b), 1000)
}

test "budget: 累计消耗并判定超时" {
  let b = budget(1000)
  let b2 = spend(b, 600UL)
  assert_false(is_timed_out(b2))
  assert_eq(remaining_ms(b2), 400)
  let b3 = spend(b2, 500UL)
  assert_true(is_timed_out(b3))
  assert_eq(remaining_ms(b3), 0)
}

test "budget: limit <= 0 表示不限制" {
  let b = spend(budget(0), 999999UL)
  assert_false(is_timed_out(b))
  assert_eq(remaining_ms(b), 0)
  let b2 = spend(budget(-5), 999999UL)
  assert_false(is_timed_out(b2))
}

test "budget: 恰好等于上限不算超时" {
  let b = spend(budget(500), 500UL)
  assert_false(is_timed_out(b))
  assert_eq(remaining_ms(b), 0)
}

test "format_ms: 毫秒 / 秒 / 分" {
  assert_eq(format_ms(0UL), "0ms")
  assert_eq(format_ms(999UL), "999ms")
  assert_eq(format_ms(1000UL), "1.0s")
  assert_eq(format_ms(1500UL), "1.5s")
  assert_eq(format_ms(59000UL), "59.0s")
  assert_eq(format_ms(60000UL), "1m0s")
  assert_eq(format_ms(125000UL), "2m5s")
}

test "spent_ms 返回累计值" {
  assert_eq(spent_ms(spend(spend(budget(100), 10UL), 20UL)), 30UL)
}
