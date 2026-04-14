import glam/doc.{type Document}
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set.{type Set}
import gleam/string

import justin

import gilly/common.{type Optionality}
import gilly/openapi/openapi.{type OpenAPI, type PathItem}
import gilly/openapi/operation.{type Operation, type Parameter, Path, Query}
import gilly/openapi/schema.{
  type ArraySchema, type BaseSchema, type ObjectSchema, type Schema,
  type StringSchema,
}

/// Configuration for the code generator.
///
pub type Config {
  Config(
    optionality: Optionality,
    indent: Int,
    optional_query_params: Bool,
    client_default_parameters: List(String),
  )
}

/// Tracks how a schema is referenced by operations.
///
pub type SchemaUsage {
  /// Only referenced in request bodies → opaque type + new + with_XXX setters.
  RequestOnly
  /// Only referenced in responses → non-opaque, no setters needed.
  ResponseOnly
  /// Referenced in both requests and responses → generate everything.
  Both
  /// Not referenced by any operation → generate everything (safe default).
  Unreferenced
}

// --- State -------------------------------------------------------------------

type State {
  State(
    imports: Dict(String, Set(String)),
    /// Enums discovered during codegen, keyed by generated type name.
    /// Values are the original string variants from the OpenAPI spec.
    enums: Dict(String, List(String)),
    /// Tracks how each schema is referenced by operations.
    /// Keyed by the raw schema name from the OpenAPI spec.
    schema_usages: Dict(String, SchemaUsage),
  )
}

