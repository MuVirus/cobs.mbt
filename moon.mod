// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "MuVirus/cobs"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/MuVirus/cobs.mbt"

license = "Apache-2.0"

keywords = [ "cobs", "encoding", "serial", "framing" ]

preferred_target = "wasm"

description = "COBS (Consistent Overhead Byte Stuffing) codec in pure MoonBit"
