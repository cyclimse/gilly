import gleam/dynamic/decode
import gleam/option.{type Option}

pub type TypeName {
  StringType
  IntegerType
  ArrayType
  ObjectType
}

fn type_name_decoder() -> decode.Decoder(TypeName) {
  use variant <- decode.then(decode.string)
  case variant {
    "string" -> decode.success(StringType)
    "integer" -> decode.success(IntegerType)
    "array" -> decode.success(ArrayType)
    "object" -> decode.success(ObjectType)
    _ -> decode.failure(StringType, "TypeName")
  }
}

pub type Schema {
  String(BaseSchema, StringSchema)
  Integer(BaseSchema, IntegerSchema)
  Array(BaseSchema, ArraySchema)
  Object(BaseSchema, ObjectSchema)
}

pub fn schema_decoder() -> decode.Decoder(Schema) {
  use base_schema <- decode.then(base_schema_decoder())
  case base_schema.type_name {
    StringType ->
      decode.then(string_schema_decoder(), fn(string_schema) {
        decode.success(String(base_schema, string_schema))
      })
    IntegerType ->
      decode.then(integer_schema_decoder(), fn(integer_schema) {
        decode.success(Integer(base_schema, integer_schema))
      })
    ArrayType ->
      decode.then(array_schema_decoder(), fn(array_schema) {
        decode.success(Array(base_schema, array_schema))
      })
    ObjectType ->
      decode.then(object_schema_decoder(), fn(object_schema) {
        decode.success(Object(base_schema, object_schema))
      })
  }
}

pub type BaseSchema {
  BaseSchema(
    name: String,
    type_name: TypeName,
    title: Option(String),
    description: Option(String),
  )
}

fn base_schema_decoder() -> decode.Decoder(BaseSchema) {
  use name <- decode.field("name", decode.string)
  use type_name <- decode.field("type", type_name_decoder())
  use title <- decode.field("title", decode.optional(decode.string))
  use description <- decode.field("description", decode.optional(decode.string))
  decode.success(BaseSchema(name:, type_name:, title:, description:))
}

pub type StringSchema {
  StringSchema(min_length: Int, max_length: Option(Int))
}

fn string_schema_decoder() -> decode.Decoder(StringSchema) {
  use min_length <- decode.field("min_length", decode.int)
  use max_length <- decode.field("max_length", decode.optional(decode.int))
  decode.success(StringSchema(min_length:, max_length:))
}

pub type IntegerSchema {
  IntegerSchema(minimum: Option(Float), maximum: Option(Float))
}

fn integer_schema_decoder() -> decode.Decoder(IntegerSchema) {
  use minimum <- decode.field("minimum", decode.optional(decode.float))
  use maximum <- decode.field("maximum", decode.optional(decode.float))
  decode.success(IntegerSchema(minimum:, maximum:))
}

pub type ArraySchema {
  ArraySchema(min_items: Int, max_items: Option(Int), items: List(Schema))
}

fn array_schema_decoder() -> decode.Decoder(ArraySchema) {
  use min_items <- decode.field("min_items", decode.int)
  use max_items <- decode.field("max_items", decode.optional(decode.int))
  use items <- decode.field("items", decode.list(schema_decoder()))
  decode.success(ArraySchema(min_items:, max_items:, items:))
}

pub type ObjectSchema {
  ObjectSchema(required: List(String), properties: List(#(String, Schema)))
}

fn object_schema_decoder() -> decode.Decoder(ObjectSchema) {
  use required <- decode.field("required", decode.list(decode.string))
  use properties <- decode.field(
    "properties",
    decode.list({
      use a <- decode.field(0, decode.string)
      use b <- decode.field(1, schema_decoder())

      decode.success(#(a, b))
    }),
  )
  decode.success(ObjectSchema(required:, properties:))
}
