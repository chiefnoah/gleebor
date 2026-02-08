# GleeBOR

### A CBOR ([RFC 8949](https://www.rfc-editor.org/rfc/rfc8949.html)) Library for Gleam

[![Package Version](https://img.shields.io/hexpm/v/gleebor)](https://hex.pm/packages/gleebor)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/gleebor/)

CBOR is a self-describing standardized data format used for data interchange. It's
efficient, generally pretty fast, and best of all: has high quality implementations in
many languages. This libraries goal is to add to the list of languages that have strong
CBOR support!

> [!WARNING]
> The `BitArray` syntax used throughout this library is currently unsupported by
> the JavaScript backend. Until this is fixed upstream, this library is only expected to
> work for BEAM backed applications.


```sh
gleam add gleebor
```
```gleam
import gleebor
import io

fn read_my_bytes() {
  // 0 major arg, 24 to signal the following byte is the payload value, 123 is an 8-bit
  //number
  <<0:3, 24:5, 123:8>>
}

pub fn main() {
  // Get your bytes somehow!
  let bytes = read_my_bytes()

  let assert Ok(number) = gleebor.decode_int(bytes)
  io.debug(number) // => 123
}
```

Further documentation can be found at <https://hexdocs.pm/gleebor>.

## Development

```sh
gleam test  # Run the tests
gleam shell # Run an Erlang shell
```

## Status

The following describes the current status for this library's progress.


- [x] Decode
  - [x] Ints
  - [x] Floats
  - [x] Text Strings (Sized)
  - [x] Bytes (sized)
  - [x] Arrays (sized)
  - [x] Maps
  - [x] Tags
  - [x] Indefinite sequences
- [x] Encode
  - [x] Ints
  - [x] Floats
  - [x] Text Strings (Sized)
  - [x] Bytes (sized)
  - [x] Arrays (sized)
  - [x] Maps
  - [x] Tags
  - [x] Indefinite sequences


