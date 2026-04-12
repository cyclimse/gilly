import birdie
import pprint
import simplifile

import gilly/openapi/openapi

pub fn from_json_string_simple_test() {
  let assert Ok(json_string) =
    simplifile.read("test/gilly/openapi/samples/simple.json")
  let assert Ok(spec) = openapi.from_json_string(json_string)
  spec |> pprint.format |> birdie.snap(title: "Simple OpenAPI Spec")
}

pub fn from_json_string_pet_store_test() {
  let assert Ok(json_string) =
    simplifile.read("test/gilly/openapi/samples/petstore.json")
  let assert Ok(spec) = openapi.from_json_string(json_string)
  spec |> pprint.format |> birdie.snap(title: "Pet Store OpenAPI Spec")
}
