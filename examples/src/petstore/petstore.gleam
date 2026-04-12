import gleam/http/request
import gleam/http/response
import gleam/httpc
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/string

import petstore/schema

const base_url = "http://localhost:8080/api/v3"

fn client(
  req: request.Request(String),
) -> Result(response.Response(String), String) {
  httpc.send(req)
  |> result.map_error(fn(e) { "HTTP error: " <> string.inspect(e) })
}

pub fn main() {
  // 1. Create a pet
  let new_pet =
    schema.Pet(
      id: Some(99_999),
      name: "Lucy",
      category: Some(schema.Category(id: Some(1), name: Some("Dogs"))),
      photo_urls: ["https://gleam.run/images/lucy/lucypride.svg"],
      tags: Some([schema.Tag(id: Some(1), name: Some("gleam"))]),
      status: Some(schema.PetStatusAvailable),
    )

  io.println("--- Creating Lucy ---")

  let assert Ok(created) = schema.add_pet(client, base_url, new_pet)
  let assert Some(pet_id) = created.id
  io.println(
    "Created pet: " <> created.name <> " (id: " <> int.to_string(pet_id) <> ")",
  )

  // 2. List available pets
  io.println("\n--- Listing available pets ---")
  let assert Ok(pets) =
    schema.find_pets_by_status(client, base_url, "available")
  io.println("Found " <> int.to_string(list.length(pets)) <> " available pets")

  // 3. Delete the pet we just created
  io.println("\n--- Deleting pet " <> int.to_string(pet_id) <> " ---")
  let assert Ok(Nil) = schema.delete_pet(client, base_url, pet_id)
  io.println("Deleted!")
}