fn default_state() -> State {
  State(imports: dict.new(), enums: dict.new(), schema_usages: dict.new())
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

/// Generate Gleam source code for both schema types and operations from an
/// OpenAPI spec, with a single shared import block.
///
pub fn generate(spec: OpenAPI, config: Config) -> String {
  let schemas = extract_schemas(spec)
  let state = default_state()

  // Pre-scan operations to track how schemas are used (request/response/both)
  let schema_usages = collect_schema_usages(spec)
  let state = State(..state, schema_usages:)

  // 1. Generate schema types
  let #(state, type_docs) = generate_schema_docs(state, schemas, config)

  let types_code =
    doc.join(type_docs, with: doc.lines(2))
    |> doc.append(doc.line)

  // Register enum imports if needed
  let state = case dict.is_empty(state.enums) {
    True -> state
    False ->
      state
      |> import_module("gleam/dynamic/decode")
      |> import_module("gleam/json")
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

  // 2. Generate operations
  let #(state, op_docs) = generate_operation_docs(state, spec, schemas, config)

  let ops_code = case op_docs {
    [] -> doc.empty
    _ -> {
      let base_url = default_base_url(spec)
      let default_params = config.client_default_parameters
      let client_param_setters =
        client_default_param_setters(config.indent, default_params)
      doc.concat(
        list.flatten([
          [
            doc.lines(2),
            separator_comment("Operations"),
            doc.lines(2),
            api_error_doc(config.indent),
            doc.lines(2),
            client_type_doc(
              config.indent,
              spec.info.description,
              default_params,
            ),
            doc.lines(2),
            client_new_doc(config.indent, base_url, default_params),
            doc.lines(2),
            client_with_base_url_doc(config.indent),
          ],
          list.map(client_param_setters, fn(d) { doc.concat([doc.lines(2), d]) }),
          [
            doc.lines(2),
            doc.join(op_docs, with: doc.lines(2)),
            doc.line,
          ],
        ]),
      )
    }
  }

  // 3. Assemble with single import block
  let code = case dict.is_empty(state.imports) {
    True -> doc.concat([types_code, enums_code, ops_code])
    False ->
      doc.concat([
        imports_doc(state, config.indent),
        doc.lines(2),
        types_code,
        enums_code,
        ops_code,
      ])
  }

  doc.to_string(code, 80)
}

/// Generate Gleam source code for the schema types in an OpenAPI spec.
///
pub fn generate_schemas(spec: OpenAPI, config: Config) -> String {
  let schemas = extract_schemas(spec)
  let state = default_state()

  let #(state, type_docs) = generate_schema_docs(state, schemas, config)

  let types_code =
    doc.join(type_docs, with: doc.lines(2))
    |> doc.append(doc.line)

  // If we discovered any enums, register the decode and json imports
  let state = case dict.is_empty(state.enums) {
    True -> state
    False ->
      state
      |> import_module("gleam/dynamic/decode")
      |> import_module("gleam/json")
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

/// Generate Gleam source code for the operations (API client functions) in an
/// OpenAPI spec. Each operation becomes a function that takes a generic HTTP
/// client callback, enabling any HTTP library to be used.
///
pub fn generate_operations(spec: OpenAPI, config: Config) -> String {
  let schemas = extract_schemas(spec)
  let state = default_state()

  let #(state, op_docs) = generate_operation_docs(state, spec, schemas, config)

  let code = case op_docs {
    [] -> doc.empty
    _ -> {
      let base_url = default_base_url(spec)
      let default_params = config.client_default_parameters
      let client_param_setters =
        client_default_param_setters(config.indent, default_params)
      doc.concat(
        list.flatten([
          [
            imports_doc(state, config.indent),
            doc.lines(2),
            api_error_doc(config.indent),
            doc.lines(2),
            client_type_doc(
              config.indent,
              spec.info.description,
              default_params,
            ),
            doc.lines(2),
            client_new_doc(config.indent, base_url, default_params),
            doc.lines(2),
            client_with_base_url_doc(config.indent),
          ],
          list.map(client_param_setters, fn(d) { doc.concat([doc.lines(2), d]) }),
          [
            doc.lines(2),
            doc.join(op_docs, with: doc.lines(2)),
            doc.line,
          ],
        ]),
      )
    }
  }

  doc.to_string(code, 80)
}

fn generate_schema_docs(
  state: State,
  schemas: List(#(String, Schema)),
  config: Config,
) -> #(State, List(Document)) {
  let #(state, type_docs) =
    list.fold(schemas, #(state, []), fn(acc, entry) {
      let #(state, docs) = acc
      let #(name, schema) = entry
      let #(state, type_doc) =
        schema_to_type_doc(state, name, schema, schemas, config)
      #(state, [type_doc, ..docs])
    })
  #(state, list.reverse(type_docs))
}

fn generate_operation_docs(
  state: State,
  spec: OpenAPI,
  schemas: List(#(String, Schema)),
  config: Config,
) -> #(State, List(Document)) {
  let state = import_module(state, "gleam/http/request")
  let state = import_module(state, "gleam/http/response")
  let state = import_module(state, "gleam/http")
  let state = import_module(state, "gleam/result")

  list.fold(spec.paths, #(state, []), fn(acc, path_entry) {
    let #(state, docs) = acc
    let #(path, path_item) = path_entry
    let #(state, path_docs) =
      path_item_to_docs(state, path, path_item, schemas, config)
    #(state, list.append(docs, path_docs))
  })
}

fn extract_schemas(spec: OpenAPI) -> List(#(String, Schema)) {
  spec.components
  |> option.map(fn(c) { c.schemas })
  |> option.unwrap([])
}

// --- Schema usage tracking ---------------------------------------------------

/// Extract the raw schema name from a $ref string like "#/components/schemas/Pet".
fn ref_to_raw_name(ref: String) -> Option(String) {
  case string.split(ref, "/") {
    [_, _, _, name, ..] -> Some(name)
    _ -> None
  }
}

/// Merge a new usage signal into an existing one.
fn merge_usage(existing: SchemaUsage, new: SchemaUsage) -> SchemaUsage {
  case existing, new {
    Both, _ | _, Both -> Both
    RequestOnly, ResponseOnly | ResponseOnly, RequestOnly -> Both
    RequestOnly, RequestOnly -> RequestOnly
    ResponseOnly, ResponseOnly -> ResponseOnly
    Unreferenced, other | other, Unreferenced -> other
  }
}

/// Record that a schema ref is used in a particular context (request or response).
fn record_schema_ref(
  usages: Dict(String, SchemaUsage),
  schema: Schema,
  usage: SchemaUsage,
) -> Dict(String, SchemaUsage) {
  case schema {
    schema.Ref(ref:) ->
      case ref_to_raw_name(ref) {
        Some(name) ->
          dict.upsert(usages, name, fn(existing) {
            case existing {
              Some(prev) -> merge_usage(prev, usage)
              None -> usage
            }
          })
        None -> usages
      }
    _ -> usages
  }
}

/// Pre-scan all operations to build a map of schema name → SchemaUsage.
fn collect_schema_usages(spec: OpenAPI) -> Dict(String, SchemaUsage) {
  list.fold(spec.paths, dict.new(), fn(usages, path_entry) {
    let #(_path, path_item) = path_entry
    let operations =
      [
        path_item.get,
        path_item.post,
        path_item.put,
        path_item.delete,
        path_item.patch,
      ]
      |> list.filter_map(fn(op) {
        case op {
          Some(o) -> Ok(o)
          None -> Error(Nil)
        }
      })
    list.fold(operations, usages, fn(usages, op) {
      collect_operation_usages(usages, op)
    })
  })
}

fn collect_operation_usages(
  usages: Dict(String, SchemaUsage),
  op: Operation,
) -> Dict(String, SchemaUsage) {
  // Track request body schema refs
  let usages = case op.request_body {
    Some(rb) ->
      case list.key_find(rb.content, "application/json") {
        Ok(media_type) ->
          case media_type.schema {
            Some(body_schema) ->
              record_schema_ref(usages, body_schema, RequestOnly)
            None -> usages
          }
        Error(_) -> usages
      }
    None -> usages
  }

  // Track response schema refs (try 200, 201, default)
  let response =
    list.key_find(op.responses, "200")
    |> result_or(fn() { list.key_find(op.responses, "201") })
    |> result_or(fn() { list.key_find(op.responses, "default") })

  case response {
    Ok(resp) ->
      case list.key_find(resp.content, "application/json") {
        Ok(media_type) ->
          case media_type.schema {
            Some(resp_schema) ->
              record_schema_ref(usages, resp_schema, ResponseOnly)
            None -> usages
          }
        Error(_) -> usages
      }
    Error(_) -> usages
  }
}

/// Look up the usage for a schema by its raw name.
fn get_schema_usage(state: State, raw_name: String) -> SchemaUsage {
  case dict.get(state.schema_usages, raw_name) {
    Ok(usage) -> usage
    Error(_) -> Unreferenced
  }
}

// --- Operation generation ----------------------------------------------------

fn api_error_doc(indent: Int) -> Document {
  doc.concat([
    doc.from_string("pub type ApiError(err) {"),
    doc.line |> doc.nest(by: indent),
    doc.from_string("JsonDecodeError(json.DecodeError)")
      |> doc.nest(by: indent),
    doc.line |> doc.nest(by: indent),
    doc.from_string("ClientError(err)") |> doc.nest(by: indent),
    doc.line,
    doc.from_string("}"),
  ])
}

fn client_type_doc(
  indent: Int,
  description: Option(String),
  default_params: List(String),
) -> Document {
  let comment = case description {
    Some(desc) -> doc.concat([description_to_comment(desc), doc.line])
    None -> doc.empty
  }
  let extra_fields =
    list.map(default_params, fn(name) {
      doc.concat([
        doc.line |> doc.nest(by: indent * 2),
        doc.from_string(to_field_name(name) <> ": String,")
          |> doc.nest(by: indent * 2),
      ])
    })
  doc.concat(
    list.flatten([
      [
        comment,
        doc.from_string("pub opaque type Client(err) {"),
        doc.line |> doc.nest(by: indent),
        doc.from_string("Client(")
          |> doc.nest(by: indent),
        doc.line |> doc.nest(by: indent * 2),
        doc.from_string(
          "http_client: fn(request.Request(String)) -> Result(response.Response(String), err),",
        )
          |> doc.nest(by: indent * 2),
        doc.line |> doc.nest(by: indent * 2),
        doc.from_string("base_url: String,")
          |> doc.nest(by: indent * 2),
      ],
      extra_fields,
      [
        doc.line |> doc.nest(by: indent),
        doc.from_string(")")
          |> doc.nest(by: indent),
        doc.line,
        doc.from_string("}"),
      ],
    ]),
  )
}

fn client_new_doc(
  indent: Int,
  default_base_url: Option(String),
  default_params: List(String),
) -> Document {
  let base_url_default = case default_base_url {
    Some(url) -> "\"" <> url <> "\""
    None -> "\"\""
  }

  let extra_args =
    list.map(default_params, fn(name) {
      let field_name = to_field_name(name)
      doc.concat([
        doc.line |> doc.nest(by: indent),
        doc.from_string(field_name <> " " <> field_name <> ": String,")
          |> doc.nest(by: indent),
      ])
    })
  let extra_inits =
    list.map(default_params, fn(name) { to_field_name(name) <> ":" })
  let all_inits =
    ["http_client:", "base_url: " <> base_url_default]
    |> list.append(extra_inits)

  doc.concat(
    list.flatten([
      [
        doc.from_string("pub fn new("),
        doc.line |> doc.nest(by: indent),
        doc.from_string(
          "http_client: fn(request.Request(String)) -> Result(response.Response(String), err),",
        )
          |> doc.nest(by: indent),
      ],
      extra_args,
      [
        doc.line,
        doc.from_string(") -> Client(err) {"),
        doc.line |> doc.nest(by: indent),
        doc.from_string("Client(" <> string.join(all_inits, ", ") <> ")")
          |> doc.nest(by: indent),
        doc.line,
        doc.from_string("}"),
      ],
    ]),
  )
}

fn client_with_base_url_doc(indent: Int) -> Document {
  doc.concat([
    doc.from_string("pub fn with_base_url("),
    doc.line |> doc.nest(by: indent),
    doc.from_string("client: Client(err),")
      |> doc.nest(by: indent),
    doc.line |> doc.nest(by: indent),
    doc.from_string("base_url: String,")
      |> doc.nest(by: indent),
    doc.line,
    doc.from_string(") -> Client(err) {"),
    doc.line |> doc.nest(by: indent),
    doc.from_string("Client(..client, base_url:)")
      |> doc.nest(by: indent),
    doc.line,
    doc.from_string("}"),
  ])
}

fn client_default_param_setters(
  indent: Int,
  default_params: List(String),
) -> List(Document) {
  list.map(default_params, fn(name) {
    let field_name = to_field_name(name)
    doc.concat([
      doc.from_string("pub fn with_" <> field_name <> "("),
      doc.line |> doc.nest(by: indent),
      doc.from_string("client: Client(err),")
        |> doc.nest(by: indent),
      doc.line |> doc.nest(by: indent),
      doc.from_string(field_name <> " " <> field_name <> ": String,")
        |> doc.nest(by: indent),
      doc.line,
      doc.from_string(") -> Client(err) {"),
      doc.line |> doc.nest(by: indent),
      doc.from_string("Client(..client, " <> field_name <> ":)")
        |> doc.nest(by: indent),
      doc.line,
      doc.from_string("}"),
    ])
  })
}

fn default_base_url(spec: OpenAPI) -> Option(String) {
  case spec.servers {
    [first, ..] -> Some(first.url)
    [] -> None
  }
}

fn path_item_to_docs(
  state: State,
  path: String,
  path_item: PathItem,
  all_schemas: List(#(String, Schema)),
  config: Config,
) -> #(State, List(Document)) {
  let methods = [
    #("Get", path_item.get),
    #("Post", path_item.post),
    #("Put", path_item.put),
    #("Delete", path_item.delete),
    #("Patch", path_item.patch),
  ]

  list.fold(methods, #(state, []), fn(acc, method_entry) {
    let #(state, docs) = acc
    let #(method, op) = method_entry
    case op {
      Some(operation) -> {
        let #(state, op_doc) =
          operation_doc(state, path, method, operation, all_schemas, config)
        #(state, list.append(docs, [op_doc]))
      }
      None -> #(state, docs)
    }
  })
}

/// Describes the kind of request body an operation has.
type BodyInfo {
  NoBody
  RefBody(type_doc: Document, schema: Schema)
  InlineBody(base: BaseSchema, obj_schema: ObjectSchema)
}

fn operation_doc(
  state: State,
  path: String,
  method: String,
  op: Operation,
  all_schemas: List(#(String, Schema)),
  config: Config,
) -> #(State, Document) {
  let indent = config.indent
  let fn_name = operation_fn_name(op, path, method)
  let request_type_name = to_type_name(fn_name) <> "Request"

  // Separate path and query parameters
  let path_params = list.filter(op.parameters, fn(p) { p.in_ == Path })
  let query_params =
    list.filter(op.parameters, fn(p) { p.in_ == Query })
    |> list.map(fn(p) {
      case config.optional_query_params {
        True -> operation.Parameter(..p, required: False)
        False -> p
      }
    })

  // Determine which params are promoted to the Client via client_default_parameters.
  // Promoted params become optional on the Request (with a setter override).
  let promoted_set = set.from_list(config.client_default_parameters)
  let promoted_path_params =
    list.filter(path_params, fn(p) { set.contains(promoted_set, p.name) })
  let promoted_query_params =
    list.filter(query_params, fn(p) { set.contains(promoted_set, p.name) })

  // Make promoted params optional on the Request type
  let path_params_for_request =
    list.map(path_params, fn(p) {
      case set.contains(promoted_set, p.name) {
        True -> operation.Parameter(..p, required: False)
        False -> p
      }
    })
  let query_params_for_request =
    list.map(query_params, fn(p) {
      case set.contains(promoted_set, p.name) && p.required {
        True -> operation.Parameter(..p, required: False)
        False -> p
      }
    })

  let has_params = !list.is_empty(path_params) || !list.is_empty(query_params)

  // Determine body kind: None, $ref, or inline object
  let #(state, body_info) = case op.request_body {
    Some(rb) -> {
      let #(state, param) = request_body_param(state, rb, all_schemas)
      case param {
        Some(#(_arg_name, _type_doc, schema.Object(base, obj_schema))) -> #(
          state,
          InlineBody(base, obj_schema),
        )
        Some(#(_arg_name, type_doc, schema)) -> #(
          state,
          RefBody(type_doc, schema),
        )
        None -> #(state, NoBody)
      }
    }
    None -> #(state, NoBody)
  }

  // Determine which body fields are promoted to the Client
  let promoted_body_field_names = case body_info {
    InlineBody(_base, obj_schema) ->
      list.filter(config.client_default_parameters, fn(name) {
        list.any(obj_schema.properties, fn(prop) { prop.0 == name })
      })
    _ -> []
  }

  // Collect all promoted names (params + body fields) for merge line generation
  let all_promoted_names =
    list.append(
      list.map(list.append(promoted_path_params, promoted_query_params), fn(p) {
        p.name
      }),
      promoted_body_field_names,
    )

  // Build the response type from the 200/201 response
  let #(state, response_type) = response_type_from_op(state, op, all_schemas)

  // Generate request type and determine function arguments + body accessor
  // Uses "request params:" label trick: external label is "request" (for callers),
  // internal variable is "params" (avoids shadowing gleam/http/request module).
  let #(state, request_docs, all_args, body_param, params_prefix, all_schemas) = case
    body_info,
    has_params
  {
    // Case A: No body, no params → fn(client)
    NoBody, False -> #(
      state,
      [],
      [doc.from_string("client client: Client(err)")],
      None,
      "",
      all_schemas,
    )

    // Case B: No body, has params → generate XxxRequest from params
    NoBody, True -> {
      let #(state, docs) =
        operation_request_docs(
          state,
          request_type_name,
          path_params_for_request,
          query_params_for_request,
          None,
          all_schemas,
          config,
        )
      #(
        state,
        docs,
        [
          doc.from_string("request params: " <> request_type_name),
          doc.from_string("client client: Client(err)"),
        ],
        None,
        "params.",
        all_schemas,
      )
    }

    // Case C: $ref body, no params → fn(body, client)
    RefBody(type_doc, body_schema), False -> #(
      state,
      [],
      [
        doc.concat([doc.from_string("body: "), type_doc]),
        doc.from_string("client client: Client(err)"),
      ],
      Some(#("body", type_doc, body_schema)),
      "",
      all_schemas,
    )

    // Case D: $ref body, has params → wrapper XxxRequest with params + body field
    RefBody(type_doc, body_schema), True -> {
      let #(state, docs) =
        operation_request_docs(
          state,
          request_type_name,
          path_params_for_request,
          query_params_for_request,
          Some(#("body", type_doc)),
          all_schemas,
          config,
        )
      // body_param accessor is "params.body" since the body is a field on the request
      let ref_schema = body_schema
      #(
        state,
        docs,
        [
          doc.from_string("request params: " <> request_type_name),
          doc.from_string("client client: Client(err)"),
        ],
        Some(#("params.body", type_doc, ref_schema)),
        "params.",
        all_schemas,
      )
    }

    // Case E: Inline body, no params → generate XxxRequest from body schema
    InlineBody(base, obj_schema), False -> {
      let #(state, docs, all_schemas) =
        operation_inline_body_request_docs(
          state,
          request_type_name,
          [],
          [],
          base,
          obj_schema,
          all_schemas,
          config,
          promoted_set,
        )
      // Body is the request itself, encoded via xxx_to_json(params)
      let ref_schema =
        schema.Ref(ref: "#/components/schemas/" <> request_type_name)
      #(
        state,
        docs,
        [
          doc.from_string("request params: " <> request_type_name),
          doc.from_string("client client: Client(err)"),
        ],
        Some(#("params", doc.from_string(request_type_name), ref_schema)),
        "params.",
        all_schemas,
      )
    }

    // Case F: Inline body, has params → merge params + body into XxxRequest
    InlineBody(base, obj_schema), True -> {
      let #(state, docs, all_schemas) =
        operation_inline_body_request_docs(
          state,
          request_type_name,
          path_params_for_request,
          query_params_for_request,
          base,
          obj_schema,
          all_schemas,
          config,
          promoted_set,
        )
      // Body is the request itself, encoded via xxx_to_json(params)
      let ref_schema =
        schema.Ref(ref: "#/components/schemas/" <> request_type_name)
      #(
        state,
        docs,
        [
          doc.from_string("request params: " <> request_type_name),
          doc.from_string("client client: Client(err)"),
        ],
        Some(#("params", doc.from_string(request_type_name), ref_schema)),
        "params.",
        all_schemas,
      )
    }
  }

  // Build merge lines for promoted (client_default) params and body fields:
  // let region = option.unwrap(params.region, client.region)
  let merge_lines = case all_promoted_names {
    [] -> []
    _ -> {
      list.map(all_promoted_names, fn(name) {
        let field_name = to_field_name(name)
        doc.from_string(
          "let "
          <> field_name
          <> " = option.unwrap("
          <> params_prefix
          <> field_name
          <> ", client."
          <> field_name
          <> ")",
        )
      })
    }
  }

  // Build update line to write resolved promoted body fields back into params
  // before JSON serialization: let params = XxxRequest(..params, field: Some(field))
  let body_update_lines = case promoted_body_field_names {
    [] -> []
    _ -> {
      let field_updates =
        list.map(promoted_body_field_names, fn(name) {
          let field_name = to_field_name(name)
          field_name <> ": Some(" <> field_name <> ")"
        })
      [
        doc.from_string(
          "let params = "
          <> request_type_name
          <> "(..params, "
          <> string.join(field_updates, ", ")
          <> ")",
        ),
      ]
    }
  }

  // Import gleam/option if there are promoted params/fields (for option.unwrap)
  let state = case all_promoted_names {
    [] -> state
    _ ->
      state
      |> import_module("gleam/option")
  }
  // Import Some for body update lines
  let state = case promoted_body_field_names {
    [] -> state
    _ ->
      state
      |> import_qualified("gleam/option", "Some")
  }

  // Build URL expression with path parameter substitution
  let url_expr =
    build_url_expression(path, path_params, params_prefix, promoted_set)

  // Build the function body
  let state = import_module(state, "gleam/dynamic/decode")
  let state = import_module(state, "gleam/json")

  // Import gleam/int if any path param is an integer
  let has_int_path_param =
    list.any(path_params, fn(p) {
      case p.schema {
        Some(schema.Integer(_, _)) -> True
        _ -> False
      }
    })
  // Also import gleam/int if any query param is an integer
  let has_int_query_param =
    list.any(query_params, fn(p) {
      case p.schema {
        Some(schema.Integer(_, _)) -> True
        _ -> False
      }
    })
  let state = case has_int_path_param || has_int_query_param {
    True -> import_module(state, "gleam/int")
    False -> state
  }

  // Import gleam/option and gleam/list if any query param is optional
  let has_optional_query = list.any(query_params, fn(p) { !p.required })
  let state = case has_optional_query {
    True ->
      state
      |> import_module("gleam/option")
      |> import_module("gleam/list")
    False -> state
  }

  let req_lines =
    build_request_lines(
      state,
      method,
      query_params,
      body_param,
      all_schemas,
      params_prefix,
      promoted_set,
    )

  let #(state, decode_line) =
    build_decode_line(state, response_type, all_schemas)

  let body_lines =
    list.flatten([
      merge_lines,
      body_update_lines,
      [url_expr],
      req_lines,
      [decode_line],
    ])

  // Build return type
  let return_type = case response_type {
    Some(#(type_doc, _schema)) ->
      doc.concat([
        doc.from_string("Result("),
        type_doc,
        doc.from_string(", ApiError(err))"),
      ])
    None -> doc.from_string("Result(Nil, ApiError(err))")
  }

  // Add description comment
  let comment = case op.summary {
    Some(summary) ->
      doc.concat([
        doc.from_string("/// " <> summary),
        doc.line,
      ])
    None ->
      case op.description {
        Some(desc) ->
          doc.concat([
            description_to_comment(desc),
            doc.line,
          ])
        None -> doc.empty
      }
  }

  let fn_doc =
    doc.concat([
      comment,
      doc.from_string("pub fn " <> fn_name <> "("),
      doc.line |> doc.nest(by: indent),
      doc.join(all_args, with: doc.concat([doc.from_string(","), doc.line]))
        |> doc.nest(by: indent),
      doc.concat([doc.from_string(","), doc.line]),
      doc.from_string(") -> "),
      return_type,
      doc.from_string(" {"),
      doc.line |> doc.nest(by: indent),
      doc.join(body_lines, with: doc.line)
        |> doc.nest(by: indent),
      doc.line,
      doc.from_string("}"),
    ])

  // Prepend request type docs, then the function
  let full_doc = case request_docs {
    [] -> fn_doc
    _ ->
      doc.concat([
        doc.join(request_docs, with: doc.lines(2)),
        doc.lines(2),
        fn_doc,
      ])
  }

  #(state, full_doc)
}

