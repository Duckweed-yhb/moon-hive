///|
pub(all) struct HexPlugin {}

///|
pub impl Plugin for HexPlugin with name(_self) {
  "hex"
}

///|
pub impl Plugin for HexPlugin with description(_self) {
  "十六进制编解码插件：支持字符串的编码/解码"
}

///|
pub impl Plugin for HexPlugin with execute(_self, command, args) {
  match command {
    "encode" => {
      if args.length() < 1 {
        "用法: moon run cmd/main hex encode <文本>"
      } else {
        hex_encode(args[0])
      }
    }
    "decode" => {
      if args.length() < 1 {
        "用法: moon run cmd/main hex decode <十六进制文本>"
      } else {
        hex_decode(args[0])
      }
    }
    _ => "未知命令: \{command}（支持: encode / decode）"
  }
}

///| 把 0~15 转成一个十六进制字符（'0'-'9' / 'a'-'f'）
fn hex_char(v : Int) -> String {
  if v < 10 {
    "\{Int::unsafe_to_char(48 + v)}"
  } else {
    "\{Int::unsafe_to_char(87 + v)}"
  }
}

///| 十六进制编码：每个字节拆成高 4 位 + 低 4 位，各转一个字符
pub fn hex_encode(input : String) -> String {
  let bytes = @utf8.encode(input)
  let mut result = ""
  let mut i = 0
  while i < bytes.length() {
    let b = bytes[i].to_int()
    result = result + hex_char(b >> 4) + hex_char(b & 0x0F)
    i = i + 1
  }
  result
}

///| 十六进制字符 → 0~15（-1 表示非法字符）
fn hex_value(c : Int) -> Int {
  if c >= 48 && c <= 57 { c - 48 }
  else if c >= 97 && c <= 102 { c - 87 }
  else if c >= 65 && c <= 70 { c - 55 }
  else { -1 }
}

///| 十六进制解码：每两个字符还原成一个字节
pub fn hex_decode(input : String) -> String {
  let out = []
  let mut invalid = false
  let mut i = 0
  while i + 1 < input.length() {
    let hi = hex_value(input[i].to_int())
    let lo = hex_value(input[i + 1].to_int())
    if hi < 0 || lo < 0 {
      invalid = true
    } else {
      out.push(((hi << 4) | lo).to_byte())
    }
    i = i + 2
  }
  if input.length() % 2 == 1 {
    invalid = true
  }
  if invalid {
    return "（解码失败：输入不是合法的十六进制文本）"
  }
  try {
    @utf8.decode(Bytes::from_array(out))
  } catch {
    _ => "（解码失败：不是合法的 UTF-8 文本）"
  }
}
