// Blackbox tests run against the package's public API. Use `@cobs` to import.
// Prefer high-level behaviors over implementation details.
// Run `moon test` to execute and `moon test --update` to refresh snapshots.

///|
/// Builds `n` copies of byte `b` as a `Bytes` value.
fn repeat_byte(n : Int32, b : Byte) -> Bytes {
  let arr : Array[Byte] = []
  for _ in 0..<n {
    arr.push(b)
  }
  Bytes::from_iter(arr.iter())
}

///|
/// Builds `n` position-dependent bytes: `(i * 7 + 1) & 0xFF`, a mix that
/// crosses zero bytes and 254-byte block boundaries at varying offsets.
fn pattern_bytes(n : Int32) -> Bytes {
  let arr : Array[Byte] = []
  for i in 0..<n {
    arr.push(((i * 7 + 1) & 0xFF).to_byte())
  }
  Bytes::from_iter(arr.iter())
}

///|
test "encode/decode known vectors" {
  let vectors : Array[(Bytes, Bytes)] = [
    // empty payload still carries one (empty) block plus the delimiter
    (b"", b"\x01\x00"),
    // a zero byte becomes an empty block
    (b"\x00", b"\x01\x01\x00"),
    (b"\x45", b"\x02\x45\x00"),
    (b"\x45\x00", b"\x02\x45\x01\x00"),
    (b"\x45\x00\x00", b"\x02\x45\x01\x01\x00"),
    (b"\x00\x00\x45", b"\x01\x01\x02\x45\x00"),
    (b"\x45\x00\x45", b"\x02\x45\x02\x45\x00"),
    (b"\x00\x45\x00\x11", b"\x01\x02\x45\x02\x11\x00"),
    (b"\x45\x00\x25\x50\x44\x00", b"\x02\x45\x04\x25\x50\x44\x01\x00"),
  ]
  for (payload, expected) in vectors {
    assert_eq(@cobs.encode(payload), expected)
    assert_eq(@cobs.decode(expected), Ok(payload))
  }
}

///|
test "encode boundaries at 254" {
  // 254 non-zero bytes: one full-length block closed by 0xFF, plus the
  // final code byte of the trailing (empty) block
  let full = repeat_byte(254, b'\x55')
  let enc = @cobs.encode(full)
  assert_eq(enc.length(), 257)
  assert_eq(enc[0], b'\xff')
  assert_eq(enc[255], b'\x01')
  assert_eq(enc[256], b'\x00')
  assert_eq(@cobs.decode(enc), Ok(full))
  // 255 non-zero bytes: a 0xFF block, then a second block closed by the
  // end of the payload
  let over = repeat_byte(255, b'\x55')
  let enc2 = @cobs.encode(over)
  assert_eq(enc2.length(), 258)
  assert_eq(enc2[0], b'\xff')
  assert_eq(enc2[255], b'\x02')
  assert_eq(enc2[256], b'\x55')
  assert_eq(enc2[257], b'\x00')
  assert_eq(@cobs.decode(enc2), Ok(over))
  // a 0xFF block followed by a zero-terminated empty block
  let full_zero = full + b"\x00"
  let enc3 = @cobs.encode(full_zero)
  assert_eq(enc3.length(), 258)
  assert_eq(enc3[0], b'\xff')
  assert_eq(enc3[255], b'\x01')
  assert_eq(enc3[256], b'\x01')
  assert_eq(enc3[257], b'\x00')
  assert_eq(@cobs.decode(enc3), Ok(full_zero))
  // 254 zero bytes: one empty block per zero plus the final block
  let zeros = repeat_byte(254, b'\x00')
  let enc4 = @cobs.encode(zeros)
  assert_eq(enc4.length(), 256)
  assert_eq(@cobs.decode(enc4), Ok(zeros))
}

///|
test "max_encoded_len boundaries" {
  assert_eq(@cobs.max_encoded_len(0), 2)
  assert_eq(@cobs.max_encoded_len(1), 3)
  assert_eq(@cobs.max_encoded_len(253), 255)
  assert_eq(@cobs.max_encoded_len(254), 257)
  assert_eq(@cobs.max_encoded_len(255), 258)
  assert_eq(@cobs.max_encoded_len(508), 512)
  assert_eq(@cobs.max_encoded_len(509), 513)
  assert_eq(@cobs.max_encoded_len(762), 767)
}

