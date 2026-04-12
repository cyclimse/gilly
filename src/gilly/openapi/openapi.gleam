import gilly/openapi/error.{type Error}
import gilly/openapi/operation.{type Operation, operation_decoder}
import gilly/openapi/schema.{type Schema, schema_decoder}
import gilly/openapi/version.{type Version, version_decoder}
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string

pub type Server {
  Server(url: String)
}

pub type OpenAPI {
  OpenAPI(
    version: Version,
    info: Info,
    servers: List(Server),
    paths: List(#(String, PathItem)),
    components: Option(Components),
  )
}

fn server_decoder() -> decode.Decoder(Server) {
  use url <- decode.field("url", decode.string)
  decode.success(Server(url:))
}

pub fn openapi_decoder() -> decode.Decoder(OpenAPI) {
  use info <- decode.field("info", info_decoder())
  use version <- decode.field("openapi", version_decoder())
  use servers <- decode.optional_field(
    "servers",
    [],
    decode.list(server_decoder()),
  )
  use paths <- decode.optional_field(
    "paths",
    [],
    decode.dict(decode.string, path_item_decoder())
      |> decode.map(dict.to_list),
  )
  use components <- decode.optional_field(
    "components",
    option.None,
    decode.optional(components_decoder()),
  )
  decode.success(OpenAPI(version:, info:, servers:, paths:, components:))
}

pub fn from_json_string(json_string: String) -> Result(OpenAPI, Error) {
  json.parse(json_string, openapi_decoder())
  |> result.map_error(fn(e) {
    case e {
      json.UnableToDecode(errors) -> handle_decode_errors(errors)
      _ -> error.JsonError(inner: e)
    }
  })
}

/// Handle decode errors by converting them into our custom `Error` type.
fn handle_decode_errors(errors: List(decode.DecodeError)) -> Error {
  let version_unsupported =
    list.find_map(errors, fn(e) {
      let decode.DecodeError(expected:, ..) = e
      case string.split_once(expected, version.unsupported_sentinel) {
        Ok(#(_, version)) -> Ok(version)
        Error(_) -> Error(e)
      }
    })
  case version_unsupported {
    Ok(version) -> error.UnsupportedVersion(version)
    Error(_) -> error.ParseError(inner: errors)
  }
}

pub type Info {
  Info(title: String, version: String, description: Option(String))
}

fn info_decoder() -> decode.Decoder(Info) {
  use title <- decode.field("title", decode.string)
  use version <- decode.field("version", decode.string)
  use description <- decode.optional_field(
    "description",
    option.None,
    decode.optional(decode.string),
  )
  decode.success(Info(title:, version:, description:))
}

pub type Components {
  Components(schemas: List(#(String, Schema)))
}

fn components_decoder() -> decode.Decoder(Components) {
  use schemas <- decode.field(
    "schemas",
    decode.dict(decode.string, schema_decoder())
      |> decode.map(dict.to_list),
  )
  decode.success(Components(schemas:))
}

pub type PathItem {
  PathItem(
    get: Option(Operation),
    post: Option(Operation),
    put: Option(Operation),
    delete: Option(Operation),
    patch: Option(Operation),
  )
}

fn path_item_decoder() -> decode.Decoder(PathItem) {
  use get <- decode.optional_field(
    "get",
    option.None,
    decode.optional(operation_decoder()),
  )
  use post <- decode.optional_field(
    "post",
    option.None,
    decode.optional(operation_decoder()),
  )
  use put <- decode.optional_field(
    "put",
    option.None,
    decode.optional(operation_decoder()),
  )
  use delete <- decode.optional_field(
    "delete",
    option.None,
    decode.optional(operation_decoder()),
  )
  use patch <- decode.optional_field(
    "patch",
    option.None,
    decode.optional(operation_decoder()),
  )
  decode.success(PathItem(get:, post:, put:, delete:, patch:))
}
