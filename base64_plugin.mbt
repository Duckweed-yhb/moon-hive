///|
pub(all) struct Base64Plugin {}

///|
pub impl Plugin for Base64Plugin with name(_self) {
  "base64"
}

///|
pub impl Plugin for Base64Plugin with description(_self) {
  "Base64 编码/解码插件：支持字符串与文件的编码/解码"
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
    "decode" => "解码功能开发中（Day 5 完成）"
    _ => "未知命令: \{command}（支持: encode）"
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
