import gilly/openapi/openapi.{type OpenAPI}
import gilly/openapi/schema.{
  type ArraySchema, type BaseSchema, type ObjectSchema, type Schema,
  type StringSchema,
}
import glam/doc.{type Document}
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set.{type Set}
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

// --- State -------------------------------------------------------------------

type State {
  State(
    imports: Dict(String, Set(String)),
    /// Enums discovered during codegen, keyed by generated type name.
    /// Values are the original string variants from the OpenAPI spec.
    enums: Dict(String, List(String)),
  )
}

fn default_state() -> State {
  State(imports: dict.new(), enums: dict.new())
}

fn register_enum(
  state: State,
  type_name: String,
  variants: List(String),
) -> State {
  State(..state, enums: dict.insert(state.enums, type_name, variants))
}

fn import_qualified(state: State, module: String, imported: String) -> State {
  let imports =
    dict.upsert(state.imports, module, fn(existing) {
      case existing {
        Some(values) -> set.insert(values, imported)
        None -> set.from_list([imported])
      }
    })
  State(..state, imports:)
}

fn import_module(state: State, module: String) -> State {
  let imports = case dict.has_key(state.imports, module) {
    True -> state.imports
    False -> dict.insert(state.imports, module, set.new())
  }
  State(..state, imports:)
}

fn imports_doc(state: State, indent: Int) -> Document {
  let sorted_imports =
    dict.to_list(state.imports)
    |> list.sort(fn(a, b) { string.compare(a.0, b.0) })

  list.map(sorted_imports, fn(entry) {
    let #(module, qualified) = entry
    let import_line = doc.from_string("import " <> module)
    case set.to_list(qualified) {
      [] -> import_line
      values -> {
        let values_doc =
          list.sort(values, string.compare)
          |> list.map(doc.from_string)
          |> doc.join(with: doc.break(", ", ","))
          |> doc.group
        doc.concat([
          import_line,
          doc.from_string(".{"),
          doc.concat([doc.soft_break, values_doc])
            |> doc.group
            |> doc.nest(by: indent),
          doc.soft_break,
          doc.from_string("}"),
        ])
      }
    }
  })
  |> doc.join(with: doc.line)
}

// --- Public API --------------------------------------------------------------

/// Generate Gleam source code for the schema types in an OpenAPI spec.
///
pub fn generate_schemas(spec: OpenAPI, config: Config) -> String {
  let schemas = extract_schemas(spec)
  let state = default_state()

  let #(state, type_docs) =
    list.fold(schemas, #(state, []), fn(acc, entry) {
      let #(state, docs) = acc
      let #(name, schema) = entry
      let #(state, type_doc) =
        schema_to_type_doc(state, name, schema, schemas, config)
      #(state, [type_doc, ..docs])
    })
  let type_docs = list.reverse(type_docs)

  let types_code =
    doc.join(type_docs, with: doc.lines(2))
    |> doc.append(doc.line)

  // If we discovered any enums, register the decode import
  let state = case dict.is_empty(state.enums) {
    True -> state
    False ->
      state
      |> import_module("gleam/dynamic/decode")
  }

  let enums_code = case dict.is_empty(state.enums) {
    True -> doc.empty
    False ->
      doc.concat([
        doc.lines(2),
        separator_comment("Enums"),
        doc.lines(2),
        enums_doc(state, config.indent),
      ])
  }

  let code = case dict.is_empty(state.imports) {
    True -> doc.concat([types_code, enums_code])
    False ->
      doc.concat([
        imports_doc(state, config.indent),
        doc.lines(2),
        types_code,
        enums_code,
      ])
  }

  doc.to_string(code, 80)
}

fn extract_schemas(spec: OpenAPI) -> List(#(String, Schema)) {
  spec.components
  |> option.map(fn(c) { c.schemas })
  |> option.unwrap([])
}

// --- Type generation ---------------------------------------------------------

fn schema_to_type_doc(
  state: State,
  name: String,
  schema: Schema,
  all_schemas: List(#(String, Schema)),
  config: Config,
) -> #(State, Document) {
  let type_name = to_type_name(name)
  case schema {
    schema.Object(base, object_schema) ->
      object_type_doc(
        state,
        type_name,
        base,
        object_schema,
        all_schemas,
        config,
      )
    _ ->
      // For non-object top-level schemas, generate a type alias-like wrapper
      simple_type_doc(state, type_name, schema, all_schemas, config)
  }
}

