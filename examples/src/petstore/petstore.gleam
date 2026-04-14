import gleam/httpc
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/string

import petstore/client

pub fn main() {
  let api_client =
    client.new(fn(req) {
      httpc.send(req)
      |> result.map_error(fn(e) { "HTTP error: " <> string.inspect(e) })
    })
    |> client.with_base_url("http://localhost:8080/api/v3")
  // 1. Create a pet
  let new_pet =
    client.Pet(
      id: Some(99_999),
      name: "Lucy",
      category: Some(client.Category(id: Some(1), name: Some("Dogs"))),
      photo_urls: ["https://gleam.run/images/lucy/lucypride.svg"],
      tags: Some([client.Tag(id: Some(1), name: Some("gleam"))]),
      status: Some(client.PetStatusAvailable),
    )

  io.println("--- Creating Lucy ---")

  let assert Ok(created) = client.add_pet(new_pet, api_client)
  let assert Some(pet_id) = created.id
  io.println(
    "Created pet: " <> created.name <> " (id: " <> int.to_string(pet_id) <> ")",
  )

  // 2. List available pets
  io.println("\n--- Listing available pets ---")
  let assert Ok(pets) =
    client.find_pets_by_status(
      client.new_find_pets_by_status_request("available"),
      api_client,
    )
  io.println("Found " <> int.to_string(list.length(pets)) <> " available pets")

  // 3. Delete the pet we just created
  io.println("\n--- Deleting pet " <> int.to_string(pet_id) <> " ---")
  let assert Ok(Nil) =
    client.delete_pet(client.new_delete_pet_request(pet_id), api_client)
  io.println("Deleted!")
}
