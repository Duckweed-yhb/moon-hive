test {
  // Base64 编码：标准值
  inspect(base64_encode("hello"), content="aGVsbG8=")
  inspect(base64_encode("a"), content="YQ==")
  inspect(base64_encode("ab"), content="YWI=")
  inspect(base64_encode("abc"), content="YWJj")
  inspect(base64_encode("MoonBit"), content="TW9vbkJpdA==")
}

test {
  // Base64 编码：中文与空串
  inspect(base64_encode("你好"), content="5L2g5aW9")
  inspect(base64_encode(""), content="")
}

test {
  // Base64 解码：还原原文
  inspect(base64_decode("aGVsbG8="), content="hello")
  inspect(base64_decode("5L2g5aW9"), content="你好")
  inspect(base64_decode(""), content="")
}

test {
  // 往返：encode 后再 decode 应还原原文（含中文、标点）
  inspect(base64_decode(base64_encode("MoonBit 2026!")), content="MoonBit 2026!")
  inspect(base64_decode(base64_encode("你好，世界")), content="你好，世界")
}

test {
  // 非法输入：应返回错误提示而不是崩溃
  inspect(base64_decode("@@@"), content="（解码失败：输入含非法字符）")
}
