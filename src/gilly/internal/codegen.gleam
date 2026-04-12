import gilly/openapi/openapi.{type OpenAPI}
import gilly/openapi/schema.{
  type ArraySchema, type BaseSchema, type ObjectSchema, type Schema,
  type StringSchema,
}
import glam/doc.{type Document}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import justin

/// Controls how the codegen decides whether a field should be `Option(T)`.
///
pub type Optionality {
  /// Only fields listed in the `required` array are non-optional.
  /// This is the strict OpenAPI interpretation.
  RequiredOnly
  /// Fields are required unless marked `nullable: true`.
  /// Useful for specs (like Scaleway) that don't use `required` arrays.
  NullableOnly
  /// A field is optional if it's not in `required` OR is `nullable: true`.
  /// This combines both signals.
  RequiredAndNullable
}

/// Configuration for the code generator.
///
pub type Config {
  Config(optionality: Optionality, indent: Int)
}

/// Generate Gleam source code for the schema types in an OpenAPI spec.
///
pub fn generate_schemas(spec: OpenAPI, config: Config) -> String {
  let schemas = extract_schemas(spec)

  let type_docs =
    list.map(schemas, fn(entry) {
      let #(name, schema) = entry
      schema_to_type_doc(name, schema, schemas, config)
    })

  let code =
    doc.join(type_docs, with: doc.lines(2))
    |> doc.append(doc.line)

  doc.to_string(code, 80)
}

fn extract_schemas(spec: OpenAPI) -> List(#(String, Schema)) {
  spec.components
  |> option.map(fn(c) { c.schemas })
  |> option.unwrap([])
}

// --- Type generation ---------------------------------------------------------