fn object_type_doc(
  state: State,
  type_name: String,
  base: BaseSchema,
  object_schema: ObjectSchema,
  all_schemas: List(#(String, Schema)),
  config: Config,
) -> #(State, Document) {
  let comment = base_schema_comment(base)

  let #(state, fields) =
    list.fold(object_schema.properties, #(state, []), fn(acc, prop) {
      let #(state, fields) = acc
      let #(prop_name, prop_schema) = prop
      let field_name = to_field_name(prop_name)
      let in_required = list.contains(object_schema.required, prop_name)
      let optional =
        is_field_optional(prop_schema, in_required, config.optionality)
      let enum_hint = type_name <> to_type_name(prop_name)
      let #(state, field_type) =
        schema_to_gleam_type(
          state,
          prop_schema,
          !optional,
          all_schemas,
          enum_hint,
        )

      let field_line =
        doc.concat([
          doc.from_string(field_name <> ": "),
          field_type,
        ])

      let field_doc = case schema_description(prop_schema) {
        Some(comment) -> doc.concat([comment, doc.line, field_line])
        None -> field_line
      }

      #(state, [field_doc, ..fields])
    })
  let fields = list.reverse(fields)

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

  let result = case comment {
    Some(c) -> doc.concat([c, doc.line, body])
    None -> body
  }

  let #(state, decoder) =
    record_decoder_doc(state, type_name, object_schema, all_schemas, config)
  let result = doc.concat([result, doc.lines(2), decoder])

  #(state, result)
}

fn simple_type_doc(
  state: State,
  type_name: String,
  schema: Schema,
  all_schemas: List(#(String, Schema)),
  config: Config,
) -> #(State, Document) {
  let #(state, gleam_type) =
    schema_to_gleam_type(state, schema, True, all_schemas, type_name)
  let result =
    doc.concat([
      doc.from_string("pub type " <> type_name <> " ="),
      doc.line |> doc.nest(by: config.indent),
      gleam_type |> doc.nest(by: config.indent),
    ])
  #(state, result)
}

// --- Type mapping ------------------------------------------------------------

fn schema_to_gleam_type(
  state: State,
  schema: Schema,
  required: Bool,
  all_schemas: List(#(String, Schema)),
  enum_name_hint: String,
) -> #(State, Document) {
  let #(state, inner) = case schema {
    schema.Ref(ref:) -> #(state, doc.from_string(ref_to_type_name(ref)))
    schema.String(_, string_schema) ->
      string_type(state, string_schema, enum_name_hint)
    schema.Integer(_, _) -> #(state, doc.from_string("Int"))
    schema.Number(_) -> #(state, doc.from_string("Float"))
    schema.Boolean(_) -> #(state, doc.from_string("Bool"))
    schema.Array(_, array_schema) ->
      array_type(state, array_schema, all_schemas, enum_name_hint)
    schema.Object(_, object_schema) ->
      inline_object_type(state, object_schema, all_schemas)
  }

  case required {
    True -> #(state, inner)
    False -> wrap_optional(state, inner)
  }
}

fn string_type(
  state: State,
  string_schema: StringSchema,
  enum_name_hint: String,
) -> #(State, Document) {
  case string_schema.enum {
    Some(variants) -> {
      let type_name = to_type_name(enum_name_hint)
      let state = register_enum(state, type_name, variants)
      #(state, doc.from_string(type_name))
    }
    None ->
      case string_schema.format {
        Some("date-time") -> #(state, doc.from_string("String"))
        Some("binary") -> #(state, doc.from_string("BitArray"))
        _ -> #(state, doc.from_string("String"))
      }
  }
}

fn array_type(
  state: State,
  array_schema: ArraySchema,
  all_schemas: List(#(String, Schema)),
  enum_name_hint: String,
) -> #(State, Document) {
  let #(state, items_type) =
    schema_to_gleam_type(
      state,
      array_schema.items,
      True,
      all_schemas,
      enum_name_hint,
    )
  #(
    state,
    doc.concat([
      doc.from_string("List("),
      items_type,
      doc.from_string(")"),
    ]),
  )
}

fn inline_object_type(
  state: State,
  _object_schema: ObjectSchema,
  _all_schemas: List(#(String, Schema)),
) -> #(State, Document) {
  // For inline anonymous objects, fall back to a generic type
  let state = import_qualified(state, "gleam/dynamic", "type Dynamic")
  #(state, doc.from_string("Dynamic"))
}

