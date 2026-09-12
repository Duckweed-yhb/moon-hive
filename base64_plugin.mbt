///|
pub(all) struct Base64Plugin {}

///|
pub impl Plugin for Base64Plugin with name(_self) {
  "base64"
}

///|
pub impl Plugin for Base64Plugin with description(_self) {
  "Base64 编码/解码插件：支持字符串的编码/解码"
}

///|
pub impl Plugin for Base64Plugin with execute(_self, command, args) {
  match command {
    "encode" => {
      if args.length() < 1 {
        "用法: moon run cmd/main base64 encode <文本>"
      } else {
        base64_encode(args[0])
      }
    }
    "decode" => {
      if args.length() < 1 {
        "用法: moon run cmd/main base64 decode <Base64文本>"
      } else {
        base64_decode(args[0])
      }
    }
    _ => "未知命令: \{command}（支持: encode / decode）"
  }
}

///| Base64 编码：把字符串按 UTF-8 转字节，再编码为标准 Base64
pub fn base64_encode(input : String) -> String {
  let bytes = @utf8.encode(input)
  let table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  let mut result = ""
  let mut i = 0
  while i < bytes.length() {
    let b1 = bytes[i].to_int()
    let b2 = if i + 1 < bytes.length() { bytes[i + 1].to_int() } else { 0 }
    let b3 = if i + 2 < bytes.length() { bytes[i + 2].to_int() } else { 0 }
    let i0 = b1 >> 2
    let i1 = ((b1 & 0x03) << 4) | (b2 >> 4)
    let i2 = ((b2 & 0x0F) << 2) | (b3 >> 6)
    let i3 = b3 & 0x3F
    result = result + "\{Int::unsafe_to_char(table[i0].to_int())}"
    result = result + "\{Int::unsafe_to_char(table[i1].to_int())}"
    if i + 1 < bytes.length() {
      result = result + "\{Int::unsafe_to_char(table[i2].to_int())}"
    } else {
      result = result + "="
    }
    if i + 2 < bytes.length() {
      result = result + "\{Int::unsafe_to_char(table[i3].to_int())}"
    } else {
      result = result + "="
    }
    i = i + 3
  }
  result
}

///| Base64 字符 → 6 位值（-1 表示 '=' 填充，-2 表示非法字符）
fn char_to_value(v : Int) -> Int {
  if v >= 65 && v <= 90 { v - 65 }
  else if v >= 97 && v <= 122 { v - 71 }
  else if v >= 48 && v <= 57 { v + 4 }
  else if v == 43 { 62 }
  else if v == 47 { 63 }
  else if v == 61 { -1 }
  else { -2 }
}

///| Base64 解码：把 Base64 文本还原为原始字符串
pub fn base64_decode(input : String) -> String {
  let vals = []
  let mut invalid = false
  let mut i = 0
  while i < input.length() {
    let v = char_to_value(input[i].to_int())
    if v == -2 {
      invalid = true
    } else if v >= 0 {
      vals.push(v)
    }
    i = i + 1
  }
  if invalid {
    return "（解码失败：输入含非法字符）"
  }
  let out = []
  let mut j = 0
  while j + 3 < vals.length() {
    let v1 = vals[j]
    let v2 = vals[j + 1]
    let v3 = vals[j + 2]
    let v4 = vals[j + 3]
    let b1 = (v1 << 2) | (v2 >> 4)
    let b2 = ((v2 & 0x0F) << 4) | (v3 >> 2)
    let b3 = ((v3 & 0x03) << 6) | v4
    out.push(b1.to_byte())
    out.push(b2.to_byte())
    out.push(b3.to_byte())
    j = j + 4
  }
  let rest = vals.length() - j
  if rest >= 2 {
    let b1 = (vals[j] << 2) | (vals[j + 1] >> 4)
    out.push(b1.to_byte())
    if rest >= 3 {
      let b2 = ((vals[j + 1] & 0x0F) << 4) | (vals[j + 2] >> 2)
      out.push(b2.to_byte())
    }
  }
  try {
    @utf8.decode(Bytes::from_array(out))
  } catch {
    _ => "（解码失败：不是合法的 UTF-8 文本）"
  }
}