/// Generate the Request type, new_ constructor, and with_ setters for an operation's
/// path and query parameters, optionally including a body $ref field.
fn operation_request_docs(
  state: State,
  type_name: String,
  path_params: List(Parameter),
  query_params: List(Parameter),
  body_ref: Option(#(String, Document)),
  all_schemas: List(#(String, Schema)),
  config: Config,
) -> #(State, List(Document)) {
  let indent = config.indent

  // Build field entries: path params are always required, query params depend on config
  let all_params = list.append(path_params, query_params)

  // Build field definitions for the type
  let #(state, fields) =
    list.fold(all_params, #(state, []), fn(acc, param) {
      let #(state, fields) = acc
      let field_name = to_field_name(param.name)
      let #(state, type_doc) = param_to_type(state, param, all_schemas)
      let field_doc = case param.required {
        True -> doc.concat([doc.from_string(field_name <> ": "), type_doc])
        False ->
          doc.concat([
            doc.from_string(field_name <> ": Option("),
            type_doc,
            doc.from_string(")"),
          ])
      }
      #(state, list.append(fields, [field_doc]))
    })

  // Add body $ref field if present (always required)
  let fields = case body_ref {
    Some(#(name, btype_doc)) -> {
      let field_doc =
        doc.concat([doc.from_string(to_field_name(name) <> ": "), btype_doc])
      list.append(fields, [field_doc])
    }
    None -> fields
  }

  // Import Option type if there are optional params
  let has_optional = list.any(all_params, fn(p) { !p.required })
  let state = case has_optional {
    True -> import_qualified(state, "gleam/option", "type Option")
    False -> state
  }

  // Type definition
  let type_doc = case fields {
    [] ->
      doc.concat([
        doc.from_string("pub opaque type " <> type_name <> " {"),
        doc.line |> doc.nest(by: indent),
        doc.from_string(type_name)
          |> doc.nest(by: indent),
        doc.line,
        doc.from_string("}"),
      ])
    _ ->
      doc.concat([
        doc.from_string("pub opaque type " <> type_name <> " {"),
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

  // Constructor: takes required params (path params + required query params) + body ref
  let required_params = list.filter(all_params, fn(p) { p.required })
  let optional_params = list.filter(all_params, fn(p) { !p.required })

  let state = case list.is_empty(optional_params) {
    True -> state
    False -> import_qualified(state, "gleam/option", "None")
  }

  let #(state, required_args) =
    list.fold(required_params, #(state, []), fn(acc, param) {
      let #(state, args) = acc
      let field_name = to_field_name(param.name)
      let #(state, type_doc) = param_to_type(state, param, all_schemas)
      let arg =
        doc.concat([
          doc.from_string(field_name <> " " <> field_name <> ": "),
          type_doc,
        ])
      #(state, list.append(args, [arg]))
    })

  // Add body ref as a required constructor arg
  let required_args = case body_ref {
    Some(#(name, btype_doc)) -> {
      let arg =
        doc.concat([
          doc.from_string(
            to_field_name(name) <> " " <> to_field_name(name) <> ": ",
          ),
          btype_doc,
        ])
      list.append(required_args, [arg])
    }
    None -> required_args
  }

  let field_inits =
    list.map(all_params, fn(param) {
      let field_name = to_field_name(param.name)
      case param.required {
        True -> field_name <> ":"
        False -> field_name <> ": None"
      }
    })

  // Add body ref field init
  let field_inits = case body_ref {
    Some(#(name, _)) -> list.append(field_inits, [to_field_name(name) <> ":"])
    None -> field_inits
  }

  let constructor_body =
    doc.from_string(type_name <> "(" <> string.join(field_inits, ", ") <> ")")

  let fn_name = "new_" <> justin.snake_case(type_name)
  let constructor_doc = case required_args {
    [] ->
      doc.concat([
        doc.from_string("pub fn " <> fn_name <> "() -> " <> type_name <> " {"),
        doc.line |> doc.nest(by: indent),
        constructor_body |> doc.nest(by: indent),
        doc.line,
        doc.from_string("}"),
      ])
    _ ->
      doc.concat([
        doc.from_string("pub fn " <> fn_name <> "("),
        doc.line |> doc.nest(by: indent),
        doc.join(
          required_args,
          with: doc.concat([doc.from_string(","), doc.line]),
        )
          |> doc.nest(by: indent),
        doc.concat([doc.from_string(","), doc.line]),
        doc.from_string(") -> " <> type_name <> " {"),
        doc.line |> doc.nest(by: indent),
        constructor_body |> doc.nest(by: indent),
        doc.line,
        doc.from_string("}"),
      ])
  }

  // Generate with_ setters for optional params
  let var_name = justin.snake_case(type_name)
  let #(state, setters) =
    list.fold(optional_params, #(state, []), fn(acc, param) {
      let #(state, setters) = acc
      let field_name = to_field_name(param.name)
      let setter_fn_name =
        justin.snake_case(type_name) <> "_with_" <> field_name

      let #(state, inner_type) = param_to_type(state, param, all_schemas)
      let state = import_qualified(state, "gleam/option", "Some")

      let comment_part = case param.description {
        Some(desc) -> [description_to_comment(desc), doc.line]
        None -> []
      }

      let setter_doc =
        doc.concat(
          list.append(comment_part, [
            doc.from_string("pub fn " <> setter_fn_name <> "("),
            doc.line |> doc.nest(by: indent),
            doc.from_string(var_name <> ": " <> type_name <> ",")
              |> doc.nest(by: indent),
            doc.line |> doc.nest(by: indent),
            doc.concat([
              doc.from_string(field_name <> " " <> field_name <> ": "),
              inner_type,
              doc.from_string(","),
            ])
              |> doc.nest(by: indent),
            doc.line,
            doc.from_string(") -> " <> type_name <> " {"),
            doc.line |> doc.nest(by: indent),
            doc.from_string(
              type_name
              <> "(.."
              <> var_name
              <> ", "
              <> field_name
              <> ": Some("
              <> field_name
              <> "))",
            )
              |> doc.nest(by: indent),
            doc.line,
            doc.from_string("}"),
          ]),
        )

      #(state, list.append(setters, [setter_doc]))
    })

  let all_docs =
    [type_doc, constructor_doc]
    |> list.append(setters)

  #(state, all_docs)
}

/// Generate a Request type that merges path/query params with inline body fields.
/// The to_json encoder only serializes body fields, not param fields.
fn operation_inline_body_request_docs(
  state: State,
  type_name: String,
  path_params: List(Parameter),
  query_params: List(Parameter),
  body_base: BaseSchema,
  body_schema: ObjectSchema,
  all_schemas: List(#(String, Schema)),
  config: Config,
  promoted_body_fields: Set(String),
) -> #(State, List(Document), List(#(String, Schema))) {
  let indent = config.indent
  let request_only = True
  let all_params = list.append(path_params, query_params)

  // Register as RequestOnly so it gets opaque type
  let state =
    State(
      ..state,
      schema_usages: dict.insert(state.schema_usages, type_name, RequestOnly),
    )

  // Track enums registered before schema generation
  let enums_before = state.enums

  // --- Build type definition fields ---

  // Param fields
  let #(state, param_fields) =
    list.fold(all_params, #(state, []), fn(acc, param) {
      let #(state, fields) = acc
      let field_name = to_field_name(param.name)
      let #(state, type_doc) = param_to_type(state, param, all_schemas)
      let field_doc = case param.required {
        True -> doc.concat([doc.from_string(field_name <> ": "), type_doc])
        False ->
          doc.concat([
            doc.from_string(field_name <> ": Option("),
            type_doc,
            doc.from_string(")"),
          ])
      }
      #(state, list.append(fields, [field_doc]))
    })

  // Body fields (same logic as object_type_doc)
  let #(state, body_fields) =
    list.fold(body_schema.properties, #(state, []), fn(acc, prop) {
      let #(state, fields) = acc
      let #(prop_name, prop_schema) = prop
      let field_name = to_field_name(prop_name)
      let in_required = list.contains(body_schema.required, prop_name)
      let optional =
        is_field_optional(prop_schema, in_required, config.optionality)
        || set.contains(promoted_body_fields, prop_name)
      let enum_hint = type_name <> to_type_name(prop_name)
      let #(state, field_type) =
        schema_to_gleam_type(
          state,
          prop_schema,
          !optional,
          all_schemas,
          enum_hint,
          request_only,
        )

      let field_line =
        doc.concat([doc.from_string(field_name <> ": "), field_type])

      let field_doc = case schema_description(prop_schema) {
        Some(comment) -> doc.concat([comment, doc.line, field_line])
        None -> field_line
      }

      #(state, [field_doc, ..fields])
    })
  let body_fields = list.reverse(body_fields)

  let all_fields = list.append(param_fields, body_fields)

  // Import Option if there are optional params or body fields
  let has_optional_params = list.any(all_params, fn(p) { !p.required })
  let state = case has_optional_params {
    True -> import_qualified(state, "gleam/option", "type Option")
    False -> state
  }

  // Type definition (always opaque for RequestOnly)
  let comment = base_schema_comment(body_base)
  let type_body = case all_fields {
    [] ->
      doc.concat([
        doc.from_string("pub opaque type " <> type_name <> " {"),
        doc.line |> doc.nest(by: indent),
        doc.from_string(type_name) |> doc.nest(by: indent),
        doc.line,
        doc.from_string("}"),
      ])
    _ ->
      doc.concat([
        doc.from_string("pub opaque type " <> type_name <> " {"),
        doc.line |> doc.nest(by: indent),
        doc.concat([
          doc.from_string(type_name <> "("),
          doc.line |> doc.nest(by: indent),
          doc.join(
            all_fields,
            with: doc.concat([doc.from_string(","), doc.line]),
          )
            |> doc.nest(by: indent),
          doc.concat([doc.from_string(","), doc.line]),
          doc.from_string(")"),
        ])
          |> doc.nest(by: indent),
        doc.line,
        doc.from_string("}"),
      ])
  }
  let type_doc = case comment {
    Some(c) -> doc.concat([c, doc.line, type_body])
    None -> type_body
  }

  // --- to_json: ONLY body fields ---
  let #(state, to_json_doc) =
    record_to_json_doc(
      state,
      type_name,
      body_schema,
      all_schemas,
      config,
      request_only,
      promoted_body_fields,
    )

  // --- Constructor: required params + required body fields ---
  // Classify body fields
  let body_field_info =
    list.map(body_schema.properties, fn(prop) {
      let #(prop_name, prop_schema) = prop
      let field_name = to_field_name(prop_name)
      let in_required = list.contains(body_schema.required, prop_name)
      let optional =
        is_field_optional(prop_schema, in_required, config.optionality)
        || set.contains(promoted_body_fields, prop_name)
      #(prop_name, field_name, prop_schema, optional)
    })

  let has_optional_body = list.any(body_field_info, fn(f) { f.3 })

  let state = case has_optional_params || has_optional_body {
    True -> import_qualified(state, "gleam/option", "None")
    False -> state
  }

  // Required param args
  let #(state, param_required_args) =
    list.fold(
      list.filter(all_params, fn(p) { p.required }),
      #(state, []),
      fn(acc, param) {
        let #(state, args) = acc
        let field_name = to_field_name(param.name)
        let #(state, type_doc) = param_to_type(state, param, all_schemas)
        let arg =
          doc.concat([
            doc.from_string(field_name <> " " <> field_name <> ": "),
            type_doc,
          ])
        #(state, list.append(args, [arg]))
      },
    )

  // Required body field args
  let #(state, body_required_args) =
    list.fold(body_field_info, #(state, []), fn(acc, f) {
      let #(state, args) = acc
      let #(prop_name, field_name, prop_schema, optional) = f
      case optional {
        True -> #(state, args)
        False -> {
          let enum_hint = type_name <> to_type_name(prop_name)
          let #(state, field_type) =
            schema_to_gleam_type(
              state,
              prop_schema,
              True,
              all_schemas,
              enum_hint,
              request_only,
            )
          let arg =
            doc.concat([
              doc.from_string(field_name <> " " <> field_name <> ": "),
              field_type,
            ])
          #(state, list.append(args, [arg]))
        }
      }
    })

  let required_args = list.append(param_required_args, body_required_args)

  // Field initializers
  let param_inits =
    list.map(all_params, fn(p) {
      let field_name = to_field_name(p.name)
      case p.required {
        True -> field_name <> ":"
        False -> field_name <> ": None"
      }
    })
  let body_inits =
    list.map(body_field_info, fn(f) {
      let #(_, field_name, _, optional) = f
      case optional {
        True -> field_name <> ": None"
        False -> field_name <> ":"
      }
    })
  let field_inits = list.append(param_inits, body_inits)

  let constructor_body =
    doc.from_string(type_name <> "(" <> string.join(field_inits, ", ") <> ")")

  let constructor_fn_name = "new_" <> justin.snake_case(type_name)
  let constructor_doc = case required_args {
    [] ->
      doc.concat([
        doc.from_string(
          "pub fn " <> constructor_fn_name <> "() -> " <> type_name <> " {",
        ),
        doc.line |> doc.nest(by: indent),
        constructor_body |> doc.nest(by: indent),
        doc.line,
        doc.from_string("}"),
      ])
    _ ->
      doc.concat([
        doc.from_string("pub fn " <> constructor_fn_name <> "("),
        doc.line |> doc.nest(by: indent),
        doc.join(
          required_args,
          with: doc.concat([doc.from_string(","), doc.line]),
        )
          |> doc.nest(by: indent),
        doc.concat([doc.from_string(","), doc.line]),
        doc.from_string(") -> " <> type_name <> " {"),
        doc.line |> doc.nest(by: indent),
        constructor_body |> doc.nest(by: indent),
        doc.line,
        doc.from_string("}"),
      ])
  }

  // --- Setters: optional params + optional body fields ---

  // Param setters
  let var_name = justin.snake_case(type_name)
  let optional_params = list.filter(all_params, fn(p) { !p.required })
  let #(state, param_setters) =
    list.fold(optional_params, #(state, []), fn(acc, param) {
      let #(state, setters) = acc
      let field_name = to_field_name(param.name)
      let setter_fn_name =
        justin.snake_case(type_name) <> "_with_" <> field_name
      let #(state, inner_type) = param_to_type(state, param, all_schemas)
      let state = import_qualified(state, "gleam/option", "Some")

      let comment_part = case param.description {
        Some(desc) -> [description_to_comment(desc), doc.line]
        None -> []
      }

      let setter_doc =
        doc.concat(
          list.append(comment_part, [
            doc.from_string("pub fn " <> setter_fn_name <> "("),
            doc.line |> doc.nest(by: indent),
            doc.from_string(var_name <> ": " <> type_name <> ",")
              |> doc.nest(by: indent),
            doc.line |> doc.nest(by: indent),
            doc.concat([
              doc.from_string(field_name <> " " <> field_name <> ": "),
              inner_type,
              doc.from_string(","),
            ])
              |> doc.nest(by: indent),
            doc.line,
            doc.from_string(") -> " <> type_name <> " {"),
            doc.line |> doc.nest(by: indent),
            doc.from_string(
              type_name
              <> "(.."
              <> var_name
              <> ", "
              <> field_name
              <> ": Some("
              <> field_name
              <> "))",
            )
              |> doc.nest(by: indent),
            doc.line,
            doc.from_string("}"),
          ]),
        )

      #(state, list.append(setters, [setter_doc]))
    })

  // Body field setters (reuse record_with_field_docs)
  let #(state, body_setters) =
    record_with_field_docs(
      state,
      type_name,
      body_schema,
      all_schemas,
      config,
      request_only,
      promoted_body_fields,
    )

  let all_setters = list.append(param_setters, body_setters)

  // --- Enum docs for any newly discovered enums ---
  let new_enums =
    dict.to_list(state.enums)
    |> list.filter(fn(entry) { !dict.has_key(enums_before, entry.0) })
  let enum_docs = case new_enums {
    [] -> []
    _ -> {
      let temp_state = State(..state, enums: dict.from_list(new_enums))
      [enums_doc(temp_state, config.indent)]
    }
  }

  // Add the inline schema to all_schemas so ref_to_json can find it
  let all_schemas = [
    #(type_name, schema.Object(body_base, body_schema)),
    ..all_schemas
  ]

  let all_docs =
    list.flatten([
      enum_docs,
      [type_doc, to_json_doc, constructor_doc],
      all_setters,
    ])

  #(state, all_docs, all_schemas)
}

