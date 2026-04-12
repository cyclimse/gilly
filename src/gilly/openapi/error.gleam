import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/string

pub type Error {
  /// An error occurred while parsing the OpenAPI JSON.
  JsonError(inner: json.DecodeError)

  /// The version of the OpenAPI specification is not supported by this library.
  UnsupportedVersion(version: String)

  /// The OpenAPI specification could not be decoded into the expected structure.
  ParseError(inner: List(decode.DecodeError))
}

pub fn describe_error(error: Error) -> String {
  case error {
    JsonError(inner) -> "JSON parsing error: " <> describe_json_error(inner)
    UnsupportedVersion(version) -> "Unsupported OpenAPI version: " <> version
    ParseError(errors) ->
      "Failed to decode OpenAPI specification: "
      <> describe_decode_errors(errors)
  }
}

// Note: I could probably use pprint to make it easy on myself
fn describe_json_error(error: json.DecodeError) -> String {
  case error {
    json.UnexpectedEndOfInput -> "Unexpected end of input"
    json.UnexpectedByte(byte) -> "Unexpected byte: " <> byte
    json.UnexpectedSequence(seq) -> "Unexpected sequence: " <> seq
    json.UnableToDecode(errors) ->
      "Unable to decode: " <> describe_decode_errors(errors)
  }
}

fn describe_decode_errors(errors: List(decode.DecodeError)) -> String {
  string.join(
    list.map(errors, fn(e) {
      let decode.DecodeError(expected:, found:, path:) = e
      let path_str = string.join(path, " -> ")
      "Expected " <> expected <> " but got " <> found <> " at path " <> path_str
    }),
    "; ",
  )
}
