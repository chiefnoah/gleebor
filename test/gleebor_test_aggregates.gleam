import gleam/result
import gleam/yielder
import gleebor

pub fn decode_byte_string_test() {
  // a small byte array
  assert gleebor.decode_bytes(<<2:3, 1:5, 123>>) == Ok(#(<<123>>, <<>>))
  // a larger one, uses a u8
  let larger_string = <<
    2:3, 24:5, 32:8, 78:int-size(64), 78:int-size(64), 78:int-size(64),
    78:int-size(64),
  >>
  let expected = <<
    78:int-size(64), 78:int-size(64), 78:int-size(64), 78:int-size(64),
  >>
  assert gleebor.decode_bytes(larger_string) == Ok(#(expected, <<>>))
}

pub fn decode_uft8_string_test() {
  // a small byte array
  assert gleebor.decode_string(<<3:3, 1:5, "N":utf8>>) == Ok(#("N", <<>>))
  // a larger one, uses a u8

  let larger_string = <<
    3:3, 24:5, 36:8, "Hello, world! This is a long string!":utf8,
  >>
  assert gleebor.decode_string(larger_string)
    == Ok(#("Hello, world! This is a long string!", <<>>))
}

pub fn decode_list_ints_test() {
  let cbor_list = <<4:3, 3:5, 5:8, 4:8, 3:8>>
  assert gleebor.decode_list(cbor_list, with: gleebor.decode_int)
    |> result.unwrap(yielder.empty())
    |> yielder.map(fn(r) {
      let assert Ok(#(val, _)) = r
      val
    })
    |> yielder.to_list
    == [5, 4, 3]
}

pub fn decode_list_strings_failure_test() {
  let cbor_list = <<4:3, 3:5, 5:8, 4:8, 3:8>>
  let assert Ok(lazily_decoding) =
    gleebor.decode_list(cbor_list, with: gleebor.decode_string)
  let assert Ok(first_decoded) = yielder.first(lazily_decoding)
  assert first_decoded == Error(gleebor.IncorrectType(major_type: 0))
}