fn wrap_optional(state: State, inner: Document) -> #(State, Document) {
  let state = import_qualified(state, "gleam/option", "type Option")
  #(
    state,
    doc.concat([
      doc.from_string("Option("),
      inner,
      doc.from_string(")"),
    ]),
  )
}

// --- Decoder mapping ---------------------------------------------------------

fn schema_to_inner_decoder(
  state: State,
  schema: Schema,
  all_schemas: List(#(String, Schema)),
  enum_name_hint: String,
) -> #(State, Document) {
  case schema {
    schema.Ref(ref:) -> ref_to_decoder(state, ref, all_schemas)
    schema.String(_, string_schema) ->
      string_decoder(state, string_schema, enum_name_hint)
    schema.Integer(_, _) -> #(state, doc.from_string("decode.int"))
    schema.Number(_) -> #(state, doc.from_string("decode.float"))
    schema.Boolean(_) -> #(state, doc.from_string("decode.bool"))
    schema.Array(_, array_schema) ->
      array_decoder(state, array_schema, all_schemas, enum_name_hint)
    schema.Object(_, _) -> #(state, doc.from_string("decode.dynamic"))
  }
}

fn string_decoder(
  state: State,
  string_schema: StringSchema,
  enum_name_hint: String,
) -> #(State, Document) {
  case string_schema.enum {
    Some(variants) -> {
      let type_name = to_type_name(enum_name_hint)
      let _ = variants
      let decoder_name = enum_decoder_name(type_name)
      #(state, doc.from_string(decoder_name <> "()"))
    }
    None ->
      case string_schema.format {
        Some("binary") -> #(state, doc.from_string("decode.bit_array"))
        _ -> #(state, doc.from_string("decode.string"))
      }
  }
}

fn array_decoder(
  state: State,
  array_schema: ArraySchema,
  all_schemas: List(#(String, Schema)),
  enum_name_hint: String,
) -> #(State, Document) {
  let #(state, items_decoder) =
    schema_to_inner_decoder(
      state,
      array_schema.items,
      all_schemas,
      enum_name_hint,
    )
  #(
    state,
    doc.concat([
      doc.from_string("decode.list("),
      items_decoder,
      doc.from_string(")"),
    ]),
  )
}

fn ref_to_decoder(
  state: State,
  ref: String,
  all_schemas: List(#(String, Schema)),
) -> #(State, Document) {
  let raw_name = case string.split(ref, "/") {
    [_, _, _, name, ..] -> name
    _ -> ref
  }
  let type_name = to_type_name(raw_name)
  case list.key_find(all_schemas, raw_name) {
    // Object types have their own decoder function
    Ok(schema.Object(_, _)) -> {
      let decoder_name = justin.snake_case(type_name) <> "_decoder()"
      #(state, doc.from_string(decoder_name))
    }
    // Other types: resolve the decoder inline
    Ok(schema) -> schema_to_inner_decoder(state, schema, all_schemas, type_name)
    // Unknown ref: dynamic fallback
    Error(_) -> #(state, doc.from_string("decode.dynamic"))
  }
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

/// Convert a variant string to a namespaced PascalCase constructor name.
/// Prefixed with the type name to avoid conflicts across enums.
fn enum_variant_name(type_name: String, variant: String) -> String {
  type_name <> justin.pascal_case(variant)
}

fn enum_decoder_name(type_name: String) -> String {
  justin.snake_case(type_name) <> "_decoder"
}

// --- Record decoder codegen --------------------------------------------------

fn record_decoder_doc(
  state: State,
  type_name: String,
  object_schema: ObjectSchema,
  all_schemas: List(#(String, Schema)),
  config: Config,
) -> #(State, Document) {
  let state = import_module(state, "gleam/dynamic/decode")
  let decoder_name = justin.snake_case(type_name) <> "_decoder"
  let indent = config.indent

  let #(state, field_lines) =
    list.fold(object_schema.properties, #(state, []), fn(acc, prop) {
      let #(state, lines) = acc
      let #(prop_name, prop_schema) = prop
      let field_name = to_field_name(prop_name)
      let in_required = list.contains(object_schema.required, prop_name)
      let optional =
        is_field_optional(prop_schema, in_required, config.optionality)
      let enum_hint = type_name <> to_type_name(prop_name)
      let #(state, inner_decoder) =
        schema_to_inner_decoder(state, prop_schema, all_schemas, enum_hint)

      let #(state, line) = case optional {
        False -> #(
          state,
          doc.concat([
            doc.from_string(
              "use "
              <> field_name
              <> " <- decode.field(\""
              <> prop_name
              <> "\", ",
            ),
            inner_decoder,
            doc.from_string(")"),
          ]),
        )
        True -> {
          let state = import_qualified(state, "gleam/option", "None")
          #(
            state,
            doc.concat([
              doc.from_string(
                "use "
                <> field_name
                <> " <- decode.optional_field(\""
                <> prop_name
                <> "\", None, decode.optional(",
              ),
              inner_decoder,
              doc.from_string("))"),
            ]),
          )
        }
      }

      #(state, [line, ..lines])
    })
  let field_lines = list.reverse(field_lines)

  let labels =
    list.map(object_schema.properties, fn(prop) { to_field_name(prop.0) <> ":" })
  let success_line = case labels {
    [] -> doc.from_string("decode.success(" <> type_name <> ")")
    _ ->
      doc.from_string(
        "decode.success("
        <> type_name
        <> "("
        <> string.join(labels, ", ")
        <> "))",
      )
  }

  let body_lines = list.append(field_lines, [success_line])
  let return_type = doc.from_string("decode.Decoder(" <> type_name <> ")")

  let result =
    doc.concat([
      doc.from_string("pub fn " <> decoder_name <> "() -> "),
      return_type,
      doc.from_string(" {"),
      doc.line |> doc.nest(by: indent),
      doc.join(body_lines, with: doc.line) |> doc.nest(by: indent),
      doc.line,
      doc.from_string("}"),
    ])

  #(state, result)
}

