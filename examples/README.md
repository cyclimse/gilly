# Gilly examples

## Pet Store

Generate Gleam types from the Pet Store OpenAPI spec:

```bash
gleam run -m gilly -- samples/petstore.json -o src/pet_store/schema.gleam
```

Run the Pet Store example:

```bash
docker run --rm -p 8080:8080 swaggerapi/petstore3:1.0.27
```

Then, in another terminal, run the client:

```bash
gleam run -m petstore/petstore
```

## Scaleway

Generate Gleam types from the Scaleway OpenAPI spec:

```bash
gleam run -m gilly -- samples/scaleway_containers.json -o src/scaleway/schema.gleam --optionality NullableOnly
```

Export your Scaleway API key as an environment variable:

```bash
export SCW_SECRET_KEY=<your_api_key>
```

Run the client:

```bash
gleam run -m scaleway/scaleway
```
