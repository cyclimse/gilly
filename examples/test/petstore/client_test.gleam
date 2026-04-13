import birdie
import gleam/httpc
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import pprint

import petstore/client

const api_base_url = "http://localhost:8080/api/v3"

fn new_assert_200_api_client() -> client.Client(String) {
  client.new(fn(req) {
    use resp <- result.try(
      httpc.send(req)
      |> result.map_error(fn(e) { "HTTP error: " <> string.inspect(e) }),
    )
    assert resp.status == 200
    Ok(resp)
  })
  |> client.with_base_url(api_base_url)
}

pub fn lucy(id: Int) -> client.Pet {
  client.Pet(
    id: Some(id),
    name: "Lucy",
    category: Some(client.Category(id: Some(1), name: Some("Mascots"))),
    photo_urls: ["https://gleam.run/images/lucy/lucypride.svg"],
    tags: Some([client.Tag(id: Some(1), name: Some("gleam"))]),
    status: Some(client.PetStatusAvailable),
  )
}

pub fn create_pet_test() {
  let api_client = new_assert_200_api_client()

  let lucy = lucy(10)

  let assert Ok(created) = client.add_pet(api_client, lucy)
  assert lucy.id == created.id

  created |> pprint.format |> birdie.snap(title: "Created Lucy (10)")
}

pub fn create_and_delete_pet_test() {
  let api_client = new_assert_200_api_client()

  let lucy = lucy(20)

  let assert Ok(created) = client.add_pet(api_client, lucy)
  assert lucy.id == created.id

  created |> pprint.format |> birdie.snap(title: "Created Lucy (20)")

  let assert Some(pet_id) = created.id
  let assert Ok(Nil) = client.delete_pet(api_client, pet_id)
}

pub fn create_and_update_pet_test() {
  let api_client = new_assert_200_api_client()

  let lucy = lucy(30)

  let assert Ok(created) = client.add_pet(api_client, lucy)
  assert lucy.id == created.id

  created |> pprint.format |> birdie.snap(title: "Created Lucy (30)")

  let updated_lucy =
    client.Pet(
      id: created.id,
      name: "Lucy Updated",
      category: created.category,
      photo_urls: created.photo_urls,
      tags: created.tags,
      status: Some(client.PetStatusSold),
    )

  let assert Ok(updated) = client.update_pet(api_client, updated_lucy)
  assert updated.name == "Lucy Updated"
  assert updated.status == Some(client.PetStatusSold)

  updated |> pprint.format |> birdie.snap(title: "Updated Lucy (30)")
}

pub fn list_pets_by_status_test() {
  let api_client = new_assert_200_api_client()

  // To avoid any issues with test isolation, we create specific pets for this test
  let test_pet_ids = [40, 41, 42]
  list.each(test_pet_ids, fn(id) {
    let pet = lucy(id)
    let assert Ok(created) = client.add_pet(api_client, pet)
    assert pet.id == created.id
  })

  let assert Ok(pets) = client.find_pets_by_status(api_client, "available")
  let found_test_pets =
    list.filter(pets, fn(p) {
      case p.id {
        Some(id) -> list.contains(test_pet_ids, id)
        None -> False
      }
    })

  found_test_pets
  |> list.sort(by: fn(l, r) {
    int.compare(option.unwrap(l.id, 0), option.unwrap(r.id, 0))
  })
  |> pprint.format
  |> birdie.snap(title: "Found available pets with IDs 40, 41, 42")
}
