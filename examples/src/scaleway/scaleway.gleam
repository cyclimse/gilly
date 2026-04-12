import envoy
import gleam/http/request
import gleam/httpc
import gleam/io
import gleam/result
import pprint

import scaleway/schema

const default_region = "fr-par"

const default_api_url = "https://api.scaleway.com"

pub fn main() {
  let client = must_load_scaleway_client_from_env()
  list_containers(client)
}

type ScalewayClient {
  ScalewayClient(
    scw_secret_key: String,
    default_project_id: String,
    region: String,
    scw_api_url: String,
  )
}

fn must_load_scaleway_client_from_env() -> ScalewayClient {
  let assert Ok(scw_secret_key) = envoy.get("SCW_SECRET_KEY")
  let assert Ok(default_project_id) = envoy.get("SCW_DEFAULT_PROJECT_ID")

  let region = envoy.get("SCW_REGION") |> result.unwrap(default_region)
  let scw_api_url = envoy.get("SCW_API_URL") |> result.unwrap(default_api_url)

  ScalewayClient(scw_secret_key:, default_project_id:, region:, scw_api_url:)
}

fn list_containers(
  client: ScalewayClient,
) -> schema.ScalewayContainersV1beta1ListContainersResponse {
  let url =
    client.scw_api_url
    <> "/containers/v1beta1/regions/"
    <> client.region
    <> "/containers"
  let assert Ok(base_req) = request.to(url)
  let req =
    request.prepend_header(base_req, "X-Auth-Token", client.scw_secret_key)
  let req = request.prepend_header(req, "Content-Type", "application/json")

  let assert Ok(resp) = httpc.send(req)
  assert resp.status == 200

  pprint.debug("Raw response body:")
  pprint.debug(resp.body)
  
  todo as "Parse response body and return list of containers"
}