fn operation_fn_name(op: Operation, path: String, method: String) -> String {
  case op.operation_id {
    Some(id) -> justin.snake_case(id)
    None -> {
      // Fallback: method + path
      let clean_path =
        string.replace(path, "{", "")
        |> string.replace("}", "")
        |> string.replace("/", "_")
      justin.snake_case(string.lowercase(method) <> clean_path)
    }
  }
}

fn param_to_type(
  state: State,
  param: Parameter,
  all_schemas: List(#(String, Schema)),
) -> #(State, Document) {
  case param.schema {
    // Inline string enums on parameters are just String — the enum type is
    // not generated in the schema section.
    Some(schema.String(_, _)) -> #(state, doc.from_string("String"))
    // Always pass required=True here because optional wrapping is handled
    // by the Params type builder / setter generator, not by the type itself.
    Some(schema) ->
      schema_to_gleam_type(state, schema, True, all_schemas, param.name, False)
    None -> #(state, doc.from_string("String"))
  }
}

/// Returns the expression to convert a query param value `v` to a String.
/// For String types, this is just "v". For Int types, "int.to_string(v)".
fn query_param_to_string_expr(param: Parameter) -> String {
  case param.schema {
    Some(schema.Integer(_, _)) -> "int.to_string(v)"
    Some(schema.Number(_)) -> "float.to_string(v)"
    Some(schema.Boolean(_)) -> "bool.to_string(v)"
    _ -> "v"
  }
}

