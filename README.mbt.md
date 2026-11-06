# MuVirus/cobs

纯 [MoonBit](https://www.moonbitlang.com) 实现的 COBS（Consistent Overhead Byte
Stuffing，一致性开销字节填充）协议库。

- **纯 MoonBit、零第三方依赖**：只使用语言内置类型，wasm / js / native 后端均可编译。
- **完整 API**：一次性编解码 + 流式增量解码器，适合串口、TCP 等字节流链路。

## 什么是 COBS

COBS 是一种字节填充（成帧）算法：编码后的帧**内部保证不含 `0x00`**，以单个
`0x00` 作为帧分隔符。接收方只需按 `0x00` 切分字节流即可定位帧边界，因此对
噪声或丢字节具有天然的重同步能力。相比 SLIP / PPP 转义，它的开销是**一致的**：
最坏情况每 254 字节只增加 1 字节（加上末尾分隔符），即
`encode` 输出长度不超过 `max_encoded_len(n) = n + n/254 + 2`。

## 用法

在你的 `moon.pkg` 中添加依赖：

```json
import {
  "MuVirus/cobs" @cobs,
}
```

一次性编解码：

```moonbit nocheck
let payload = b"\x01\x02\x00\x03hello\x00world"
let frame = @cobs.encode(payload)
// frame = 03 01 02 07 03 68 65 6c 6c 6f 06 77 6f 72 6c 64 00
// （内部无 0x00，末尾是分隔符）

match @cobs.decode(frame) {
  Ok(data) => assert_eq(data, payload) // 还原成功
  Err(TruncatedFrame) => ...           // 帧在分隔符之前结束
  Err(TrailingData) => ...             // 分隔符之后还有多余字节
}
```

流式解码（逐字节喂入，凑满一帧返回载荷）：

```moonbit nocheck
let dec = @cobs.Decoder::new()
for byte in wire {
  match dec.push(byte) {
    Some(data) => handle(data) // 0x00 分隔符到达，一帧完成
    None => ()
  }
}
```

一次喂入整个缓冲区、取出其中所有完整帧：

```moonbit nocheck
///|
let frames : Array[Bytes] = @cobs.Decoder::new().feed(buffer)
```

## 语义细节

- `encode` 输出总是以 `0x00` 结尾；编码空载荷得到 `[0x01, 0x00]`。
- 块最大长度为 254 字节；写满 254 字节的块以 `0xFF` 关闭（按长度关闭，
  不吸收零字节），随后若载荷继续，会开启新块。
- `decode` 是**严格**模式：`0x00` 分隔符必须是输入的最后一个字节，
  任何截断（`TruncatedFrame`）或分隔符后的多余数据（`TrailingData`）都会报错。
- `Decoder` 是**宽容**模式：`0x00` 永远作为当前帧的边界，因此损坏的码字会在
  下一个分隔符处自动重新同步（中途到达的分隔符会产出部分帧而不是报错）。
  需要严格校验时请使用 `decode`。
- `Decoder::finish` 用于流结束检查：所有字节都已作为帧交付时返回 `Ok(())`，
  否则返回 `Err(TruncatedFrame)`。

## API 一览

| 函数 | 说明 |
| --- | --- |
| `max_encoded_len(n) -> Int` | `n` 字节载荷的编码长度上界（含分隔符） |
| `encode(Bytes) -> Bytes` | 编码为完整帧（含末尾 `0x00` 分隔符） |
| `decode(Bytes) -> Result[Bytes, DecodeError]` | 严格解码一帧 |
| `Decoder::new() / push / feed / finish` | 流式增量解码 |

## 开发

```bash
moon test           # 运行测试
moon fmt            # 格式化
moon info           # 更新 .mbti 接口
moon run cmd/main   # 运行演示
```
