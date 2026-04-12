import birdie
import pprint
import simplifile

import gilly/openapi/error
import gilly/openapi/openapi

fn from_json_string_case(title: String, file_path: String) {
  let assert Ok(json_string) = simplifile.read(file_path)
  let assert Ok(spec) = openapi.from_json_string(json_string)
  spec |> pprint.format |> birdie.snap(title: title)
}

pub fn from_json_string_simple_test() {
  from_json_string_case("Simple OpenAPI Spec", "test/samples/simple.json")
}

pub fn from_json_string_pet_store_test() {
  from_json_string_case("Pet Store OpenAPI Spec", "test/samples/petstore.json")
}

pub fn from_json_string_scaleway_containers_test() {
  from_json_string_case(
    "Scaleway Containers OpenAPI Spec",
    "test/samples/scaleway_containers.json",
  )
}

pub fn from_json_string_unsupported_version_test() {
  let assert Ok(json_string) =
    simplifile.read("test/samples/unsupported_version.json")
  let assert Error(error.UnsupportedVersion(version:)) =
    openapi.from_json_string(json_string)
  assert version == "2.0"
}
