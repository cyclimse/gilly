import envoy
import gleam/http/request
import gleam/httpc
import gleam/io
import gleam/list
import gleam/result
import gleam/string

import scaleway/client

const default_region = "fr-par"

pub fn main() {
  let assert Ok(scw_secret_key) = envoy.get("SCW_SECRET_KEY")
  let region = envoy.get("SCW_REGION") |> result.unwrap(default_region)

  let api_client =
    client.new(fn(req) {
      let req = request.prepend_header(req, "X-Auth-Token", scw_secret_key)
      httpc.send(req)
      |> result.map_error(fn(e) { "HTTP error: " <> string.inspect(e) })
    })

  let params = client.new_list_containers_request(region: region)

  let assert Ok(resp) =
    client.list_containers(request: params, client: api_client)

  list.each(
    resp.containers,
    fn(container: client.ScalewayContainersV1beta1Container) {
      let url = "https://" <> container.domain_name
      io.println(
        "Container " <> container.name <> " (" <> container.id <> "): " <> url,
      )
    },
  )
}
