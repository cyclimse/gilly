.PHONY: generate generate-petstore generate-scaleway run-petstore run-scaleway docker-petstore

generate: generate-petstore generate-scaleway

generate-petstore:
	gleam run -m gilly -- samples/petstore.json -o src/petstore/client.gleam

generate-scaleway:
	gleam run -m gilly -- samples/scaleway_containers.json -o src/scaleway/client.gleam \
	  --optionality NullableOnly \
	  --optional-query-params

run-petstore:
	gleam run -m petstore/petstore

run-scaleway:
	gleam run -m scaleway/scaleway

docker-petstore:
	docker run --rm -p 8080:8080 swaggerapi/petstore3:1.0.27
