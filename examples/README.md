# Gilly examples

## Scaleway

Generate Gleam types from the Scaleway OpenAPI spec:

```bash
gleam run -m gilly -- samples/scaleway_containers.json -o src/scaleway/schemas.gleam
```

Export your Scaleway API key as an environment variable:

```bash
export SCW_SECRET_KEY=<your_api_key>
```

Run the client:

```bash
gleam run -m scaleway
```