///|
test "decode rejects malformed frames" {
  // empty input has no delimiter at all
  assert_eq(@cobs.decode(b""), Err(@cobs.TruncatedFrame))
  // missing delimiter
  assert_eq(@cobs.decode(b"\x02\x45"), Err(@cobs.TruncatedFrame))
  // code word promises more data than the frame holds
  assert_eq(@cobs.decode(b"\x03\x45\x00"), Err(@cobs.TruncatedFrame))
  assert_eq(@cobs.decode(b"\xff\x55\x00"), Err(@cobs.TruncatedFrame))
  // delimiter must be the last byte
  assert_eq(@cobs.decode(b"\x02\x45\x00\x01"), Err(@cobs.TrailingData))
  assert_eq(@cobs.decode(b"\x00\x01"), Err(@cobs.TrailingData))
}

///|
test "DecodeError display" {
  assert_eq(@cobs.TruncatedFrame.to_string(), "TruncatedFrame")
  assert_eq(@cobs.TrailingData.to_string(), "TrailingData")
}

///|
test "decode accepts empty frames" {
  // both encodings of an empty payload
  assert_eq(@cobs.decode(b"\x00"), Ok(b""))
  assert_eq(@cobs.decode(b"\x01\x00"), Ok(b""))
}

///|
test "roundtrip across block boundary lengths" {
  for len in [0, 1, 2, 3, 126, 253, 254, 255, 256, 508, 509, 510, 762, 763] {
    let payload = pattern_bytes(len)
    let frame = @cobs.encode(payload)
    assert_true(frame.length() <= @cobs.max_encoded_len(len))
    // no interior zero bytes inside the frame
    for j in 0..<(frame.length() - 1) {
      assert_true(frame[j] != b'\x00')
    }
    assert_eq(@cobs.decode(frame), Ok(payload))
  }
}

///|
test "roundtrip on pseudo-random payloads" {
  let mut seed = 987654321
  for _round in 0..<32 {
    seed = seed * 1103515245 + 12345
    let len = (seed >> 16) & 0x3FF
    let arr : Array[Byte] = []
    for _i in 0..<len {
      seed = seed * 1103515245 + 12345
      arr.push(((seed >> 16) & 0xFF).to_byte())
    }
    let payload = Bytes::from_iter(arr.iter())
    let frame = @cobs.encode(payload)
    assert_true(frame.length() <= @cobs.max_encoded_len(len))
    assert_eq(@cobs.decode(frame), Ok(payload))
  }
}

///|
test "Decoder reassembles frames byte by byte" {
  let frame = @cobs.encode(b"\x45\x00\x25\x50")
  let dec = @cobs.Decoder::new()
  let mut got : Bytes? = None
  for i in 0..<frame.length() {
    match dec.push(frame[i]) {
      Some(f) => got = Some(f)
      None => ()
    }
  }
  assert_eq(got, Some(b"\x45\x00\x25\x50"))
  assert_eq(dec.finish(), Ok(()))
}

///|
test "Decoder feed extracts every frame in a buffer" {
  let all = @cobs.encode(b"a\x00b") +
    @cobs.encode(b"") +
    @cobs.encode(b"\x00\x00")
  let frames = @cobs.Decoder::new().feed(all)
  assert_eq(frames, [b"a\x00b", b"", b"\x00\x00"])
}

///|
test "Decoder finish reports incomplete frames" {
  // a fresh decoder is idle
  assert_eq(@cobs.Decoder::new().finish(), Ok(()))
  // still collecting a block
  let dec = @cobs.Decoder::new()
  assert_true(dec.push(b'\x03') is None)
  assert_eq(dec.finish(), Err(@cobs.TruncatedFrame))
  // a 0xFF block closed by length still owes its delimiter
  let dec2 = @cobs.Decoder::new()
  assert_true(dec2.push(b'\xff') is None)
  for _i in 0..<254 {
    assert_true(dec2.push(b'\x7f') is None)
  }
  assert_eq(dec2.finish(), Err(@cobs.TruncatedFrame))
  // after a delivered frame the decoder is idle again
  let dec3 = @cobs.Decoder::new()
  let _ = dec3.push(b'\x00')
  assert_eq(dec3.finish(), Ok(()))
}

///|
test "Decoder resynchronizes on delimiter" {
  // a corrupted code word: the delimiter arrives before the promised data,
  // so a partial frame is delivered and the stream resynchronizes
  let frames = @cobs.Decoder::new().feed(b"\x03\x61\x00\x02\x62\x00")
  assert_eq(frames, [b"\x61", b"\x62"])
}