fn request_body_param(
  state: State,
  rb: operation.RequestBody,
  all_schemas: List(#(String, Schema)),
) -> #(State, Option(#(String, Document, Schema))) {
  // Look for application/json content
  case list.key_find(rb.content, "application/json") {
    Ok(media_type) ->
      case media_type.schema {
        Some(body_schema) -> {
          let #(state, type_doc) =
            schema_to_gleam_type(
              state,
              body_schema,
              True,
              all_schemas,
              "body",
              False,
            )
          #(state, Some(#("body", type_doc, body_schema)))
        }
        None -> #(state, None)
      }
    Error(_) -> #(state, None)
  }
}

fn response_type_from_op(
  state: State,
  op: Operation,
  all_schemas: List(#(String, Schema)),
) -> #(State, Option(#(Document, Schema))) {
  // Try 200, then 201, then "default"
  let response =
    list.key_find(op.responses, "200")
    |> result_or(fn() { list.key_find(op.responses, "201") })
    |> result_or(fn() { list.key_find(op.responses, "default") })

  case response {
    Ok(resp) ->
      case list.key_find(resp.content, "application/json") {
        Ok(media_type) ->
          case media_type.schema {
            Some(resp_schema) -> {
              let #(state, type_doc) =
                schema_to_gleam_type(
                  state,
                  resp_schema,
                  True,
                  all_schemas,
                  "response",
                  False,
                )
              #(state, Some(#(type_doc, resp_schema)))
            }
            None -> #(state, None)
          }
        Error(_) -> #(state, None)
      }
    Error(_) -> #(state, None)
  }
}

fn result_or(
  result: Result(a, e),
  alternative: fn() -> Result(a, e),
) -> Result(a, e) {
  case result {
    Ok(_) -> result
    Error(_) -> alternative()
  }
}

fn build_url_expression(
  path: String,
  path_params: List(Parameter),
  params_prefix: String,
  promoted: Set(String),
) -> Document {
  // Split path on {param} segments and build a string concatenation
  case path_params {
    [] ->
      doc.from_string(
        "let assert Ok(req) = request.to(client.base_url <> \"" <> path <> "\")",
      )
    _ -> {
      let url_parts =
        build_path_parts(path, path_params, params_prefix, promoted)
      doc.concat([
        doc.from_string("let assert Ok(req) = request.to(client.base_url <> "),
        url_parts,
        doc.from_string(")"),
      ])
    }
  }
}

