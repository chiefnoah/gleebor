import gleam/yielder
import gleebor

// ---------------------------------------------------------------------------
// Decode – Floats
// ---------------------------------------------------------------------------

pub fn decode_float64_test() {
  let data = <<7:3, 27:5, 1.5:float-size(64)>>
  assert gleebor.decode_float(data) == Ok(#(1.5, <<>>))
}

pub fn decode_float64_negative_test() {
  let data = <<7:3, 27:5, -4.1:float-size(64)>>
  assert gleebor.decode_float(data) == Ok(#(-4.1, <<>>))
}

pub fn decode_float32_test() {
  let data = <<7:3, 26:5, 1.5:float-size(32)>>
  assert gleebor.decode_float(data) == Ok(#(1.5, <<>>))
}

pub fn decode_float32_zero_test() {
  let data = <<7:3, 26:5, 0.0:float-size(32)>>
  assert gleebor.decode_float(data) == Ok(#(0.0, <<>>))
}

pub fn decode_float16_one_test() {
  // float16 1.0 = sign 0, exponent 15 (0b01111), mantissa 0
  let data = <<7:3, 25:5, 0:1, 15:5, 0:10>>
  assert gleebor.decode_float(data) == Ok(#(1.0, <<>>))
}

pub fn decode_float16_one_point_five_test() {
  // float16 1.5 = sign 0, exponent 15, mantissa 512 (0b1000000000)
  let data = <<7:3, 25:5, 0:1, 15:5, 512:10>>
  assert gleebor.decode_float(data) == Ok(#(1.5, <<>>))
}

pub fn decode_float16_negative_test() {
  // float16 -2.0 = sign 1, exponent 16, mantissa 0
  let data = <<7:3, 25:5, 1:1, 16:5, 0:10>>
  assert gleebor.decode_float(data) == Ok(#(-2.0, <<>>))
}

pub fn decode_float16_zero_test() {
  let data = <<7:3, 25:5, 0:1, 0:5, 0:10>>
  assert gleebor.decode_float(data) == Ok(#(0.0, <<>>))
}

pub fn decode_float_wrong_type_test() {
  // Major type 0 (int), not 7
  assert gleebor.decode_float(<<0:3, 5:5>>)
    == Error(gleebor.IncorrectType(major_type: 0))
}

pub fn decode_float_premature_eof_test() {
  // float64 marker but not enough data
  assert gleebor.decode_float(<<7:3, 27:5, 0:32>>)
    == Error(gleebor.PrematureEOF)
}

pub fn decode_float_simple_value_test() {
  // Simple value 20 (false) should not decode as float
  assert gleebor.decode_float(<<7:3, 20:5>>)
    == Error(gleebor.IncorrectType(major_type: 7))
}

// ---------------------------------------------------------------------------
// Decode – Booleans
// ---------------------------------------------------------------------------

pub fn decode_bool_false_test() {
  assert gleebor.decode_bool(<<7:3, 20:5>>) == Ok(#(False, <<>>))
}

pub fn decode_bool_true_test() {
  assert gleebor.decode_bool(<<7:3, 21:5>>) == Ok(#(True, <<>>))
}

pub fn decode_bool_with_rest_test() {
  assert gleebor.decode_bool(<<7:3, 21:5, 42>>) == Ok(#(True, <<42>>))
}

pub fn decode_bool_wrong_simple_value_test() {
  // null (22) is not a bool
  assert gleebor.decode_bool(<<7:3, 22:5>>)
    == Error(gleebor.IncorrectType(major_type: 7))
}

pub fn decode_bool_wrong_type_test() {
  assert gleebor.decode_bool(<<0:3, 5:5>>)
    == Error(gleebor.IncorrectType(major_type: 0))
}

// ---------------------------------------------------------------------------
// Decode – Null
// ---------------------------------------------------------------------------

pub fn decode_null_test() {
  assert gleebor.decode_null(<<7:3, 22:5>>) == Ok(#(Nil, <<>>))
}

pub fn decode_null_with_rest_test() {
  assert gleebor.decode_null(<<7:3, 22:5, 99>>) == Ok(#(Nil, <<99>>))
}

pub fn decode_null_wrong_type_test() {
  assert gleebor.decode_null(<<7:3, 20:5>>)
    == Error(gleebor.IncorrectType(major_type: 7))
}

// ---------------------------------------------------------------------------
// Decode – Undefined
// ---------------------------------------------------------------------------

pub fn decode_undefined_test() {
  assert gleebor.decode_undefined(<<7:3, 23:5>>) == Ok(#(Nil, <<>>))
}

pub fn decode_undefined_wrong_type_test() {
  assert gleebor.decode_undefined(<<7:3, 22:5>>)
    == Error(gleebor.IncorrectType(major_type: 7))
}

// ---------------------------------------------------------------------------
// Decode – Tags
// ---------------------------------------------------------------------------

pub fn decode_tag_small_test() {
  // Tag 1 (epoch datetime) followed by int 1363896240
  let data = <<6:3, 1:5, 0:3, 26:5, 1_363_896_240:32>>
  let assert Ok(#(tag, rest)) = gleebor.decode_tag(data)
  assert tag == 1
  let assert Ok(#(val, _)) = gleebor.decode_int(rest)
  assert val == 1_363_896_240
}

pub fn decode_tag_large_test() {
  // Self-described CBOR tag 55799
  let data = <<6:3, 25:5, 55_799:16>>
  assert gleebor.decode_tag(data) == Ok(#(55_799, <<>>))
}

pub fn decode_tag_wrong_type_test() {
  assert gleebor.decode_tag(<<0:3, 5:5>>)
    == Error(gleebor.IncorrectType(major_type: 0))
}

pub fn decode_tag_eof_test() {
  assert gleebor.decode_tag(<<>>) == Error(gleebor.PrematureEOF)
}

// ---------------------------------------------------------------------------
// Decode – Maps
// ---------------------------------------------------------------------------

pub fn decode_map_string_to_int_test() {
  // {"a": 1, "b": 2}
  let data = <<
    5:3, 2:5, 3:3, 1:5, "a":utf8, 0:3, 1:5, 3:3, 1:5, "b":utf8, 0:3, 2:5,
  >>
  let assert Ok(iter) =
    gleebor.decode_map(
      buffer: data,
      keys: gleebor.decode_string,
      values: gleebor.decode_int,
    )
  let pairs =
    iter
    |> yielder.map(fn(r) {
      let assert Ok(#(kv, _)) = r
      kv
    })
    |> yielder.to_list
  assert pairs == [#("a", 1), #("b", 2)]
}

pub fn decode_map_empty_test() {
  let data = <<5:3, 0:5>>
  let assert Ok(iter) =
    gleebor.decode_map(
      buffer: data,
      keys: gleebor.decode_string,
      values: gleebor.decode_int,
    )
  assert yielder.to_list(iter) == []
}

pub fn decode_map_wrong_type_test() {
  assert gleebor.decode_map(
      buffer: <<0:3, 5:5>>,
      keys: gleebor.decode_string,
      values: gleebor.decode_int,
    )
    == Error(gleebor.IncorrectType(major_type: 0))
}

// ---------------------------------------------------------------------------
// Decode – Indefinite bytes
// ---------------------------------------------------------------------------

pub fn decode_indefinite_bytes_test() {
  // Indefinite byte string: two chunks [<<1,2>>, <<3>>] then break
  let data = <<2:3, 31:5, 2:3, 2:5, 1, 2, 2:3, 1:5, 3, 0xff>>
  assert gleebor.decode_bytes(data) == Ok(#(<<1, 2, 3>>, <<>>))
}

pub fn decode_indefinite_bytes_empty_test() {
  // Indefinite byte string with no chunks, just break
  let data = <<2:3, 31:5, 0xff>>
  assert gleebor.decode_bytes(data) == Ok(#(<<>>, <<>>))
}

pub fn decode_indefinite_bytes_with_rest_test() {
  let data = <<2:3, 31:5, 2:3, 1:5, 42, 0xff, 99>>
  assert gleebor.decode_bytes(data) == Ok(#(<<42>>, <<99>>))
}

// ---------------------------------------------------------------------------
// Decode – Indefinite strings
// ---------------------------------------------------------------------------

pub fn decode_indefinite_string_test() {
  let data = <<
    3:3, 31:5, 3:3, 3:5, "hel":utf8, 3:3, 2:5, "lo":utf8, 0xff,
  >>
  assert gleebor.decode_string(data) == Ok(#("hello", <<>>))
}

pub fn decode_indefinite_string_empty_test() {
  let data = <<3:3, 31:5, 0xff>>
  assert gleebor.decode_string(data) == Ok(#("", <<>>))
}

// ---------------------------------------------------------------------------
// Decode – Indefinite arrays
// ---------------------------------------------------------------------------

pub fn decode_indefinite_list_test() {
  // Indefinite array of ints [1, 2, 3] then break
  let data = <<4:3, 31:5, 0:3, 1:5, 0:3, 2:5, 0:3, 3:5, 0xff>>
  let assert Ok(iter) =
    gleebor.decode_list(buffer: data, with: gleebor.decode_int)
  let values =
    iter
    |> yielder.map(fn(r) {
      let assert Ok(#(val, _)) = r
      val
    })
    |> yielder.to_list
  assert values == [1, 2, 3]
}

pub fn decode_indefinite_list_empty_test() {
  let data = <<4:3, 31:5, 0xff>>
  let assert Ok(iter) =
    gleebor.decode_list(buffer: data, with: gleebor.decode_int)
  assert yielder.to_list(iter) == []
}

// ---------------------------------------------------------------------------
// Decode – Indefinite maps
// ---------------------------------------------------------------------------

pub fn decode_indefinite_map_test() {
  // Indefinite map {"a": 1} then break
  let data = <<5:3, 31:5, 3:3, 1:5, "a":utf8, 0:3, 1:5, 0xff>>
  let assert Ok(iter) =
    gleebor.decode_map(
      buffer: data,
      keys: gleebor.decode_string,
      values: gleebor.decode_int,
    )
  let pairs =
    iter
    |> yielder.map(fn(r) {
      let assert Ok(#(kv, _)) = r
      kv
    })
    |> yielder.to_list
  assert pairs == [#("a", 1)]
}

pub fn decode_indefinite_map_empty_test() {
  let data = <<5:3, 31:5, 0xff>>
  let assert Ok(iter) =
    gleebor.decode_map(
      buffer: data,
      keys: gleebor.decode_string,
      values: gleebor.decode_int,
    )
  assert yielder.to_list(iter) == []
}

// ---------------------------------------------------------------------------
// Round-trip tests (encode then decode)
// ---------------------------------------------------------------------------

pub fn roundtrip_int_test() {
  let values = [0, 1, 23, 24, 255, 256, 65_535, 65_536, 1_000_000]
  let neg_values = [-1, -24, -25, -256, -500, -65_537]
  list.each(values, fn(n) {
    let assert Ok(#(decoded, <<>>)) = gleebor.decode_int(gleebor.encode_int(n))
    assert decoded == n
  })
  list.each(neg_values, fn(n) {
    let assert Ok(#(decoded, <<>>)) = gleebor.decode_int(gleebor.encode_int(n))
    assert decoded == n
  })
}

pub fn roundtrip_bytes_test() {
  let data = <<1, 2, 3, 4, 5>>
  let assert Ok(#(decoded, <<>>)) =
    gleebor.decode_bytes(gleebor.encode_bytes(data))
  assert decoded == data
}

pub fn roundtrip_string_test() {
  let s = "Hello, CBOR!"
  let assert Ok(#(decoded, <<>>)) =
    gleebor.decode_string(gleebor.encode_string(s))
  assert decoded == s
}

pub fn roundtrip_float_test() {
  let assert Ok(#(decoded, <<>>)) =
    gleebor.decode_float(gleebor.encode_float(3.14))
  assert decoded == 3.14
}

pub fn roundtrip_bool_test() {
  let assert Ok(#(False, <<>>)) =
    gleebor.decode_bool(gleebor.encode_bool(False))
  let assert Ok(#(True, <<>>)) =
    gleebor.decode_bool(gleebor.encode_bool(True))
}

pub fn roundtrip_null_test() {
  let assert Ok(#(Nil, <<>>)) = gleebor.decode_null(gleebor.encode_null())
}

pub fn roundtrip_list_test() {
  let encoded = gleebor.encode_list([10, 20, 30], with: gleebor.encode_int)
  let assert Ok(iter) =
    gleebor.decode_list(buffer: encoded, with: gleebor.decode_int)
  let values =
    iter
    |> yielder.map(fn(r) {
      let assert Ok(#(val, _)) = r
      val
    })
    |> yielder.to_list
  assert values == [10, 20, 30]
}

pub fn roundtrip_map_test() {
  let encoded =
    gleebor.encode_map(
      [#("x", 10), #("y", 20)],
      keys: gleebor.encode_string,
      values: gleebor.encode_int,
    )
  let assert Ok(iter) =
    gleebor.decode_map(
      buffer: encoded,
      keys: gleebor.decode_string,
      values: gleebor.decode_int,
    )
  let pairs =
    iter
    |> yielder.map(fn(r) {
      let assert Ok(#(kv, _)) = r
      kv
    })
    |> yielder.to_list
  assert pairs == [#("x", 10), #("y", 20)]
}

pub fn roundtrip_tag_test() {
  let tag_header = gleebor.encode_tag(1)
  let payload = gleebor.encode_int(1_000_000)
  let data = <<tag_header:bits, payload:bits>>
  let assert Ok(#(1, rest)) = gleebor.decode_tag(data)
  let assert Ok(#(1_000_000, <<>>)) = gleebor.decode_int(rest)
}

pub fn roundtrip_indefinite_bytes_test() {
  let encoded = gleebor.encode_indefinite_bytes([<<1, 2>>, <<3, 4>>])
  let assert Ok(#(decoded, <<>>)) = gleebor.decode_bytes(encoded)
  assert decoded == <<1, 2, 3, 4>>
}

pub fn roundtrip_indefinite_string_test() {
  let encoded = gleebor.encode_indefinite_string(["hello", " ", "world"])
  let assert Ok(#(decoded, <<>>)) = gleebor.decode_string(encoded)
  assert decoded == "hello world"
}

import gleam/list
