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

const indent = 2

/// Generate Gleam source code for the schema types in an OpenAPI spec.
///
pub fn generate_schemas(spec: OpenAPI) -> String {
  let schemas = extract_schemas(spec)

  let type_docs =
    list.map(schemas, fn(entry) {
      let #(name, schema) = entry
      schema_to_type_doc(name, schema, schemas)
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
) -> Document {
  let type_name = to_type_name(name)
  case schema {
    schema.Object(base, object_schema) ->
      object_type_doc(type_name, base, object_schema, all_schemas)
    _ ->
      // For non-object top-level schemas, generate a type alias-like wrapper
      simple_type_doc(type_name, schema, all_schemas)
  }
}

fn object_type_doc(
  type_name: String,
  base: BaseSchema,
  object_schema: ObjectSchema,
  all_schemas: List(#(String, Schema)),
) -> Document {
  let comment = base_schema_comment(base)

  let fields =
    list.map(object_schema.properties, fn(prop) {
      let #(prop_name, prop_schema) = prop
      let field_name = to_field_name(prop_name)
      let is_required = list.contains(object_schema.required, prop_name)
      let field_type =
        schema_to_gleam_type(prop_schema, is_required, all_schemas)

      doc.concat([
        doc.from_string(field_name <> ": "),
        field_type,
      ])
    })

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
) -> Document {
  let gleam_type = schema_to_gleam_type(schema, True, all_schemas)
  doc.concat([
    doc.from_string("pub type " <> type_name <> " ="),
    doc.line |> doc.nest(by: indent),
    gleam_type |> doc.nest(by: indent),
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

// --- Comments ----------------------------------------------------------------

fn base_schema_comment(base: BaseSchema) -> Option(Document) {
  case base.description {
    Some(desc) -> {
      let lines =
        string.split(desc, "\n")
        |> list.map(fn(line) { doc.from_string("/// " <> string.trim(line)) })
      Some(doc.join(lines, with: doc.line))
    }
    None -> None
  }
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