fn build_path_parts(
  path: String,
  params: List(Parameter),
  params_prefix: String,
  promoted: Set(String),
) -> Document {
  // Replace {param} with string concatenation
  let parts = split_path_on_params(path, params, params_prefix, promoted, [])
  doc.join(parts, with: doc.from_string(" <> "))
}

fn split_path_on_params(
  remaining: String,
  params: List(Parameter),
  params_prefix: String,
  promoted: Set(String),
  acc: List(Document),
) -> List(Document) {
  case find_next_param(remaining, params) {
    Some(#(before, param, after)) -> {
      // Promoted params are resolved to local variables (no prefix)
      let param_name = case set.contains(promoted, param.name) {
        True -> to_field_name(param.name)
        False -> params_prefix <> to_field_name(param.name)
      }
      let has_int_type = case param.schema {
        Some(schema.Integer(_, _)) -> True
        _ -> False
      }
      let before_parts = case before {
        "" -> acc
        _ -> list.append(acc, [doc.from_string("\"" <> before <> "\"")])
      }
      let param_expr = case has_int_type {
        True -> doc.from_string("int.to_string(" <> param_name <> ")")
        False -> doc.from_string(param_name)
      }
      split_path_on_params(
        after,
        params,
        params_prefix,
        promoted,
        list.append(before_parts, [param_expr]),
      )
    }
    None ->
      case remaining {
        "" -> acc
        _ -> list.append(acc, [doc.from_string("\"" <> remaining <> "\"")])
      }
  }
}

fn find_next_param(
  path: String,
  params: List(Parameter),
) -> Option(#(String, Parameter, String)) {
  case string.split_once(path, "{") {
    Ok(#(before, rest)) ->
      case string.split_once(rest, "}") {
        Ok(#(param_name, after)) ->
          case list.find(params, fn(p) { p.name == param_name }) {
            Ok(param) -> Some(#(before, param, after))
            Error(_) -> None
          }
        Error(_) -> None
      }
    Error(_) -> None
  }
}

fn build_request_lines(
  state: State,
  method: String,
  query_params: List(Parameter),
  body_param: Option(#(String, Document, Schema)),
  all_schemas: List(#(String, Schema)),
  params_prefix: String,
  promoted: Set(String),
) -> List(Document) {
  let method_line =
    doc.from_string("let req = request.set_method(req, http." <> method <> ")")

  let header_line =
    doc.from_string(
      "let req = request.prepend_header(req, \"content-type\", \"application/json\")",
    )

  let body_line = case body_param {
    Some(#(arg_name, _, body_schema)) -> {
      let #(_state, encode_expr) =
        schema_to_json_expression_inner(
          state,
          body_schema,
          arg_name,
          all_schemas,
          arg_name,
          False,
        )
      let encode_str = doc.to_string(encode_expr, 80)
      [
        doc.from_string(
          "let req = request.set_body(req, json.to_string("
          <> encode_str
          <> "))",
        ),
      ]
    }
    None -> []
  }

  let query_lines = case query_params {
    [] -> []
    _ -> {
      let is_array_param = fn(p: Parameter) {
        case p.schema {
          Some(schema.Array(_, _)) -> True
          _ -> False
        }
      }

      // A query param is "effectively required" if it's required or promoted
      // (promoted params have been resolved to local variables via merge lines)
      let is_effectively_required = fn(p: Parameter) {
        p.required || set.contains(promoted, p.name)
      }

      // Get the variable name for a query param:
      // promoted params use direct variable name, others use params_prefix
      let param_var_name = fn(p: Parameter) {
        case set.contains(promoted, p.name) {
          True -> to_field_name(p.name)
          False -> params_prefix <> to_field_name(p.name)
        }
      }

      // Required scalar query params are always included as tuples
      let required_scalar_entries =
        list.filter(query_params, fn(p) {
          is_effectively_required(p) && !is_array_param(p)
        })
        |> list.map(fn(param) {
          let pname = param_var_name(param)
          let value_expr = case query_param_to_string_expr(param) {
            "v" -> pname
            conv -> string.replace(conv, "v", pname)
          }
          doc.from_string("#(\"" <> param.name <> "\", " <> value_expr <> ")")
        })

      // Required array query params are expanded with list.map
      let required_array_lines =
        list.filter(query_params, fn(p) {
          is_effectively_required(p) && is_array_param(p)
        })
        |> list.map(fn(param) {
          let pname = param_var_name(param)
          let value_expr = query_param_to_string_expr(param)
          doc.from_string(
            "let query = list.append(query, list.map("
            <> pname
            <> ", fn(v) { #(\""
            <> param.name
            <> "\", "
            <> value_expr
            <> ") }))",
          )
        })

      // Optional scalar query params use option.map + option.values
      let optional_scalar_entries =
        list.filter(query_params, fn(p) {
          !is_effectively_required(p) && !is_array_param(p)
        })
        |> list.map(fn(param) {
          let pname = param_var_name(param)
          let value_expr = query_param_to_string_expr(param)
          doc.from_string(
            "option.map("
            <> pname
            <> ", fn(v) { #(\""
            <> param.name
            <> "\", "
            <> value_expr
            <> ") })",
          )
        })

      // Optional array query params use option.unwrap + list.map
      let optional_array_lines =
        list.filter(query_params, fn(p) {
          !is_effectively_required(p) && is_array_param(p)
        })
        |> list.map(fn(param) {
          let pname = param_var_name(param)
          let value_expr = query_param_to_string_expr(param)
          doc.from_string(
            "let query = list.append(query, "
            <> pname
            <> " |> option.unwrap([]) |> list.map(fn(v) { #(\""
            <> param.name
            <> "\", "
            <> value_expr
            <> ") }))",
          )
        })

      let required_list = case required_scalar_entries {
        [] -> doc.from_string("[]")
        _ ->
          doc.concat([
            doc.from_string("["),
            doc.join(required_scalar_entries, with: doc.from_string(", ")),
            doc.from_string("]"),
          ])
      }

      let optional_scalar_part = case optional_scalar_entries {
        [] -> []
        _ -> [
          doc.from_string("let query = list.append(query, option.values(["),
          ..list.append(
            list.map(optional_scalar_entries, fn(entry) {
              doc.concat([
                doc.from_string("  "),
                entry,
                doc.from_string(","),
              ])
            }),
            [doc.from_string("]))")],
          )
        ]
      }

      list.flatten([
        [doc.concat([doc.from_string("let query = "), required_list])],
        required_array_lines,
        optional_scalar_part,
        optional_array_lines,
        [doc.from_string("let req = request.set_query(req, query)")],
      ])
    }
  }

  [method_line, header_line]
  |> list.append(body_line)
  |> list.append(query_lines)
}

fn build_decode_line(
  state: State,
  response_type: Option(#(Document, Schema)),
  all_schemas: List(#(String, Schema)),
) -> #(State, Document) {
  case response_type {
    Some(#(_type_doc, resp_schema)) -> {
      let #(state, decoder_doc) =
        schema_to_inner_decoder(state, resp_schema, all_schemas, "response")
      let decoder_str = doc.to_string(decoder_doc, 80)
      #(
        state,
        doc.concat([
          doc.from_string(
            "use resp <- result.try(client.http_client(req) |> result.map_error(ClientError))",
          ),
          doc.line,
          doc.from_string("json.parse(resp.body, " <> decoder_str <> ")"),
          doc.line,
          doc.from_string("|> result.map_error(JsonDecodeError)"),
        ]),
      )
    }
    None -> #(
      state,
      doc.concat([
        doc.from_string(
          "use resp <- result.try(client.http_client(req) |> result.map_error(ClientError))",
        ),
        doc.line,
        doc.from_string("let _ = resp"),
        doc.line,
        doc.from_string("Ok(Nil)"),
      ]),
    )
  }
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
  let usage = get_schema_usage(state, name)
  case schema {
    schema.Object(base, object_schema) ->
      object_type_doc(
        state,
        type_name,
        base,
        object_schema,
        all_schemas,
        config,
        usage,
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
  usage: SchemaUsage,
) -> #(State, Document) {
  let comment = base_schema_comment(base)

  let is_opaque = case usage {
    RequestOnly -> True
    ResponseOnly | Both | Unreferenced -> False
  }

  let request_only = usage == RequestOnly

  let needs_decoder = case usage {
    RequestOnly -> False
    ResponseOnly | Both | Unreferenced -> True
  }

  let needs_encoder = case usage {
    ResponseOnly -> False
    RequestOnly | Both | Unreferenced -> True
  }

  let needs_constructor = case usage {
    ResponseOnly -> False
    RequestOnly | Both | Unreferenced -> True
  }

  let needs_setters = case usage {
    ResponseOnly -> False
    RequestOnly | Both | Unreferenced -> True
  }

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
          request_only,
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

  let type_keyword = case is_opaque {
    True -> "pub opaque type "
    False -> "pub type "
  }

  let body = case fields {
    [] ->
      doc.concat([
        doc.from_string(type_keyword <> type_name <> " {"),
        doc.line |> doc.nest(by: indent),
        doc.from_string(type_name)
          |> doc.nest(by: indent),
        doc.line,
        doc.from_string("}"),
      ])
    _ ->
      doc.concat([
        doc.from_string(type_keyword <> type_name <> " {"),
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

  // Conditionally generate decoder, encoder, constructor, and setters
  // based on how the schema is used by operations.
  let #(state, result) = case needs_decoder {
    True -> {
      let #(state, decoder) =
        record_decoder_doc(state, type_name, object_schema, all_schemas, config)
      #(state, doc.concat([result, doc.lines(2), decoder]))
    }
    False -> #(state, result)
  }

  let #(state, result) = case needs_encoder {
    True -> {
      let #(state, encoder) =
        record_to_json_doc(
          state,
          type_name,
          object_schema,
          all_schemas,
          config,
          request_only,
          set.new(),
        )
      #(state, doc.concat([result, doc.lines(2), encoder]))
    }
    False -> #(state, result)
  }

  let #(state, result) = case needs_constructor {
    True -> {
      let #(state, constructor) =
        record_new_doc(
          state,
          type_name,
          object_schema,
          all_schemas,
          config,
          request_only,
        )
      #(state, doc.concat([result, doc.lines(2), constructor]))
    }
    False -> #(state, result)
  }

  let #(state, result) = case needs_setters {
    True -> {
      let #(state, setters) =
        record_with_field_docs(
          state,
          type_name,
          object_schema,
          all_schemas,
          config,
          request_only,
          set.new(),
        )
      let setter_docs = case setters {
        [] -> doc.empty
        _ -> doc.concat([doc.lines(2), doc.join(setters, with: doc.lines(2))])
      }
      #(state, doc.concat([result, setter_docs]))
    }
    False -> #(state, result)
  }

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
    schema_to_gleam_type(state, schema, True, all_schemas, type_name, False)
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
  request_only: Bool,
) -> #(State, Document) {
  let #(state, inner) = case schema {
    schema.Ref(ref:) -> #(state, doc.from_string(ref_to_type_name(ref)))
    schema.String(_, string_schema) ->
      string_type(state, string_schema, enum_name_hint)
    schema.Integer(_, _) -> #(state, doc.from_string("Int"))
    schema.Number(_) -> #(state, doc.from_string("Float"))
    schema.Boolean(_) -> #(state, doc.from_string("Bool"))
    schema.Array(_, array_schema) ->
      array_type(state, array_schema, all_schemas, enum_name_hint, request_only)
    schema.Object(_, object_schema) ->
      inline_object_type(state, object_schema, all_schemas, request_only)
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
  request_only: Bool,
) -> #(State, Document) {
  let #(state, items_type) =
    schema_to_gleam_type(
      state,
      array_schema.items,
      True,
      all_schemas,
      enum_name_hint,
      request_only,
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
  request_only: Bool,
) -> #(State, Document) {
  case request_only {
    True -> {
      // For request-only schemas, use json.Json so the value is serializable
      let state = import_module(state, "gleam/json")
      #(state, doc.from_string("json.Json"))
    }
    False -> {
      // For response/both schemas, fall back to Dynamic (no decoder for Json)
      let state = import_qualified(state, "gleam/dynamic", "type Dynamic")
      #(state, doc.from_string("Dynamic"))
    }
  }
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

// --- JSON encoder mapping ----------------------------------------------------

fn schema_to_json_expression(
  state: State,
  schema: Schema,
  accessor: String,
  all_schemas: List(#(String, Schema)),
  enum_name_hint: String,
  optional: Bool,
  request_only: Bool,
) -> #(State, Document) {
  case optional {
    True -> {
      let #(state, encoder_fn) =
        schema_to_json_encoder_fn(
          state,
          schema,
          all_schemas,
          enum_name_hint,
          request_only,
        )
      #(
        state,
        doc.concat([
          doc.from_string("json.nullable(" <> accessor <> ", "),
          encoder_fn,
          doc.from_string(")"),
        ]),
      )
    }
    False ->
      schema_to_json_expression_inner(
        state,
        schema,
        accessor,
        all_schemas,
        enum_name_hint,
        request_only,
      )
  }
}

/// Returns a function-style encoder suitable for use as a callback.
/// e.g. `json.string`, `json.int`, `pet_to_json`, `fn(v) { ... }`.
fn schema_to_json_encoder_fn(
  state: State,
  schema: Schema,
  all_schemas: List(#(String, Schema)),
  enum_name_hint: String,
  request_only: Bool,
) -> #(State, Document) {
  case schema {
    schema.String(_, string_schema) ->
      string_to_json_fn(state, string_schema, enum_name_hint)
    schema.Integer(_, _) -> #(state, doc.from_string("json.int"))
    schema.Number(_) -> #(state, doc.from_string("json.float"))
    schema.Boolean(_) -> #(state, doc.from_string("json.bool"))
    schema.Array(_, array_schema) -> {
      let #(state, item_fn) =
        schema_to_json_encoder_fn(
          state,
          array_schema.items,
          all_schemas,
          enum_name_hint,
          request_only,
        )
      #(
        state,
        doc.concat([
          doc.from_string("json.array(_, "),
          item_fn,
          doc.from_string(")"),
        ]),
      )
    }
    schema.Ref(ref:) -> ref_to_json_fn(state, ref, all_schemas)
    schema.Object(_, _) ->
      case request_only {
        True -> #(state, doc.from_string("fn(v) { v }"))
        False -> #(state, doc.from_string("fn(_) { json.null() }"))
      }
  }
}

fn string_to_json_fn(
  state: State,
  string_schema: StringSchema,
  enum_name_hint: String,
) -> #(State, Document) {
  case string_schema.enum {
    Some(_) -> {
      let type_name = to_type_name(enum_name_hint)
      let to_json_fn = justin.snake_case(type_name) <> "_to_json"
      #(state, doc.from_string(to_json_fn))
    }
    None -> #(state, doc.from_string("json.string"))
  }
}

