import envoy
import gleam/bool
import gleam/erlang/process
import gleam/http/request
import gleam/httpc
import gleam/io
import gleam/result
import gleam/string

import scaleway/client

const default_region = "fr-par"

const max_retries = 300

/// Beware: this example is meant to be run with a real Scaleway account and
/// may incur costs.
/// 
/// cyclimse's note: Should be covered by the free tier :)
pub fn main() {
  let assert Ok(scw_secret_key) = envoy.get("SCW_SECRET_KEY")
  let assert Ok(project_id) = envoy.get("SCW_DEFAULT_PROJECT_ID")
  let region = envoy.get("SCW_REGION") |> result.unwrap(default_region)

  let api_client =
    client.new(
      fn(req) {
        let req = request.prepend_header(req, "X-Auth-Token", scw_secret_key)
        use resp <- result.try(
          httpc.send(req)
          |> result.map_error(fn(e) { "HTTP error: " <> string.inspect(e) }),
        )

        use <- bool.guard(
          when: resp.status >= 400,
          return: Error("API error: " <> string.inspect(resp.body)),
        )

        Ok(resp)
      },
      region: region,
      project_id: project_id,
    )

  let assert Ok(namespace) =
    client.new_create_namespace_request(
      name: "gilly-example",
      activate_vpc_integration: True,
      secret_environment_variables: [],
      tags: ["example", "gilly"],
    )
    |> client.create_namespace(api_client)

  io.println("Namespace created with ID: " <> namespace.id)

  let assert Ok(namespace) =
    wait_for_resource(
      fn() {
        client.new_get_namespace_request(namespace.id)
        |> client.get_namespace(api_client)
      },
      fn(ns) {
        ns.status == client.ScalewayContainersV1beta1NamespaceStatusReady
      },
      max_retries,
    )

  io.println("Namespace is ready to use!")

  let assert Ok(container) =
    client.new_create_container_request(
      namespace_id: namespace.id,
      name: "gilly-nginx",
      args: [],
      command: [],
      http_option: client.CreateContainerRequestHttpOptionEnabled,
      privacy: client.CreateContainerRequestPrivacyPublic,
      protocol: client.CreateContainerRequestProtocolHttp1,
      sandbox: client.CreateContainerRequestSandboxV2,
      secret_environment_variables: [],
      tags: ["example", "gilly"],
    )
    |> client.create_container_request_with_registry_image("nginx:alpine")
    |> client.create_container_request_with_port(80)
    |> client.create_container(api_client)

  io.println("Container created with ID: " <> container.id)

  let assert Ok(container) =
    wait_for_resource(
      fn() {
        client.new_get_container_request(container.id)
        |> client.get_container(api_client)
      },
      fn(c) { c.status == client.ScalewayContainersV1beta1ContainerStatusReady },
      max_retries,
    )

  let url = "https://" <> container.domain_name
  io.println("Container is ready to use at URL: " <> url)
}

type Getter(resource) =
  fn() -> Result(resource, client.ApiError(String))

type Checker(resource) =
  fn(resource) -> Bool

fn wait_for_resource(
  get_resource: Getter(resource),
  check_ready: Checker(resource),
  retries: Int,
) -> Result(resource, client.ApiError(String)) {
  use resource <- result.try(get_resource())
  case check_ready(resource) {
    True -> Ok(resource)
    False if retries > 0 -> {
      io.println("Resource not ready yet, waiting...")

      process.sleep(1000)

      wait_for_resource(get_resource, check_ready, retries - 1)
    }
    False ->
      Error(client.ClientError("Resource not ready after maximum retries"))
  }
}
