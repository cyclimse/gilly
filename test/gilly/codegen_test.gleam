import birdie
import simplifile

import gilly/internal/gilly
import gilly/openapi/openapi

fn codegen_case(title: String, file_path: String) {
  let assert Ok(json_string) = simplifile.read(file_path)
  let assert Ok(spec) = openapi.from_json_string(json_string)
  let code = gilly.generate_code(spec)
  code |> birdie.snap(title: title)
}

pub fn codegen_simple_test() {
  codegen_case("Codegen Simple Schema", "test/samples/simple.json")
}

pub fn codegen_pet_store_test() {
  codegen_case("Codegen Pet Store Schemas", "test/samples/petstore.json")
}
