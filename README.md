# Gilly

[![Package Version](https://img.shields.io/hexpm/v/gilly)](https://hex.pm/packages/gilly)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/gilly/)

Generate Gleam SDKs code from OpenAPI specifications.

> [!NOTE]  
> Gilly is in early development. Many features from the OpenAPI specification are not yet supported, and breaking changes may be introduced without a major version bump. Feedback and contributions are welcome!

Further documentation can be found at <https://hexdocs.pm/gilly>.

## Examples

Examples of generated clients can be found in the [examples](examples) directory.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```

## References

- [giacomocavalieri/squirrel](https://github.com/giacomocavalieri/squirrel) a Postgres client generator for Gleam, which inspired the design of this project.
- [oapi-codegen](https://github.com/oapi-codegen/oapi-codegen) a Go code generator for OpenAPI specifications. 