fn ref_to_json_fn(
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
    Ok(schema.Object(_, _)) -> {
      let to_json_fn = justin.snake_case(type_name) <> "_to_json"
      #(state, doc.from_string(to_json_fn))
    }
    Ok(schema) ->
      schema_to_json_encoder_fn(state, schema, all_schemas, type_name, False)
    Error(_) -> #(state, doc.from_string("fn(_) { json.null() }"))
  }
}

fn schema_to_json_expression_inner(
  state: State,
  schema: Schema,
  accessor: String,
  all_schemas: List(#(String, Schema)),
  enum_name_hint: String,
  request_only: Bool,
) -> #(State, Document) {
  case schema {
    schema.String(_, string_schema) ->
      string_to_json(state, string_schema, accessor, enum_name_hint)
    schema.Integer(_, _) -> #(
      state,
      doc.from_string("json.int(" <> accessor <> ")"),
    )
    schema.Number(_) -> #(
      state,
      doc.from_string("json.float(" <> accessor <> ")"),
    )
    schema.Boolean(_) -> #(
      state,
      doc.from_string("json.bool(" <> accessor <> ")"),
    )
    schema.Array(_, array_schema) ->
      array_to_json(state, array_schema, accessor, all_schemas, enum_name_hint)
    schema.Ref(ref:) -> ref_to_json(state, ref, accessor, all_schemas)
    schema.Object(_, _) ->
      case request_only {
        True -> #(state, doc.from_string(accessor))
        False -> #(state, doc.from_string("json.null()"))
      }
  }
}

fn string_to_json(
  state: State,
  string_schema: StringSchema,
  accessor: String,
  enum_name_hint: String,
) -> #(State, Document) {
  case string_schema.enum {
    Some(_) -> {
      let type_name = to_type_name(enum_name_hint)
      let to_string_fn = justin.snake_case(type_name) <> "_to_string"
      #(
        state,
        doc.from_string(
          "json.string(" <> to_string_fn <> "(" <> accessor <> "))",
        ),
      )
    }
    None ->
      case string_schema.format {
        Some("binary") -> #(
          state,
          doc.from_string("json.string(" <> accessor <> ")"),
        )
        _ -> #(state, doc.from_string("json.string(" <> accessor <> ")"))
      }
  }
}

fn array_to_json(
  state: State,
  array_schema: ArraySchema,
  accessor: String,
  all_schemas: List(#(String, Schema)),
  enum_name_hint: String,
) -> #(State, Document) {
  let #(state, item_encoder) =
    schema_to_json_expression_inner(
      state,
      array_schema.items,
      "item",
      all_schemas,
      enum_name_hint,
      False,
    )
  #(
    state,
    doc.concat([
      doc.from_string("json.array(" <> accessor <> ", fn(item) { "),
      item_encoder,
      doc.from_string(" })"),
    ]),
  )
}

fn ref_to_json(
  state: State,
  ref: String,
  accessor: String,
  all_schemas: List(#(String, Schema)),
) -> #(State, Document) {
  let raw_name = case string.split(ref, "/") {
    [_, _, _, name, ..] -> name
    _ -> ref
  }
  let type_name = to_type_name(raw_name)
  case list.key_find(all_schemas, raw_name) {
    Ok(schema.Object(_, _)) -> {
      let to_json_fn = justin.snake_case(type_name) <> "_to_json"
      #(state, doc.from_string(to_json_fn <> "(" <> accessor <> ")"))
    }
    Ok(schema) ->
      schema_to_json_expression_inner(
        state,
        schema,
        accessor,
        all_schemas,
        type_name,
        False,
      )
    Error(_) -> #(state, doc.from_string("json.null()"))
  }
}

// --- Optionality logic -------------------------------------------------------

