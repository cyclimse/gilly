import gleam/dict
import gleam/dynamic/decode
import gleam/option.{type Option}

pub type TypeName {
  StringType
  IntegerType
  NumberType
  ArrayType
  ObjectType
  BooleanType
}

fn type_name_decoder() -> decode.Decoder(TypeName) {
  use variant <- decode.then(decode.string)
  case variant {
    "string" -> decode.success(StringType)
    "integer" -> decode.success(IntegerType)
    "number" -> decode.success(NumberType)
    "array" -> decode.success(ArrayType)
    "object" -> decode.success(ObjectType)
    "boolean" -> decode.success(BooleanType)
    _ -> decode.failure(StringType, "TypeName")
  }
}

pub type Schema {
  Ref(ref: String)
  String(BaseSchema, StringSchema)
  Integer(BaseSchema, IntegerSchema)
  Number(BaseSchema)
  Array(BaseSchema, ArraySchema)
  Object(BaseSchema, ObjectSchema)
  Boolean(BaseSchema)
}

pub fn schema_decoder() -> decode.Decoder(Schema) {
  decode.one_of(ref_decoder(), or: [typed_schema_decoder()])
}

fn ref_decoder() -> decode.Decoder(Schema) {
  use ref <- decode.field("$ref", decode.string)
  decode.success(Ref(ref:))
}

fn typed_schema_decoder() -> decode.Decoder(Schema) {
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
    NumberType -> decode.success(Number(base_schema))
    ArrayType ->
      decode.then(array_schema_decoder(), fn(array_schema) {
        decode.success(Array(base_schema, array_schema))
      })
    ObjectType ->
      decode.then(object_schema_decoder(), fn(object_schema) {
        decode.success(Object(base_schema, object_schema))
      })
    BooleanType -> decode.success(Boolean(base_schema))
  }
}

pub type BaseSchema {
  BaseSchema(
    type_name: TypeName,
    title: Option(String),
    description: Option(String),
    nullable: Bool,
  )
}

fn base_schema_decoder() -> decode.Decoder(BaseSchema) {
  use type_name <- decode.field("type", type_name_decoder())
  use title <- decode.optional_field(
    "title",
    option.None,
    decode.optional(decode.string),
  )
  use description <- decode.optional_field(
    "description",
    option.None,
    decode.optional(decode.string),
  )
  use nullable <- decode.optional_field("nullable", False, decode.bool)
  decode.success(BaseSchema(type_name:, title:, description:, nullable:))
}

pub type StringSchema {
  StringSchema(
    min_length: Option(Int),
    max_length: Option(Int),
    enum: Option(List(String)),
    format: Option(String),
  )
}

fn string_schema_decoder() -> decode.Decoder(StringSchema) {
  use min_length <- decode.optional_field(
    "minLength",
    option.None,
    decode.optional(decode.int),
  )
  use max_length <- decode.optional_field(
    "maxLength",
    option.None,
    decode.optional(decode.int),
  )
  use enum <- decode.optional_field(
    "enum",
    option.None,
    decode.optional(decode.list(decode.string)),
  )
  use format <- decode.optional_field(
    "format",
    option.None,
    decode.optional(decode.string),
  )
  decode.success(StringSchema(min_length:, max_length:, enum:, format:))
}

pub type IntegerSchema {
  IntegerSchema(
    minimum: Option(Int),
    maximum: Option(Int),
    format: Option(String),
  )
}

fn integer_schema_decoder() -> decode.Decoder(IntegerSchema) {
  use minimum <- decode.optional_field(
    "minimum",
    option.None,
    decode.optional(decode.int),
  )
  use maximum <- decode.optional_field(
    "maximum",
    option.None,
    decode.optional(decode.int),
  )
  use format <- decode.optional_field(
    "format",
    option.None,
    decode.optional(decode.string),
  )
  decode.success(IntegerSchema(minimum:, maximum:, format:))
}

pub type ArraySchema {
  ArraySchema(min_items: Option(Int), max_items: Option(Int), items: Schema)
}

fn array_schema_decoder() -> decode.Decoder(ArraySchema) {
  use min_items <- decode.optional_field(
    "minItems",
    option.None,
    decode.optional(decode.int),
  )
  use max_items <- decode.optional_field(
    "maxItems",
    option.None,
    decode.optional(decode.int),
  )
  use items <- decode.field("items", schema_decoder())
  decode.success(ArraySchema(min_items:, max_items:, items:))
}

pub type ObjectSchema {
  ObjectSchema(required: List(String), properties: List(#(String, Schema)))
}

fn object_schema_decoder() -> decode.Decoder(ObjectSchema) {
  use required <- decode.optional_field(
    "required",
    [],
    decode.list(decode.string),
  )
  use properties <- decode.optional_field(
    "properties",
    [],
    decode.dict(decode.string, schema_decoder())
      |> decode.map(dict.to_list),
  )
  decode.success(ObjectSchema(required:, properties:))
}
