///|
/// Errors reported by `decode` and `Decoder::finish`.
#derive(Eq, Debug)
pub(all) enum DecodeError {
  /// The input ended inside a frame: the `0x00` delimiter was never reached,
  /// or a code word promised more data bytes than the input contained.
  TruncatedFrame
  /// The frame delimiter was not the last byte of the input.
  TrailingData
}

///|
pub extend DecodeError with Eq::{not_equal, equal}

///|
pub extend DecodeError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub impl Show for DecodeError with fn to_string(self) {
  match self {
    TruncatedFrame => "TruncatedFrame"
    TrailingData => "TrailingData"
  }
}

///|
pub extend DecodeError with Show::{to_string, output}

///|
/// Upper bound of the encoded length for a payload of `n` bytes, including
/// the trailing `0x00` delimiter produced by `encode`: the payload bytes
/// themselves, at most one code byte per 254 payload bytes, a final code
/// byte for the last block, and the delimiter.
pub fn max_encoded_len(n : Int32) -> Int32 {
  if n <= 0 {
    2
  } else {
    n + n / 254 + 2
  }
}

///|
/// Encodes `payload` into a complete COBS frame: a byte sequence guaranteed
/// to contain no interior `0x00`, followed by a single `0x00` delimiter that
/// marks the end of the frame on a wire. The result is at most
/// `max_encoded_len(payload.length())` bytes long; encoding an empty payload
/// yields `[0x01, 0x00]`.
pub fn encode(payload : Bytes) -> Bytes {
  let out : Array[Byte] = []
  let mut code = 1 // value of the code byte currently being filled in
  let mut code_idx = 0 // index of that code byte inside `out`
  out.push(b'\x01') // placeholder; replaced when the block closes
  for i in 0..<payload.length() {
    let b = payload[i]
    if b == b'\x00' {
      // the zero byte is replaced by the next block's code byte
      out[code_idx] = code.to_byte()
      code_idx = out.length()
      out.push(b'\x01')
      code = 1
    } else {
      out.push(b)
      code += 1
      if code == 255 {
        // the block reached its maximum of 254 data bytes and is closed
        // by length (0xFF) instead of by a zero
        out[code_idx] = b'\xff'
        code_idx = out.length()
        out.push(b'\x01')
        code = 1
      }
    }
  }
  out[code_idx] = code.to_byte()
  out.push(b'\x00') // frame delimiter
  Bytes::from_iter(out.iter())
}

///|
/// Strictly decodes one complete COBS frame: the `0x00` delimiter must be
/// the final byte of `frame`. Use `Decoder` to pull frames out of a larger
/// byte stream instead. Returns the original payload on success.
pub fn decode(frame : Bytes) -> Result[Bytes, DecodeError] {
  let out : Array[Byte] = []
  let n = frame.length()
  let mut i = 0
  while i < n {
    let code = frame[i].to_int()
    i += 1
    if code == 0 {
      // delimiter: only valid as the very last byte
      if i == n {
        return Ok(Bytes::from_iter(out.iter()))
      }
      return Err(TrailingData)
    }
    // the block carries (code - 1) data bytes and must be followed by at
    // least the delimiter
    if i + code - 1 >= n {
      return Err(TruncatedFrame)
    }
    for _ in 0..<(code - 1) {
      out.push(frame[i])
      i += 1
    }
    // a block closed by a zero has that zero absorbed by the next code
    // byte, so restore it, unless this block was closed by length (0xFF)
    // or is followed directly by the delimiter
    if code != 0xFF && frame[i] != b'\x00' {
      out.push(b'\x00')
    }
  }
  Err(TruncatedFrame)
}

///|
/// A streaming COBS decoder for wire bytes that arrive one at a time. Feed
/// every byte to `push`; when a `0x00` delimiter arrives, the payload
/// accumulated so far is returned.
///
/// The delimiter is always treated as the end of the current frame, so a
/// corrupted stream resynchronizes at the next delimiter: a delimiter that
/// arrives in the middle of a code word yields a partial frame instead of an
/// error. Use `decode` when you need strict validation of a whole frame.
pub(all) struct Decoder {
  // payload bytes accumulated for the frame in progress
  priv mut buf : Array[Byte]
  // data bytes still expected in the current block; -1 means "expecting a code byte"
  priv mut remaining : Int32
  // an implicit zero is deferred until the next code byte arrives
  priv mut pending_zero : Bool
  // the current block was opened by a 0xFF code (closed by length, not by a zero)
  priv mut unterminated : Bool
}

///|
/// Creates a decoder that expects the first byte of a frame.
pub fn Decoder::new() -> Decoder {
  { buf: [], remaining: -1, pending_zero: false, unterminated: false, }
}

///|
/// Feeds a single wire byte into the decoder. Returns `Some(payload)` when
/// the byte was the `0x00` delimiter that completed a frame, `None`
/// otherwise.
pub fn Decoder::push(self : Decoder, byte : Byte) -> Bytes? {
  if byte == b'\x00' {
    // delimiter: always terminates the current frame. A pending implicit
    // zero was consumed by the delimiter rather than kept as payload.
    let frame = Bytes::from_iter(self.buf.iter())
    self.buf = []
    self.remaining = -1
    self.pending_zero = false
    self.unterminated = false
    return Some(frame)
  }
  if self.remaining < 0 {
    // the zero absorbed between two blocks reappears in front of the next
    // block's code byte
    if self.pending_zero {
      self.buf.push(b'\x00')
      self.pending_zero = false
    }
    // a code byte opens a block of (code - 1) data bytes
    let code = byte.to_int()
    self.remaining = code - 1
    self.unterminated = code == 0xFF
    if self.remaining == 0 {
      // an empty block (code byte 0x01) closes immediately
      self.pending_zero = !self.unterminated
      self.remaining = -1
    }
  } else {
    self.buf.push(byte)
    self.remaining -= 1
    if self.remaining == 0 {
      // the block closed; unless it was closed by length (0xFF), the zero
      // that terminated it reappears in front of the next block
      self.pending_zero = !self.unterminated
      self.remaining = -1
    }
  }
  None
}

///|
/// Feeds a whole buffer and collects every frame it completes, in order.
pub fn Decoder::feed(self : Decoder, data : Bytes) -> Array[Bytes] {
  let frames : Array[Bytes] = []
  for i in 0..<data.length() {
    match self.push(data[i]) {
      Some(frame) => frames.push(frame)
      None => ()
    }
  }
  frames
}

///|
/// Checks that the fed byte stream ended on a frame boundary: returns
/// `Ok(())` when every byte fed so far has been delivered as a frame, and
/// `Err(TruncatedFrame)` when a frame was still in progress.
pub fn Decoder::finish(self : Decoder) -> Result[Unit, DecodeError] {
  if self.remaining < 0 && !self.pending_zero && self.buf.is_empty() {
    Ok(())
  } else {
    Err(TruncatedFrame)
  }
}
