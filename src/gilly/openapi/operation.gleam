import gilly/openapi/schema.{type Schema, schema_decoder}
import gleam/dict
import gleam/dynamic/decode
import gleam/option.{type Option}

pub type Operation {
  Operation(
    operation_id: Option(String),
    summary: Option(String),
    description: Option(String),
    tags: List(String),
    parameters: List(Parameter),
    request_body: Option(RequestBody),
    responses: List(#(String, Response)),
  )
}

pub fn operation_decoder() -> decode.Decoder(Operation) {
  use operation_id <- decode.optional_field(
    "operationId",
    option.None,
    decode.optional(decode.string),
  )
  use summary <- decode.optional_field(
    "summary",
    option.None,
    decode.optional(decode.string),
  )
  use description <- decode.optional_field(
    "description",
    option.None,
    decode.optional(decode.string),
  )
  use tags <- decode.optional_field("tags", [], decode.list(decode.string))
  use parameters <- decode.optional_field(
    "parameters",
    [],
    decode.list(parameter_decoder()),
  )
  use request_body <- decode.optional_field(
    "requestBody",
    option.None,
    decode.optional(request_body_decoder()),
  )
  use responses <- decode.optional_field(
    "responses",
    [],
    decode.dict(decode.string, response_decoder())
      |> decode.map(dict.to_list),
  )
  decode.success(Operation(
    operation_id:,
    summary:,
    description:,
    tags:,
    parameters:,
    request_body:,
    responses:,
  ))
}

pub type ParameterLocation {
  Query
  Path
  Header
  Cookie
}

fn parameter_location_decoder() -> decode.Decoder(ParameterLocation) {
  use variant <- decode.then(decode.string)
  case variant {
    "query" -> decode.success(Query)
    "path" -> decode.success(Path)
    "header" -> decode.success(Header)
    "cookie" -> decode.success(Cookie)
    _ -> decode.failure(Query, "ParameterLocation")
  }
}

pub type Parameter {
  Parameter(
    name: String,
    in_: ParameterLocation,
    description: Option(String),
    required: Bool,
    schema: Option(Schema),
  )
}

fn parameter_decoder() -> decode.Decoder(Parameter) {
  use name <- decode.field("name", decode.string)
  use in_ <- decode.field("in", parameter_location_decoder())
  use description <- decode.optional_field(
    "description",
    option.None,
    decode.optional(decode.string),
  )
  use required <- decode.optional_field("required", False, decode.bool)
  use schema <- decode.optional_field(
    "schema",
    option.None,
    decode.optional(schema_decoder()),
  )
  decode.success(Parameter(name:, in_:, description:, required:, schema:))
}

pub type RequestBody {
  RequestBody(
    description: Option(String),
    required: Bool,
    content: List(#(String, MediaType)),
  )
}

fn request_body_decoder() -> decode.Decoder(RequestBody) {
  use description <- decode.optional_field(
    "description",
    option.None,
    decode.optional(decode.string),
  )
  use required <- decode.optional_field("required", False, decode.bool)
  use content <- decode.optional_field(
    "content",
    [],
    decode.dict(decode.string, media_type_decoder())
      |> decode.map(dict.to_list),
  )
  decode.success(RequestBody(description:, required:, content:))
}

pub type MediaType {
  MediaType(schema: Option(Schema))
}

fn media_type_decoder() -> decode.Decoder(MediaType) {
  use schema <- decode.optional_field(
    "schema",
    option.None,
    decode.optional(schema_decoder()),
  )
  decode.success(MediaType(schema:))
}

pub type Response {
  Response(description: String, content: List(#(String, MediaType)))
}

fn response_decoder() -> decode.Decoder(Response) {
  use description <- decode.optional_field("description", "", decode.string)
  use content <- decode.optional_field(
    "content",
    [],
    decode.dict(decode.string, media_type_decoder())
      |> decode.map(dict.to_list),
  )
  decode.success(Response(description:, content:))
}
