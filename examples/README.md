# Gilly examples

A [Makefile](Makefile) is provided for convenience.

## Pet Store

Generate the client from the Pet Store OpenAPI spec:

```bash
make generate-petstore
```

Start the Pet Store docker container:

```bash
make docker-petstore
```

Then, in another terminal, run the client:

```bash
make run-petstore
```

## Scaleway

Generate the client from the Scaleway OpenAPI spec:

```bash
make generate-scaleway
```

Export your Scaleway credentials as environment variables:

```bash
export SCW_SECRET_KEY=<your_secret_key>
export SCW_DEFAULT_PROJECT_ID=<your_project_id>
```

Run the client:

```bash
make run-scaleway
```
