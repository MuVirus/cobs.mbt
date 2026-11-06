// Whitebox tests run within the package scope.
// Use them to validate internal helpers or invariants.
// Keep them focused; public behavior belongs in `_test.mbt`.

///|
test "Decoder starts idle" {
  let dec = Decoder::new()
  assert_eq(dec.remaining, -1)
  assert_true(dec.buf.is_empty())
  assert_true(!dec.pending_zero)
  assert_true(!dec.unterminated)
}

///|
test "Decoder defers the implicit zero to the next code byte" {
  let dec = Decoder::new()
  assert_true(dec.push(b'\x02') is None)
  assert_eq(dec.remaining, 1)
  assert_true(!dec.unterminated)
  // the block closed on this byte; its terminating zero is not emitted yet
  assert_true(dec.push(b'\x41') is None)
  assert_eq(dec.remaining, -1)
  assert_true(dec.pending_zero)
  assert_true(dec.buf == [b'\x41'])
  // the next code byte materializes the deferred zero as payload
  assert_true(dec.push(b'\x01') is None)
  assert_true(dec.buf == [b'\x41', b'\x00'])
  // and the empty block defers its own zero, which the delimiter drops
  assert_eq(dec.push(b'\x00'), Some(b"\x41\x00"))
  assert_true(dec.buf.is_empty())
  assert_true(!dec.pending_zero)
}

///|
test "0xFF block carries no implicit zero" {
  let dec = Decoder::new()
  assert_true(dec.push(b'\xff') is None)
  assert_eq(dec.remaining, 254)
  assert_true(dec.unterminated)
  for _i in 0..<254 {
    assert_true(dec.push(b'\x7f') is None)
  }
  // closed by length: no deferred zero
  assert_eq(dec.remaining, -1)
  assert_true(!dec.pending_zero)
  assert_eq(dec.buf.length(), 254)
  assert_eq(dec.finish(), Err(TruncatedFrame))
}

///|
test "delimiter mid-block resets without leftover state" {
  let dec = Decoder::new()
  assert_true(dec.push(b'\x03') is None)
  assert_true(dec.push(b'\x41') is None)
  // remaining == 1 here: the delimiter arrives mid-block
  assert_eq(dec.remaining, 1)
  assert_eq(dec.push(b'\x00'), Some(b"\x41"))
  assert_eq(dec.remaining, -1)
  assert_true(dec.buf.is_empty())
  assert_eq(dec.finish(), Ok(()))
}