fn is_field_optional(
  prop_schema: Schema,
  in_required: Bool,
  optionality: Optionality,
) -> Bool {
  // Inline objects map to Dynamic or json.Json, neither of which can be
  // constructed directly, so always treat them as optional regardless of
  // the optionality strategy.
  case prop_schema {
    schema.Object(_, _) -> True
    _ ->
      case optionality {
        common.RequiredOnly -> !in_required
        common.NullableOnly -> is_nullable(prop_schema)
        common.RequiredAndNullable -> !in_required || is_nullable(prop_schema)
      }
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

// --- Record encoder codegen --------------------------------------------------

fn record_to_json_doc(
  state: State,
  type_name: String,
  object_schema: ObjectSchema,
  all_schemas: List(#(String, Schema)),
  config: Config,
  request_only: Bool,
  promoted_body_fields: Set(String),
) -> #(State, Document) {
  let state = import_module(state, "gleam/json")
  let fn_name = justin.snake_case(type_name) <> "_to_json"
  let indent = config.indent

  let #(state, field_pairs) =
    list.fold(object_schema.properties, #(state, []), fn(acc, prop) {
      let #(state, pairs) = acc
      let #(prop_name, prop_schema) = prop
      let field_name = to_field_name(prop_name)
      let in_required = list.contains(object_schema.required, prop_name)
      let optional =
        is_field_optional(prop_schema, in_required, config.optionality)
        || set.contains(promoted_body_fields, prop_name)
      let enum_hint = type_name <> to_type_name(prop_name)
      let accessor = "value." <> field_name
      let #(state, json_expr) =
        schema_to_json_expression(
          state,
          prop_schema,
          accessor,
          all_schemas,
          enum_hint,
          optional,
          request_only,
        )

      let pair =
        doc.concat([
          doc.from_string("#(\"" <> prop_name <> "\", "),
          json_expr,
          doc.from_string(")"),
        ])
      #(state, [pair, ..pairs])
    })
  let field_pairs = list.reverse(field_pairs)

  let body = case field_pairs {
    [] -> doc.from_string("json.object([])")
    _ ->
      doc.concat([
        doc.from_string("json.object(["),
        doc.line |> doc.nest(by: indent),
        doc.join(
          field_pairs,
          with: doc.concat([doc.from_string(","), doc.line]),
        )
          |> doc.nest(by: indent),
        doc.concat([doc.from_string(","), doc.line]),
        doc.from_string("])"),
      ])
  }

  let result =
    doc.concat([
      doc.from_string(
        "pub fn " <> fn_name <> "(value: " <> type_name <> ") -> json.Json {",
      ),
      doc.line |> doc.nest(by: indent),
      body |> doc.nest(by: indent),
      doc.line,
      doc.from_string("}"),
    ])

  #(state, result)
}

// --- Record constructor codegen ----------------------------------------------

fn record_new_doc(
  state: State,
  type_name: String,
  object_schema: ObjectSchema,
  all_schemas: List(#(String, Schema)),
  config: Config,
  request_only: Bool,
) -> #(State, Document) {
  let fn_name = "new_" <> justin.snake_case(type_name)
  let indent = config.indent

  // Classify each field as required or optional
  let field_info =
    list.map(object_schema.properties, fn(prop) {
      let #(prop_name, prop_schema) = prop
      let field_name = to_field_name(prop_name)
      let in_required = list.contains(object_schema.required, prop_name)
      let optional =
        is_field_optional(prop_schema, in_required, config.optionality)
      #(prop_name, field_name, prop_schema, optional)
    })

  let has_optional = list.any(field_info, fn(f) { f.3 })

  // Import None if we have optional fields
  let state = case has_optional {
    True -> import_qualified(state, "gleam/option", "None")
    False -> state
  }

  // Build function parameter list (required fields only)
  let #(state, required_args) =
    list.fold(field_info, #(state, []), fn(acc, f) {
      let #(state, args) = acc
      let #(prop_name, field_name, prop_schema, optional) = f
      case optional {
        True -> #(state, args)
        False -> {
          let enum_hint = type_name <> to_type_name(prop_name)
          let #(state, field_type) =
            schema_to_gleam_type(
              state,
              prop_schema,
              True,
              all_schemas,
              enum_hint,
              request_only,
            )
          let arg =
            doc.concat([
              doc.from_string(field_name <> " " <> field_name <> ": "),
              field_type,
            ])
          #(state, list.append(args, [arg]))
        }
      }
    })

  // Build record field initializers
  let field_inits =
    list.map(field_info, fn(f) {
      let #(_prop_name, field_name, _prop_schema, optional) = f
      case optional {
        True -> field_name <> ": None"
        False -> field_name <> ":"
      }
    })

  let constructor_body = case field_inits {
    [] -> doc.from_string(type_name)
    _ ->
      doc.from_string(type_name <> "(" <> string.join(field_inits, ", ") <> ")")
  }

  let result = case required_args {
    [] ->
      doc.concat([
        doc.from_string("pub fn " <> fn_name <> "() -> " <> type_name <> " {"),
        doc.line |> doc.nest(by: indent),
        constructor_body |> doc.nest(by: indent),
        doc.line,
        doc.from_string("}"),
      ])
    _ ->
      doc.concat([
        doc.from_string("pub fn " <> fn_name <> "("),
        doc.line |> doc.nest(by: indent),
        doc.join(
          required_args,
          with: doc.concat([doc.from_string(","), doc.line]),
        )
          |> doc.nest(by: indent),
        doc.concat([doc.from_string(","), doc.line]),
        doc.from_string(") -> " <> type_name <> " {"),
        doc.line |> doc.nest(by: indent),
        constructor_body |> doc.nest(by: indent),
        doc.line,
        doc.from_string("}"),
      ])
  }

  #(state, result)
}

// --- Record setter codegen ---------------------------------------------------

fn record_with_field_docs(
  state: State,
  type_name: String,
  object_schema: ObjectSchema,
  all_schemas: List(#(String, Schema)),
  config: Config,
  request_only: Bool,
  promoted_body_fields: Set(String),
) -> #(State, List(Document)) {
  let indent = config.indent
  let var_name = justin.snake_case(type_name)

  list.fold(object_schema.properties, #(state, []), fn(acc, prop) {
    let #(state, docs) = acc
    let #(prop_name, prop_schema) = prop
    let field_name = to_field_name(prop_name)
    let in_required = list.contains(object_schema.required, prop_name)
    let optional =
      is_field_optional(prop_schema, in_required, config.optionality)
      || set.contains(promoted_body_fields, prop_name)

    case optional {
      False -> #(state, docs)
      True -> {
        let fn_name = justin.snake_case(type_name) <> "_with_" <> field_name
        let enum_hint = type_name <> to_type_name(prop_name)
        // Get the inner type (not wrapped in Option)
        let #(state, inner_type) =
          schema_to_gleam_type(
            state,
            prop_schema,
            True,
            all_schemas,
            enum_hint,
            request_only,
          )

        let state = import_qualified(state, "gleam/option", "Some")

        let comment_part = case schema_description(prop_schema) {
          Some(comment) -> [comment, doc.line]
          None -> []
        }

        let setter_doc =
          doc.concat(
            list.append(comment_part, [
              doc.from_string("pub fn " <> fn_name <> "("),
              doc.line |> doc.nest(by: indent),
              doc.from_string(var_name <> ": " <> type_name <> ",")
                |> doc.nest(by: indent),
              doc.line |> doc.nest(by: indent),
              doc.concat([
                doc.from_string(field_name <> " " <> field_name <> ": "),
                inner_type,
                doc.from_string(","),
              ])
                |> doc.nest(by: indent),
              doc.line,
              doc.from_string(") -> " <> type_name <> " {"),
              doc.line |> doc.nest(by: indent),
              doc.from_string(
                type_name
                <> "(.."
                <> var_name
                <> ", "
                <> field_name
                <> ": Some("
                <> field_name
                <> "))",
              )
                |> doc.nest(by: indent),
              doc.line,
              doc.from_string("}"),
            ]),
          )

        #(state, list.append(docs, [setter_doc]))
      }
    }
  })
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
      enum_to_string_doc(type_name, variants, indent),
      doc.lines(2),
      enum_to_json_doc(type_name, variants, indent),
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

fn enum_to_string_doc(
  type_name: String,
  variants: List(String),
  indent: Int,
) -> Document {
  let fn_name = justin.snake_case(type_name) <> "_to_string"
  let var_name = "value"

  let case_lines =
    list.map(variants, fn(v) {
      doc.concat([
        doc.from_string(enum_variant_name(type_name, v)),
        doc.from_string(" -> "),
        doc.from_string("\"" <> v <> "\""),
      ])
    })

  let case_block =
    doc.concat([
      doc.from_string("case " <> var_name <> " {"),
      doc.line |> doc.nest(by: indent),
      doc.join(case_lines, with: doc.line)
        |> doc.nest(by: indent),
      doc.line,
      doc.from_string("}"),
    ])

  doc.concat([
    doc.from_string(
      "pub fn "
      <> fn_name
      <> "("
      <> var_name
      <> ": "
      <> type_name
      <> ") -> String {",
    ),
    doc.line |> doc.nest(by: indent),
    case_block |> doc.nest(by: indent),
    doc.line,
    doc.from_string("}"),
  ])
}

fn enum_to_json_doc(
  type_name: String,
  _variants: List(String),
  indent: Int,
) -> Document {
  let fn_name = justin.snake_case(type_name) <> "_to_json"
  let to_string_fn = justin.snake_case(type_name) <> "_to_string"
  let var_name = "value"

  doc.concat([
    doc.from_string(
      "pub fn "
      <> fn_name
      <> "("
      <> var_name
      <> ": "
      <> type_name
      <> ") -> json.Json {",
    ),
    doc.line |> doc.nest(by: indent),
    doc.from_string("json.string(" <> to_string_fn <> "(" <> var_name <> "))")
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