// --- Enum codegen ------------------------------------------------------------

fn separator_comment(value: String) -> Document {
  string.pad_end("// --- " <> value <> " ", to: 80, with: "-")
  |> doc.from_string
}

fn enums_doc(state: State, indent: Int) -> Document {
  let sorted_enums =
    dict.to_list(state.enums)
    |> list.sort(fn(a, b) { string.compare(a.0, b.0) })

  list.map(sorted_enums, fn(entry) {
    let #(type_name, variants) = entry
    doc.concat([
      enum_type_doc(type_name, variants, indent),
      doc.lines(2),
      enum_decoder_doc(type_name, variants, indent),
    ])
  })
  |> doc.join(with: doc.lines(2))
}

fn enum_type_doc(
  type_name: String,
  variants: List(String),
  indent: Int,
) -> Document {
  let variant_docs =
    list.map(variants, fn(v) {
      doc.from_string(enum_variant_name(type_name, v))
    })

  doc.concat([
    doc.from_string("pub type " <> type_name <> " {"),
    doc.line |> doc.nest(by: indent),
    doc.join(variant_docs, with: doc.line)
      |> doc.nest(by: indent),
    doc.line,
    doc.from_string("}"),
  ])
}

fn enum_decoder_doc(
  type_name: String,
  variants: List(String),
  indent: Int,
) -> Document {
  let decoder_name = enum_decoder_name(type_name)
  let var_name = "value"

  let success_cases =
    list.map(variants, fn(v) {
      doc.concat([
        doc.from_string("\"" <> v <> "\" -> "),
        doc.from_string(
          "decode.success(" <> enum_variant_name(type_name, v) <> ")",
        ),
      ])
    })

  let first_variant = case variants {
    [first, ..] -> enum_variant_name(type_name, first)
    [] -> "Nil"
  }

  let failure_case =
    doc.concat([
      doc.from_string("_ -> "),
      doc.from_string(
        "decode.failure(" <> first_variant <> ", \"" <> type_name <> "\")",
      ),
    ])

  let case_body = list.append(success_cases, [failure_case])

  let case_block =
    doc.concat([
      doc.from_string("case " <> var_name <> " {"),
      doc.line |> doc.nest(by: indent),
      doc.join(case_body, with: doc.line)
        |> doc.nest(by: indent),
      doc.line,
      doc.from_string("}"),
    ])

  let fn_body =
    doc.concat([
      doc.from_string("use " <> var_name <> " <- decode.then(decode.string)"),
      doc.line,
      case_block,
    ])

  let return_type = doc.from_string("decode.Decoder(" <> type_name <> ")")

  doc.concat([
    doc.from_string("pub fn " <> decoder_name <> "() -> "),
    return_type,
    doc.from_string(" {"),
    doc.line |> doc.nest(by: indent),
    fn_body |> doc.nest(by: indent),
    doc.line,
    doc.from_string("}"),
  ])
}
