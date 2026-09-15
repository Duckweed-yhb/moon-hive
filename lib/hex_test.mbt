test {
  // Hex 编码：标准值
  inspect(hex_encode("hello"), content="68656c6c6f")
  inspect(hex_encode("MoonBit"), content="4d6f6f6e426974")
}

test {
  // Hex 编码：中文与空串（UTF-8 字节）
  inspect(hex_encode("你好"), content="e4bda0e5a5bd")
  inspect(hex_encode(""), content="")
}

test {
  // Hex 解码：还原原文
  inspect(hex_decode("68656c6c6f"), content="hello")
  inspect(hex_decode("e4bda0e5a5bd"), content="你好")
}

test {
  // 往返：encode 后再 decode 应还原原文
  inspect(hex_decode(hex_encode("MoonBit 2026")), content="MoonBit 2026")
}

test {
  // 非法输入：非法字符 / 奇数长度
  inspect(hex_decode("zz"), content="（解码失败：输入不是合法的十六进制文本）")
  inspect(hex_decode("686"), content="（解码失败：输入不是合法的十六进制文本）")
}
