import birdie
import simplifile

import gilly/internal/codegen
import gilly/internal/gilly.{type Builder}
import gilly/openapi/openapi

fn generate_code_case(title: String, builder: Builder, file_path: String) {
  let assert Ok(json_string) = simplifile.read(file_path)
  let assert Ok(spec) = openapi.from_json_string(json_string)
  let code = gilly.generate_code(builder, spec)
  code |> birdie.snap(title: title)
}

pub fn codegen_simple_test() {
  let builder = gilly.new()
  generate_code_case(
    "Codegen Simple Schema",
    builder,
    "test/samples/simple.json",
  )
}

pub fn codegen_pet_store_test() {
  let builder = gilly.new()
  generate_code_case(
    "Codegen Pet Store Schemas",
    builder,
    "test/samples/petstore.json",
  )
}

pub fn codegen_scaleway_containers_test() {
  let builder = gilly.new()
  generate_code_case(
    "Codegen Scaleway Containers Schemas",
    builder,
    "test/samples/scaleway_containers.json",
  )

  let builder_required_only =
    gilly.new()
    |> gilly.with_optionality(codegen.NullableOnly)
  generate_code_case(
    "Codegen Scaleway Containers Schemas (NullableOnly)",
    builder_required_only,
    "test/samples/scaleway_containers.json",
  )
}
