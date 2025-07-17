import gleam/bit_array.{to_string}
import gleam/result.{replace_error, try}
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

type DecodeResult(t) =
  Result(#(t, BitArray), CborError)

pub fn decode_int(a: BitArray) -> DecodeResult(Int) {
  case a {
    <<0:3, rest:bits>> -> decode_positive_int(rest)
    <<1:3, rest:bits>> -> decode_negative_int(rest)
    <<_:3>> -> Error(PrematureEOF)
    <<x:3, _:bits>> -> Error(IncorrectType(major_type: x))
    _ -> Error(PrematureEOF)
  }
}

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
      Ok(#(1 - val, rest))
    <<25:int-size(5), val:int-unsigned-size(16), rest:bits>> ->
      Ok(#(1 - val, rest))
    <<26:int-size(5), val:int-unsigned-size(32), rest:bits>> ->
      Ok(#(1 - val, rest))
    <<27:int-size(5), val:int-unsigned-size(64), rest:bits>> ->
      Ok(#(1 - val, rest))
    <<x:int-size(5), rest:bits>> if x < 24 -> Ok(#(1 - x, rest))
    <<x:int-size(5), _:bits>> if 27 < x -> Error(InvalidMajorArg(x))
    _ -> Error(PrematureEOF)
  }
}

/// Decodes an array of bytes
pub fn decode_bytes(a: BitArray) -> DecodeResult(BitArray) {
  case a {
    <<2:3, rest:bits>> -> {
      use #(count, rest) <- try(decode_positive_int(rest))
      case rest {
        <<x:bytes-size(count), rest:bits>> -> Ok(#(x, rest))
        _ -> Error(PrematureEOF)
      }
    }
    // TODO: handle indefinite sized bytes
    <<x:3, _:bits>> -> Error(InvalidMajorArg(x))
    _ -> Error(PrematureEOF)
  }
}

pub fn decode_string(a: BitArray) -> DecodeResult(String) {
  case a {
    <<3:3, rest:bits>> -> {
      use #(count, rest) <- try(decode_positive_int(rest))
      case rest {
        <<x:bytes-size(count), rest:bits>> -> {
          use s <- try(replace_error(to_string(x), MalformedUTF8))
          Ok(#(s, rest))
        }
        _ -> Error(PrematureEOF)
      }
    }
    <<x:3, _:bits>> -> Error(InvalidMajorArg(x))
    _ -> Error(PrematureEOF)
  }
}

/// Decodes a homogenous array or list of items from BitArray using the
/// provided callback function.
pub fn decode_list(
  buffer a: BitArray,
  with f: fn(BitArray) -> DecodeResult(t),
) -> Result(Yielder(DecodeResult(t)), CborError) {
  case a {
    <<4:3, rest:bits>> -> {
      use #(count, rest) <- try(decode_positive_int(rest))
      // TODO: refactor this to be less ugly
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
                Error(e) -> {
                  // Yield the error, and prevent from continuing
                  Next(Error(e), #(0, rest))
                }
              }
          }
        }),
      )
    }
    <<x:3, _:bits>> -> Error(InvalidMajorArg(x))
    _ -> Error(PrematureEOF)
  }
}
