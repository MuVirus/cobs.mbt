///|
/// Renders bytes as a lowercase hex string for demo output.
fn to_hex(bs : Bytes) -> String {
  let digits = [
    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f",
  ]
  let mut s = ""
  for i in 0..<bs.length() {
    let n = bs[i].to_int()
    s = s + digits[(n >> 4) & 0xF] + digits[n & 0xF]
  }
  s
}

///|
/// Entry point for the CLI or runnable program in this template.
/// Keep main focused; move logic into the library package.
/// Run with `moon run cmd/main` from the project root.
fn main {
  let payload = b"\x01\x02\x00\x03hello\x00world"
  let frame = @lib.encode(payload)
  println("payload : \{to_hex(payload)}")
  println("frame   : \{to_hex(frame)}")
  match @lib.decode(frame) {
    Ok(decoded) =>
      println("decoded : \{to_hex(decoded)}  roundtrip: \{decoded == payload}")
    Err(err) => println("decode error: \{err}")
  }
  // the same frame, streamed through the incremental decoder
  let dec = @lib.Decoder::new()
  for i in 0..<frame.length() {
    match dec.push(frame[i]) {
      Some(decoded) =>
        println(
          "streamed: \{to_hex(decoded)}  roundtrip: \{decoded == payload}",
        )
      None => ()
    }
  }
  match dec.finish() {
    Ok(_) => println("stream  : complete")
    Err(err) => println("stream  : incomplete frame: \{err}")
  }
}
