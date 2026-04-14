import gleam/bool
import gleam/list
import gleam/result
import gleam/string

import simplifile

import gilly/constant.{header_comment, supported_file_types, version}
import gilly/internal/codegen.{type Optionality}
import gilly/internal/error.{type Error}
import gilly/openapi/openapi.{type OpenAPI}

/// Builder is the main configuration record for Gilly.
///
/// It offers various options to customize the code generation process.
/// If you're adding codegen behaviors, try to make them configurable through the Builder.
pub opaque type Builder {
  Builder(
    optionality: Optionality,
    indent: Int,
    optional_query_params: Bool,
    client_default_parameters: List(String),
  )
}

/// Create a new Gilly Builder with default configuration.
pub fn new() -> Builder {
  Builder(
    optionality: codegen.RequiredOnly,
    indent: 2,
    optional_query_params: False,
    client_default_parameters: [],
  )
}

/// Optionality determines how we decide which fields are optional in the generated code.
pub fn with_optionality(builder: Builder, optionality: Optionality) -> Builder {
  Builder(..builder, optionality:)
}

/// Indent configures the number of spaces used for indentation in the generated code.
pub fn with_indent(builder: Builder, indent: Int) -> Builder {
  Builder(..builder, indent:)
}

/// When setting `optional_query_params` to `True`, all query parameters in the generated client will be optional, regardless of whether they are marked as required in the OpenAPI spec or not. 
/// This is useful for non-conforming OpenAPI specs or to allow more flexibility for SDK end-users.
pub fn with_optional_query_params(
  builder: Builder,
  optional_query_params: Bool,
) -> Builder {
  Builder(..builder, optional_query_params:)
}

/// Promote certain parameters (by name) to the Client type as defaults.
/// When set, these parameters become optional on each Request and are
/// automatically filled from the Client unless overridden per-request.
pub fn with_client_default_parameters(
  builder: Builder,
  client_default_parameters: List(String),
) -> Builder {
  Builder(..builder, client_default_parameters:)
}

fn to_codegen_config(builder: Builder) -> codegen.Config {
  codegen.Config(
    optionality: builder.optionality,
    indent: builder.indent,
    optional_query_params: builder.optional_query_params,
    client_default_parameters: builder.client_default_parameters,
  )
}

/// Generate Gleam code from an OpenAPI specification file.
/// 
/// Source should be a path to a JSON file containing the OpenAPI spec.
/// Returns the generated code as a string, or an error if something goes wrong.
pub fn generate_code_from_file(
  builder: Builder,
  source: String,
) -> Result(String, Error) {
  use content <- result.try(read_file(source))
  use spec <- result.try(
    openapi.from_json_string(content)
    |> result.map_error(error.ParsingOpenAPI(source:, inner: _)),
  )
  let code = generate_code(builder, spec)
  let header = generate_header(version, source)
  Ok(header <> "\n\n" <> code)
}

/// Generate Gleam code from an OpenAPI specification record.
/// See's gilly/openapi/openapi.gleam for more info on building OpenAPI records.
pub fn generate_code(builder: Builder, spec: OpenAPI) -> String {
  codegen.generate(spec, to_codegen_config(builder))
}

fn read_file(source: String) -> Result(String, Error) {
  use <- bool.guard(
    when: !is_supported_file_type(source),
    return: Error(error.UnsupportedFileType(source, supported_file_types)),
  )
  simplifile.read(source)
  |> result.map_error(error.ReadingFile(source:, inner: _))
}

fn is_supported_file_type(source: String) -> Bool {
  let extension =
    string.split(source, on: ".")
    |> list.last
    |> result.unwrap("")
  list.contains(supported_file_types, extension)
}

const version_sentinel = "<version>"

const source_path_sentinel = "<source_path>"

/// Generate a header comment for the generated code file.
fn generate_header(version: String, source: String) -> String {
  header_comment
  // Note: there might be a better way to do this in Gleam, but for now, we'll just use string replacement.
  |> string.replace(version_sentinel, version)
  |> string.replace(source_path_sentinel, source)
}
