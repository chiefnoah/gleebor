import gleam/bit_array
import gleebor

// ---------------------------------------------------------------------------
// Encode – Integers
// ---------------------------------------------------------------------------

pub fn encode_small_positive_int_test() {
  assert gleebor.encode_int(0) == <<0:3, 0:5>>
  assert gleebor.encode_int(13) == <<0:3, 13:5>>
  assert gleebor.encode_int(23) == <<0:3, 23:5>>
}

pub fn encode_u8_int_test() {
  assert gleebor.encode_int(24) == <<0:3, 24:5, 24:8>>
  assert gleebor.encode_int(123) == <<0:3, 24:5, 123:8>>
  assert gleebor.encode_int(255) == <<0:3, 24:5, 255:8>>
}

pub fn encode_u16_int_test() {
  assert gleebor.encode_int(256) == <<0:3, 25:5, 256:16>>
  assert gleebor.encode_int(1000) == <<0:3, 25:5, 1000:16>>
}

pub fn encode_u32_int_test() {
  assert gleebor.encode_int(65_536) == <<0:3, 26:5, 65_536:32>>
  assert gleebor.encode_int(1_000_000) == <<0:3, 26:5, 1_000_000:32>>
}

pub fn encode_u64_int_test() {
  assert gleebor.encode_int(4_294_967_296)
    == <<0:3, 27:5, 4_294_967_296:64>>
}

pub fn encode_small_negative_int_test() {
  assert gleebor.encode_int(-1) == <<1:3, 0:5>>
  assert gleebor.encode_int(-10) == <<1:3, 9:5>>
  assert gleebor.encode_int(-24) == <<1:3, 23:5>>
}

pub fn encode_negative_u8_int_test() {
  assert gleebor.encode_int(-25) == <<1:3, 24:5, 24:8>>
  assert gleebor.encode_int(-100) == <<1:3, 24:5, 99:8>>
}

pub fn encode_negative_u16_int_test() {
  // RFC 8949 example: -500 encodes as major type 1, value 499
  assert gleebor.encode_int(-500) == <<1:3, 25:5, 499:16>>
}

// ---------------------------------------------------------------------------
// Encode – Byte strings
// ---------------------------------------------------------------------------

pub fn encode_bytes_small_test() {
  assert gleebor.encode_bytes(<<123>>) == <<2:3, 1:5, 123>>
}

pub fn encode_bytes_empty_test() {
  assert gleebor.encode_bytes(<<>>) == <<2:3, 0:5>>
}

pub fn encode_bytes_large_test() {
  let data = <<
    78:int-size(64), 78:int-size(64), 78:int-size(64), 78:int-size(64),
  >>
  assert gleebor.encode_bytes(data)
    == <<2:3, 24:5, 32:8, 78:int-size(64), 78:int-size(64), 78:int-size(64), 78:int-size(64)>>
}

// ---------------------------------------------------------------------------
// Encode – Text strings
// ---------------------------------------------------------------------------

pub fn encode_string_small_test() {
  assert gleebor.encode_string("N") == <<3:3, 1:5, "N":utf8>>
}

pub fn encode_string_empty_test() {
  assert gleebor.encode_string("") == <<3:3, 0:5>>
}

pub fn encode_string_large_test() {
  let s = "Hello, world! This is a long string!"
  let b = bit_array.from_string(s)
  let expected = <<3:3, 24:5, 36:8, b:bits>>
  assert gleebor.encode_string(s) == expected
}

// ---------------------------------------------------------------------------
// Encode – Arrays
// ---------------------------------------------------------------------------

pub fn encode_list_ints_test() {
  let encoded = gleebor.encode_list([5, 4, 3], with: gleebor.encode_int)
  assert encoded == <<4:3, 3:5, 0:3, 5:5, 0:3, 4:5, 0:3, 3:5>>
}

pub fn encode_list_empty_test() {
  let encoded = gleebor.encode_list([], with: gleebor.encode_int)
  assert encoded == <<4:3, 0:5>>
}

pub fn encode_list_strings_test() {
  let encoded = gleebor.encode_list(["a", "b"], with: gleebor.encode_string)
  assert encoded
    == <<4:3, 2:5, 3:3, 1:5, "a":utf8, 3:3, 1:5, "b":utf8>>
}

// ---------------------------------------------------------------------------
// Encode – Maps
// ---------------------------------------------------------------------------

pub fn encode_map_test() {
  let encoded =
    gleebor.encode_map(
      [#("a", 1), #("b", 2)],
      keys: gleebor.encode_string,
      values: gleebor.encode_int,
    )
  assert encoded
    == <<
      5:3, 2:5, 3:3, 1:5, "a":utf8, 0:3, 1:5, 3:3, 1:5, "b":utf8, 0:3, 2:5,
    >>
}

pub fn encode_map_empty_test() {
  let encoded =
    gleebor.encode_map(
      [],
      keys: gleebor.encode_string,
      values: gleebor.encode_int,
    )
  assert encoded == <<5:3, 0:5>>
}

// ---------------------------------------------------------------------------
// Encode – Tags
// ---------------------------------------------------------------------------

pub fn encode_tag_small_test() {
  assert gleebor.encode_tag(1) == <<6:3, 1:5>>
}

pub fn encode_tag_large_test() {
  // Self-described CBOR tag 55799
  assert gleebor.encode_tag(55_799) == <<6:3, 25:5, 55_799:16>>
}

// ---------------------------------------------------------------------------
// Encode – Floats & simple values
// ---------------------------------------------------------------------------

pub fn encode_float_test() {
  assert gleebor.encode_float(1.5) == <<7:3, 27:5, 1.5:float-size(64)>>
  assert gleebor.encode_float(0.0) == <<7:3, 27:5, 0.0:float-size(64)>>
  assert gleebor.encode_float(-4.1) == <<7:3, 27:5, -4.1:float-size(64)>>
}

pub fn encode_bool_test() {
  assert gleebor.encode_bool(False) == <<7:3, 20:5>>
  assert gleebor.encode_bool(True) == <<7:3, 21:5>>
}

pub fn encode_null_test() {
  assert gleebor.encode_null() == <<7:3, 22:5>>
}

pub fn encode_undefined_test() {
  assert gleebor.encode_undefined() == <<7:3, 23:5>>
}

// ---------------------------------------------------------------------------
// Encode – Indefinite sequences
// ---------------------------------------------------------------------------

pub fn encode_indefinite_bytes_test() {
  let encoded = gleebor.encode_indefinite_bytes([<<1, 2>>, <<3>>])
  assert encoded == <<2:3, 31:5, 2:3, 2:5, 1, 2, 2:3, 1:5, 3, 0xff>>
}

pub fn encode_indefinite_string_test() {
  let encoded = gleebor.encode_indefinite_string(["hel", "lo"])
  assert encoded
    == <<
      3:3, 31:5, 3:3, 3:5, "hel":utf8, 3:3, 2:5, "lo":utf8, 0xff,
    >>
}

pub fn encode_indefinite_list_test() {
  let items = [gleebor.encode_int(1), gleebor.encode_int(2)]
  let encoded = gleebor.encode_indefinite_list(items)
  assert encoded == <<4:3, 31:5, 0:3, 1:5, 0:3, 2:5, 0xff>>
}

pub fn encode_indefinite_map_test() {
  let entries = [
    #(gleebor.encode_string("a"), gleebor.encode_int(1)),
  ]
  let encoded = gleebor.encode_indefinite_map(entries)
  assert encoded
    == <<5:3, 31:5, 3:3, 1:5, "a":utf8, 0:3, 1:5, 0xff>>
}
