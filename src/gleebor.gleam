import gleam/bit_array.{to_string}
import gleam/int
import gleam/list
import gleam/result.{replace_error, try}
import gleam/string
import gleam/yielder.{type Step, type Yielder, Done, Next}

pub type CborError {
  /// Indicates the input ended prematurely and decoding could not continue.
  PrematureEOF
  /// This indicates that the major type in the payload was one that is not
  /// valid according to the CBOR specification. See RFC 8949 section 3.
  InvalidMajorArg(Int)
  /// Indicates the type decoded did not match the expected type.
  IncorrectType(
    /// the major_type is the CBOR Section 3.1 Major Types indicator.
    major_type: Int,
  )
  MalformedUTF8
}

pub type DecodeResult(t) =
  Result(#(t, BitArray), CborError)

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

fn decode_positive_int(a: BitArray) -> DecodeResult(Int) {
  case a {
    <<24:int-size(5), val:int-unsigned-size(8), rest:bits>> -> Ok(#(val, rest))
    <<25:int-size(5), val:int-unsigned-size(16), rest:bits>> -> Ok(#(val, rest))
    <<26:int-size(5), val:int-unsigned-size(32), rest:bits>> -> Ok(#(val, rest))
    <<27:int-size(5), val:int-unsigned-size(64), rest:bits>> -> Ok(#(val, rest))
    <<x:int-size(5), _:bits>> if 27 < x -> Error(InvalidMajorArg(x))
    <<x:int-size(5), rest:bits>> if x < 24 -> Ok(#(x, rest))
    _ -> Error(PrematureEOF)
  }
}

fn decode_negative_int(a: BitArray) -> DecodeResult(Int) {
  case a {
    <<24:int-size(5), val:int-unsigned-size(8), rest:bits>> ->
      Ok(#(-1 - val, rest))
    <<25:int-size(5), val:int-unsigned-size(16), rest:bits>> ->
      Ok(#(-1 - val, rest))
    <<26:int-size(5), val:int-unsigned-size(32), rest:bits>> ->
      Ok(#(-1 - val, rest))
    <<27:int-size(5), val:int-unsigned-size(64), rest:bits>> ->
      Ok(#(-1 - val, rest))
    <<x:int-size(5), rest:bits>> if x < 24 -> Ok(#(-1 - x, rest))
    <<x:int-size(5), _:bits>> if 27 < x -> Error(InvalidMajorArg(x))
    _ -> Error(PrematureEOF)
  }
}

fn decode_definite_bytes(rest: BitArray) -> DecodeResult(BitArray) {
  use #(count, rest) <- try(decode_positive_int(rest))
  case rest {
    <<x:bytes-size(count), rest:bits>> -> Ok(#(x, rest))
    _ -> Error(PrematureEOF)
  }
}

fn decode_definite_string(rest: BitArray) -> DecodeResult(String) {
  use #(count, rest) <- try(decode_positive_int(rest))
  case rest {
    <<x:bytes-size(count), rest:bits>> -> {
      use s <- try(replace_error(to_string(x), MalformedUTF8))
      Ok(#(s, rest))
    }
    _ -> Error(PrematureEOF)
  }
}

fn decode_indefinite_bytes_chunks(
  a: BitArray,
  acc: BitArray,
) -> DecodeResult(BitArray) {
  case a {
    <<0xff, rest:bits>> -> Ok(#(acc, rest))
    <<2:3, rest:bits>> -> {
      use #(chunk, rest) <- try(decode_definite_bytes(rest))
      decode_indefinite_bytes_chunks(rest, <<acc:bits, chunk:bits>>)
    }
    <<_:3, _:bits>> -> Error(IncorrectType(major_type: 2))
    _ -> Error(PrematureEOF)
  }
}

fn decode_indefinite_string_chunks(
  a: BitArray,
  acc: String,
) -> DecodeResult(String) {
  case a {
    <<0xff, rest:bits>> -> Ok(#(acc, rest))
    <<3:3, rest:bits>> -> {
      use #(chunk, rest) <- try(decode_definite_string(rest))
      decode_indefinite_string_chunks(rest, string.append(acc, chunk))
    }
    <<_:3, _:bits>> -> Error(IncorrectType(major_type: 3))
    _ -> Error(PrematureEOF)
  }
}

fn decode_indefinite_list_yielder(
  a: BitArray,
  f: fn(BitArray) -> DecodeResult(t),
) -> Yielder(DecodeResult(t)) {
  yielder.unfold(#(True, a), fn(state: #(Bool, BitArray)) -> Step(
    DecodeResult(t),
    #(Bool, BitArray),
  ) {
    case state {
      #(False, _) -> Done
      #(True, <<0xff, _rest:bits>>) -> Done
      #(True, rest) ->
        case f(rest) {
          Ok(#(result, rest)) ->
            Next(Ok(#(result, rest)), #(True, rest))
          Error(e) -> Next(Error(e), #(False, rest))
        }
    }
  })
}

fn decode_indefinite_map_yielder(
  a: BitArray,
  key_decoder: fn(BitArray) -> DecodeResult(k),
  value_decoder: fn(BitArray) -> DecodeResult(v),
) -> Yielder(DecodeResult(#(k, v))) {
  yielder.unfold(#(True, a), fn(state: #(Bool, BitArray)) -> Step(
    DecodeResult(#(k, v)),
    #(Bool, BitArray),
  ) {
    case state {
      #(False, _) -> Done
      #(True, <<0xff, _rest:bits>>) -> Done
      #(True, rest) -> {
        let pair = {
          use #(key, rest) <- try(key_decoder(rest))
          use #(value, rest) <- try(value_decoder(rest))
          Ok(#(#(key, value), rest))
        }
        case pair {
          Ok(#(kv, rest)) -> Next(Ok(#(kv, rest)), #(True, rest))
          Error(e) -> Next(Error(e), #(False, rest))
        }
      }
    }
  })
}

/// Converts a half-precision (IEEE 754 float16) value to a Float.
fn float16_to_float(
  sign: Int,
  exponent: Int,
  mantissa: Int,
) -> Float {
  case exponent {
    0 -> {
      // Zero or subnormal: value = (-1)^sign * 2^(-24) * mantissa
      let s = case sign {
        1 -> -1.0
        _ -> 1.0
      }
      s *. int.to_float(mantissa) /. 16_777_216.0
    }
    31 -> {
      // Infinity or NaN — reconstruct as float64 bits
      let mant64 = int.bitwise_shift_left(mantissa, 42)
      let assert <<f:float-size(64)>> =
        <<sign:size(1), 2047:size(11), mant64:size(52)>>
      f
    }
    _ -> {
      // Normal: reconstruct as float64 bits
      let exp64 = exponent - 15 + 1023
      let mant64 = int.bitwise_shift_left(mantissa, 42)
      let assert <<f:float-size(64)>> =
        <<sign:size(1), exp64:size(11), mant64:size(52)>>
      f
    }
  }
}

/// Encodes a CBOR header: major type (3 bits) + additional info for the value.
fn encode_header(major_type: Int, value: Int) -> BitArray {
  case value {
    v if v < 0 -> <<>>
    v if v < 24 -> <<major_type:3, v:5>>
    v if v < 256 -> <<major_type:3, 24:5, v:8>>
    v if v < 65_536 -> <<major_type:3, 25:5, v:16>>
    v if v < 4_294_967_296 -> <<major_type:3, 26:5, v:32>>
    v -> <<major_type:3, 27:5, v:64>>
  }
}

// ---------------------------------------------------------------------------
// Decode – Integers (major types 0 & 1)
// ---------------------------------------------------------------------------

pub fn decode_int(a: BitArray) -> DecodeResult(Int) {
  case a {
    <<0:3, rest:bits>> -> decode_positive_int(rest)
    <<1:3, rest:bits>> -> decode_negative_int(rest)
    <<_:3>> -> Error(PrematureEOF)
    <<x:3, _:bits>> -> Error(IncorrectType(major_type: x))
    _ -> Error(PrematureEOF)
  }
}

// ---------------------------------------------------------------------------
// Decode – Byte strings (major type 2)
// ---------------------------------------------------------------------------

/// Decodes a byte string (definite or indefinite length).
pub fn decode_bytes(a: BitArray) -> DecodeResult(BitArray) {
  case a {
    <<2:3, 31:int-size(5), rest:bits>> ->
      decode_indefinite_bytes_chunks(rest, <<>>)
    <<2:3, rest:bits>> -> decode_definite_bytes(rest)
    <<x:3, _:bits>> -> Error(IncorrectType(major_type: x))
    _ -> Error(PrematureEOF)
  }
}

// ---------------------------------------------------------------------------
// Decode – Text strings (major type 3)
// ---------------------------------------------------------------------------

/// Decodes a UTF-8 text string (definite or indefinite length).
pub fn decode_string(a: BitArray) -> DecodeResult(String) {
  case a {
    <<3:3, 31:int-size(5), rest:bits>> ->
      decode_indefinite_string_chunks(rest, "")
    <<3:3, rest:bits>> -> decode_definite_string(rest)
    <<x:3, _:bits>> -> Error(IncorrectType(major_type: x))
    _ -> Error(PrematureEOF)
  }
}

// ---------------------------------------------------------------------------
// Decode – Arrays (major type 4)
// ---------------------------------------------------------------------------

/// Decodes an array of items from a BitArray using the provided callback.
/// Supports both definite and indefinite length arrays.
pub fn decode_list(
  buffer a: BitArray,
  with f: fn(BitArray) -> DecodeResult(t),
) -> Result(Yielder(DecodeResult(t)), CborError) {
  case a {
    <<4:3, 31:int-size(5), rest:bits>> ->
      Ok(decode_indefinite_list_yielder(rest, f))
    <<4:3, rest:bits>> -> {
      use #(count, rest) <- try(decode_positive_int(rest))
      Ok(
        yielder.unfold(#(count, rest), fn(n: #(Int, BitArray)) -> Step(
          DecodeResult(t),
          #(Int, BitArray),
        ) {
          case n {
            #(0, _) -> Done
            #(remaining, rest) ->
              case f(rest) {
                Ok(#(result, rest)) ->
                  Next(Ok(#(result, rest)), #(remaining - 1, rest))
                Error(e) -> Next(Error(e), #(0, rest))
              }
          }
        }),
      )
    }
    <<x:3, _:bits>> -> Error(IncorrectType(major_type: x))
    _ -> Error(PrematureEOF)
  }
}

// ---------------------------------------------------------------------------
// Decode – Maps (major type 5)
// ---------------------------------------------------------------------------

/// Decodes a CBOR map. Returns a yielder of decoded key-value pairs.
/// Supports both definite and indefinite length maps.
pub fn decode_map(
  buffer a: BitArray,
  keys key_decoder: fn(BitArray) -> DecodeResult(k),
  values value_decoder: fn(BitArray) -> DecodeResult(v),
) -> Result(Yielder(DecodeResult(#(k, v))), CborError) {
  case a {
    <<5:3, 31:int-size(5), rest:bits>> ->
      Ok(decode_indefinite_map_yielder(rest, key_decoder, value_decoder))
    <<5:3, rest:bits>> -> {
      use #(count, rest) <- try(decode_positive_int(rest))
      Ok(
        yielder.unfold(#(count, rest), fn(n: #(Int, BitArray)) -> Step(
          DecodeResult(#(k, v)),
          #(Int, BitArray),
        ) {
          case n {
            #(0, _) -> Done
            #(remaining, rest) -> {
              let pair = {
                use #(key, rest) <- try(key_decoder(rest))
                use #(value, rest) <- try(value_decoder(rest))
                Ok(#(#(key, value), rest))
              }
              case pair {
                Ok(#(kv, rest)) ->
                  Next(Ok(#(kv, rest)), #(remaining - 1, rest))
                Error(e) -> Next(Error(e), #(0, rest))
              }
            }
          }
        }),
      )
    }
    <<x:3, _:bits>> -> Error(IncorrectType(major_type: x))
    _ -> Error(PrematureEOF)
  }
}

// ---------------------------------------------------------------------------
// Decode – Tags (major type 6)
// ---------------------------------------------------------------------------

/// Decodes a CBOR tag number. The tagged data item remains in the returned
/// rest bytes and should be decoded separately by the caller.
pub fn decode_tag(a: BitArray) -> DecodeResult(Int) {
  case a {
    <<6:3, rest:bits>> -> decode_positive_int(rest)
    <<x:3, _:bits>> -> Error(IncorrectType(major_type: x))
    _ -> Error(PrematureEOF)
  }
}

// ---------------------------------------------------------------------------
// Decode – Floats & simple values (major type 7)
// ---------------------------------------------------------------------------

/// Decodes a CBOR float (half, single, or double precision).
pub fn decode_float(a: BitArray) -> DecodeResult(Float) {
  case a {
    <<7:3, 25:int-size(5), s:int-size(1), e:int-size(5), m:int-size(10), rest:bits>>
    -> Ok(#(float16_to_float(s, e, m), rest))
    <<7:3, 26:int-size(5), val:float-size(32), rest:bits>> ->
      Ok(#(val, rest))
    <<7:3, 27:int-size(5), val:float-size(64), rest:bits>> ->
      Ok(#(val, rest))
    <<7:3, x:int-size(5), _:bits>> if x >= 25 -> Error(PrematureEOF)
    <<7:3, _:int-size(5), _:bits>> -> Error(IncorrectType(major_type: 7))
    <<x:3, _:bits>> -> Error(IncorrectType(major_type: x))
    _ -> Error(PrematureEOF)
  }
}

/// Decodes a CBOR boolean (simple value 20 = false, 21 = true).
pub fn decode_bool(a: BitArray) -> DecodeResult(Bool) {
  case a {
    <<7:3, 20:int-size(5), rest:bits>> -> Ok(#(False, rest))
    <<7:3, 21:int-size(5), rest:bits>> -> Ok(#(True, rest))
    <<7:3, _:int-size(5), _:bits>> -> Error(IncorrectType(major_type: 7))
    <<x:3, _:bits>> -> Error(IncorrectType(major_type: x))
    _ -> Error(PrematureEOF)
  }
}

/// Decodes a CBOR null (simple value 22).
pub fn decode_null(a: BitArray) -> DecodeResult(Nil) {
  case a {
    <<7:3, 22:int-size(5), rest:bits>> -> Ok(#(Nil, rest))
    <<7:3, _:int-size(5), _:bits>> -> Error(IncorrectType(major_type: 7))
    <<x:3, _:bits>> -> Error(IncorrectType(major_type: x))
    _ -> Error(PrematureEOF)
  }
}

/// Decodes a CBOR undefined (simple value 23).
pub fn decode_undefined(a: BitArray) -> DecodeResult(Nil) {
  case a {
    <<7:3, 23:int-size(5), rest:bits>> -> Ok(#(Nil, rest))
    <<7:3, _:int-size(5), _:bits>> -> Error(IncorrectType(major_type: 7))
    <<x:3, _:bits>> -> Error(IncorrectType(major_type: x))
    _ -> Error(PrematureEOF)
  }
}

// ---------------------------------------------------------------------------
// Encode – Integers
// ---------------------------------------------------------------------------

/// Encodes an integer as CBOR (major type 0 for positive, 1 for negative).
pub fn encode_int(n: Int) -> BitArray {
  case n >= 0 {
    True -> encode_header(0, n)
    False -> encode_header(1, -1 - n)
  }
}

// ---------------------------------------------------------------------------
// Encode – Byte strings
// ---------------------------------------------------------------------------

/// Encodes a byte string as CBOR (major type 2).
pub fn encode_bytes(b: BitArray) -> BitArray {
  let header = encode_header(2, bit_array.byte_size(b))
  <<header:bits, b:bits>>
}

// ---------------------------------------------------------------------------
// Encode – Text strings
// ---------------------------------------------------------------------------

/// Encodes a UTF-8 string as CBOR (major type 3).
pub fn encode_string(s: String) -> BitArray {
  let b = bit_array.from_string(s)
  let header = encode_header(3, bit_array.byte_size(b))
  <<header:bits, b:bits>>
}

// ---------------------------------------------------------------------------
// Encode – Arrays
// ---------------------------------------------------------------------------

/// Encodes a list of items as a CBOR array (major type 4).
pub fn encode_list(
  items: List(a),
  with encoder: fn(a) -> BitArray,
) -> BitArray {
  let header = encode_header(4, list.length(items))
  let body = bit_array.concat(list.map(items, encoder))
  <<header:bits, body:bits>>
}

// ---------------------------------------------------------------------------
// Encode – Maps
// ---------------------------------------------------------------------------

/// Encodes a list of key-value pairs as a CBOR map (major type 5).
pub fn encode_map(
  entries: List(#(k, v)),
  keys key_encoder: fn(k) -> BitArray,
  values value_encoder: fn(v) -> BitArray,
) -> BitArray {
  let header = encode_header(5, list.length(entries))
  let body =
    bit_array.concat(
      list.flat_map(entries, fn(entry) {
        let #(k, v) = entry
        [key_encoder(k), value_encoder(v)]
      }),
    )
  <<header:bits, body:bits>>
}

// ---------------------------------------------------------------------------
// Encode – Tags
// ---------------------------------------------------------------------------

/// Encodes a CBOR tag header (major type 6). The tagged data item should be
/// appended by the caller.
pub fn encode_tag(tag: Int) -> BitArray {
  encode_header(6, tag)
}

// ---------------------------------------------------------------------------
// Encode – Floats & simple values
// ---------------------------------------------------------------------------

/// Encodes a float as CBOR double-precision (major type 7, additional info 27).
pub fn encode_float(f: Float) -> BitArray {
  <<7:3, 27:5, f:float-size(64)>>
}

/// Encodes a boolean as CBOR (simple value 20 or 21).
pub fn encode_bool(b: Bool) -> BitArray {
  case b {
    False -> <<7:3, 20:5>>
    True -> <<7:3, 21:5>>
  }
}

/// Encodes CBOR null (simple value 22).
pub fn encode_null() -> BitArray {
  <<7:3, 22:5>>
}

/// Encodes CBOR undefined (simple value 23).
pub fn encode_undefined() -> BitArray {
  <<7:3, 23:5>>
}

// ---------------------------------------------------------------------------
// Encode – Indefinite sequences
// ---------------------------------------------------------------------------

/// Encodes a list of byte-string chunks as an indefinite-length byte string.
pub fn encode_indefinite_bytes(chunks: List(BitArray)) -> BitArray {
  let header = <<2:3, 31:5>>
  let body = bit_array.concat(list.map(chunks, encode_bytes))
  <<header:bits, body:bits, 0xff>>
}

/// Encodes a list of string chunks as an indefinite-length text string.
pub fn encode_indefinite_string(chunks: List(String)) -> BitArray {
  let header = <<3:3, 31:5>>
  let body = bit_array.concat(list.map(chunks, encode_string))
  <<header:bits, body:bits, 0xff>>
}

/// Encodes a list of pre-encoded CBOR items as an indefinite-length array.
pub fn encode_indefinite_list(items: List(BitArray)) -> BitArray {
  let header = <<4:3, 31:5>>
  let body = bit_array.concat(items)
  <<header:bits, body:bits, 0xff>>
}

/// Encodes pre-encoded CBOR key-value pairs as an indefinite-length map.
pub fn encode_indefinite_map(
  entries: List(#(BitArray, BitArray)),
) -> BitArray {
  let header = <<5:3, 31:5>>
  let body =
    bit_array.concat(
      list.flat_map(entries, fn(e) {
        let #(k, v) = e
        [k, v]
      }),
    )
  <<header:bits, body:bits, 0xff>>
}
