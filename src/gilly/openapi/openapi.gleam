import gilly/openapi/schema.{type Schema, schema_decoder}
import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option}

pub type OpenAPI {
  OpenAPI(version: String, info: Info, components: Option(Components))
}

pub fn openapi_decoder() -> decode.Decoder(OpenAPI) {
  use info <- decode.field("info", info_decoder())

  use version <- decode.field("openapi", decode.string)
  use components <- decode.field(
    "components",
    decode.optional(components_decoder()),
  )
  decode.success(OpenAPI(version:, info:, components:))
}

pub fn from_json_string(
  json_string: String,
) -> Result(OpenAPI, json.DecodeError) {
  json.parse(json_string, openapi_decoder())
}

pub type Info {
  Info(title: String, version: String, description: Option(String))
}

fn info_decoder() -> decode.Decoder(Info) {
  use title <- decode.field("title", decode.string)
  use version <- decode.field("version", decode.string)
  use description <- decode.field("description", decode.optional(decode.string))
  decode.success(Info(title:, version:, description:))
}

pub type Components {
  Components(schemas: List(#(String, Schema)))
}

fn components_decoder() -> decode.Decoder(Components) {
  use schemas <- decode.field(
    "schemas",
    decode.list({
      use a <- decode.field(0, decode.string)
      use b <- decode.field(1, schema_decoder())

      decode.success(#(a, b))
    }),
  )
  decode.success(Components(schemas:))
}
