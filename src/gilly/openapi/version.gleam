import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string

pub const unsupported_sentinel = "Unsupported OpenAPI version: "

const nil_version = Version(0, option.None, option.None)

pub type Version {
  Version(major: Int, minor: Option(Int), patch: Option(Int))
}

pub fn version_decoder() -> decode.Decoder(Version) {
  decode.then(decode.string, fn(version_str) {
    case parse_version(version_str) {
      Ok(version) ->
        case version_is_supported(version) {
          True -> decode.success(version)
          False ->
            decode.failure(
              nil_version,
              expected: unsupported_sentinel <> version_str,
            )
        }
      Error(msg) -> decode.failure(nil_version, expected: msg)
    }
  })
}

fn parse_version(version_str: String) -> Result(Version, String) {
  let split = string.split(version_str, ".")
  use major_str <- result.try(
    list.first(split) |> result.map_error(fn(_) { "Version string is empty" }),
  )
  use major <- result.try(
    int.parse(major_str)
    |> result.map_error(fn(_) { "Major version is not a valid integer" }),
  )
  case split {
    [_, minor_str, patch_str] ->
      Ok(Version(
        major,
        int.parse(minor_str) |> option.from_result,
        int.parse(patch_str) |> option.from_result,
      ))
    [_, minor_str] ->
      Ok(Version(major, int.parse(minor_str) |> option.from_result, option.None))
    [_] -> Ok(Version(major, option.None, option.None))
    _ -> Error("Version string must be in the format 'X', 'X.Y', or 'X.Y.Z'")
  }
}

pub fn version_is_supported(version: Version) -> Bool {
  case version {
    Version(3, option.Some(0), _) -> True
    Version(3, option.Some(1), _) -> True
    Version(3, option.None, _) -> True
    _ -> False
  }
}