fn schema_to_type_doc(
  name: String,
  schema: Schema,
  all_schemas: List(#(String, Schema)),
  config: Config,
) -> Document {
  let type_name = to_type_name(name)
  case schema {
    schema.Object(base, object_schema) ->
      object_type_doc(type_name, base, object_schema, all_schemas, config)
    _ ->
      // For non-object top-level schemas, generate a type alias-like wrapper
      simple_type_doc(type_name, schema, all_schemas, config)
  }
}

fn object_type_doc(
  type_name: String,
  base: BaseSchema,
  object_schema: ObjectSchema,
  all_schemas: List(#(String, Schema)),
  config: Config,
) -> Document {
  let comment = base_schema_comment(base)

  let fields =
    list.map(object_schema.properties, fn(prop) {
      let #(prop_name, prop_schema) = prop
      let field_name = to_field_name(prop_name)
      let in_required = list.contains(object_schema.required, prop_name)
      let optional =
        is_field_optional(prop_schema, in_required, config.optionality)
      let field_type = schema_to_gleam_type(prop_schema, !optional, all_schemas)

      let field_line =
        doc.concat([
          doc.from_string(field_name <> ": "),
          field_type,
        ])

      case schema_description(prop_schema) {
        Some(comment) -> doc.concat([comment, doc.line, field_line])
        None -> field_line
      }
    })

  let indent = config.indent

  let body = case fields {
    [] ->
      doc.concat([
        doc.from_string("pub type " <> type_name <> " {"),
        doc.line |> doc.nest(by: indent),
        doc.from_string(type_name)
          |> doc.nest(by: indent),
        doc.line,
        doc.from_string("}"),
      ])
    _ ->
      doc.concat([
        doc.from_string("pub type " <> type_name <> " {"),
        doc.line |> doc.nest(by: indent),
        doc.concat([
          doc.from_string(type_name <> "("),
          doc.line |> doc.nest(by: indent),
          doc.join(fields, with: doc.concat([doc.from_string(","), doc.line]))
            |> doc.nest(by: indent),
          doc.concat([doc.from_string(","), doc.line]),
          doc.from_string(")"),
        ])
          |> doc.nest(by: indent),
        doc.line,
        doc.from_string("}"),
      ])
  }

  case comment {
    Some(c) -> doc.concat([c, doc.line, body])
    None -> body
  }
}

fn simple_type_doc(
  type_name: String,
  schema: Schema,
  all_schemas: List(#(String, Schema)),
  config: Config,
) -> Document {
  let gleam_type = schema_to_gleam_type(schema, True, all_schemas)
  doc.concat([
    doc.from_string("pub type " <> type_name <> " ="),
    doc.line |> doc.nest(by: config.indent),
    gleam_type |> doc.nest(by: config.indent),
  ])
}

// --- Type mapping ------------------------------------------------------------

fn schema_to_gleam_type(
  schema: Schema,
  required: Bool,
  all_schemas: List(#(String, Schema)),
) -> Document {
  let inner = case schema {
    schema.Ref(ref:) -> doc.from_string(ref_to_type_name(ref))
    schema.String(_, string_schema) -> string_type(string_schema)
    schema.Integer(_, _) -> doc.from_string("Int")
    schema.Number(_) -> doc.from_string("Float")
    schema.Boolean(_) -> doc.from_string("Bool")
    schema.Array(_, array_schema) -> array_type(array_schema, all_schemas)
    schema.Object(_, object_schema) ->
      inline_object_type(object_schema, all_schemas)
  }

  case required {
    True -> inner
    False -> wrap_optional(inner)
  }
}

fn string_type(string_schema: StringSchema) -> Document {
  case string_schema.enum {
    Some(_) ->
      // Enums on strings — for now just use String
      doc.from_string("String")
    None ->
      case string_schema.format {
        Some("date-time") -> doc.from_string("String")
        Some("binary") -> doc.from_string("BitArray")
        _ -> doc.from_string("String")
      }
  }
}

fn array_type(
  array_schema: ArraySchema,
  all_schemas: List(#(String, Schema)),
) -> Document {
  let items_type = schema_to_gleam_type(array_schema.items, True, all_schemas)
  doc.concat([
    doc.from_string("List("),
    items_type,
    doc.from_string(")"),
  ])
}

fn inline_object_type(
  _object_schema: ObjectSchema,
  _all_schemas: List(#(String, Schema)),
) -> Document {
  // For inline anonymous objects, fall back to a generic type
  doc.from_string("Dynamic")
}

fn wrap_optional(inner: Document) -> Document {
  doc.concat([
    doc.from_string("Option("),
    inner,
    doc.from_string(")"),
  ])
}

// --- Optionality logic -------------------------------------------------------

fn is_field_optional(
  prop_schema: Schema,
  in_required: Bool,
  optionality: Optionality,
) -> Bool {
  case optionality {
    RequiredOnly -> !in_required
    NullableOnly -> is_nullable(prop_schema)
    RequiredAndNullable -> !in_required || is_nullable(prop_schema)
  }
}

fn is_nullable(s: Schema) -> Bool {
  case s {
    schema.Ref(_) -> False
    schema.String(base, _)
    | schema.Integer(base, _)
    | schema.Number(base)
    | schema.Boolean(base)
    | schema.Array(base, _)
    | schema.Object(base, _) -> base.nullable
  }
}

// --- Comments ----------------------------------------------------------------

fn base_schema_comment(base: BaseSchema) -> Option(Document) {
  case base.description {
    Some(desc) -> Some(description_to_comment(desc))
    None -> None
  }
}

fn schema_description(s: Schema) -> Option(Document) {
  case s {
    schema.Ref(_) -> None
    schema.String(base, _)
    | schema.Integer(base, _)
    | schema.Number(base)
    | schema.Boolean(base)
    | schema.Array(base, _)
    | schema.Object(base, _) -> base_schema_comment(base)
  }
}

fn description_to_comment(desc: String) -> Document {
  string.split(desc, "\n")
  |> list.map(fn(line) { doc.from_string("/// " <> string.trim(line)) })
  |> doc.join(with: doc.line)
}

// --- Naming helpers ----------------------------------------------------------

fn to_type_name(name: String) -> String {
  justin.pascal_case(name)
}

fn to_field_name(name: String) -> String {
  let snake = justin.snake_case(name)
  // Avoid Gleam keywords
  case snake {
    "type" -> "type_"
    "fn" -> "fn_"
    "let" -> "let_"
    "case" -> "case_"
    "use" -> "use_"
    "pub" -> "pub_"
    "import" -> "import_"
    "as" -> "as_"
    _ -> snake
  }
}

fn ref_to_type_name(ref: String) -> String {
  // Refs look like "#/components/schemas/Pet"
  case string.split(ref, "/") {
    [_, _, _, name, ..] -> to_type_name(name)
    _ -> to_type_name(ref)
  }
}
