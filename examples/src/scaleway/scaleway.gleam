import envoy
import gleam/http/request
import gleam/httpc
import gleam/io
import gleam/list
import gleam/result
import gleam/string

import scaleway/client

const default_region = "fr-par"

/// Note: running this example may incur costs on your Scaleway account!
/// Make sure to clean up the resources afterwards.
pub fn main() {
  let assert Ok(scw_secret_key) = envoy.get("SCW_SECRET_KEY")
  let assert Ok(scw_project_id) = envoy.get("SCW_DEFAULT_PROJECT_ID")

  let region = envoy.get("SCW_REGION") |> result.unwrap(default_region)

  let api_client =
    client.new(fn(req) {
      let req = request.prepend_header(req, "X-Auth-Token", scw_secret_key)
      httpc.send(req)
      |> result.map_error(fn(e) { "HTTP error: " <> string.inspect(e) })
    })

  let namespace_params = client.new_create_namespace_params()
}
