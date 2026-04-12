import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{Some}

import petstore/schema

const base_url = "http://localhost:8080/api/v3"

pub fn main() {
  // 1. Create a pet
  let new_pet =
    schema.Pet(
      id: Some(99_999),
      name: "Gleamy",
      category: Some(schema.Category(id: Some(1), name: Some("Dogs"))),
      photo_urls: ["https://example.com/gleamy.png"],
      tags: Some([schema.Tag(id: Some(1), name: Some("gleam"))]),
      status: Some(schema.PetStatusAvailable),
    )

  io.println("--- Creating pet ---")
  let created = create_pet(new_pet)
  let assert Some(pet_id) = created.id
  io.println(
    "Created pet: " <> created.name <> " (id: " <> int.to_string(pet_id) <> ")",
  )

  // 2. List available pets
  io.println("\n--- Listing available pets ---")
  let pets = find_pets_by_status("available")
  io.println("Found " <> int.to_string(list.length(pets)) <> " available pets")

  // 3. Delete the pet we just created
  io.println("\n--- Deleting pet " <> int.to_string(pet_id) <> " ---")
  delete_pet(pet_id)
  io.println("Deleted!")
}

fn create_pet(pet: schema.Pet) -> schema.Pet {
  let body = schema.pet_to_json(pet) |> json.to_string
  let assert Ok(base_req) = request.to(base_url <> "/pet")
  let req =
    base_req
    |> request.set_method(http.Post)
    |> request.set_body(body)
    |> request.prepend_header("Content-Type", "application/json")
    |> request.prepend_header("Accept", "application/json")

  let assert Ok(resp) = httpc.send(req)
  assert resp.status == 200

  let assert Ok(created) = json.parse(resp.body, schema.pet_decoder())
  created
}

fn find_pets_by_status(status: String) -> List(schema.Pet) {
  let assert Ok(base_req) =
    request.to(base_url <> "/pet/findByStatus?status=" <> status)
  let req =
    base_req
    |> request.prepend_header("Accept", "application/json")

  let assert Ok(resp) = httpc.send(req)
  assert resp.status == 200

  let assert Ok(pets) = json.parse(resp.body, decode.list(schema.pet_decoder()))
  pets
}

fn delete_pet(id: Int) -> Nil {
  let assert Ok(base_req) = request.to(base_url <> "/pet/" <> int.to_string(id))
  let req =
    base_req
    |> request.set_method(http.Delete)
    |> request.prepend_header("Accept", "application/json")

  let assert Ok(resp) = httpc.send(req)
  assert resp.status == 200

  Nil
}
