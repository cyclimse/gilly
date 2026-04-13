# ✨ Gilly

[![Package Version](https://img.shields.io/hexpm/v/gilly)](https://hex.pm/packages/gilly)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/gilly/)

Generate Gleam SDKs from OpenAPI specifications.

> [!NOTE]  
> Gilly is in early development:
> - many features from the OpenAPI specification are not yet supported
> - for now, generated code is not guaranteed not to break between Gilly releases
> 
> Feedback and contributions are very welcome!

## Usage

### CLI

Add Gilly as a dev dependency in your `gleam.toml`:

```bash
gleam add gilly --dev
```

Then, you can run Gilly from the command line:

```bash
gleam run -m gilly -- <path_to_openapi_spec.json> --output <output_path.gleam>
```

That's it! You can use the generated SDK in your Gleam projects along with your favorite HTTP client to call the API.

Any HTTP client that uses [gleam/http](https://hexdocs.pm/gleam_http/index.html) types should be compatible with the Gilly generated client. This includes:

- [gleam/httpc](https://hexdocs.pm/gleam_httpc/index.html)
- [gleam/hackney](https://hexdocs.pm/gleam_hackney/index.html)

See the [examples](examples) for fully featured use cases.

### Library

Gilly can also be used as a library directly. Please refer to the [HexDocs](https://hexdocs.pm/gilly/gilly.html) for more details.

## Flags

| Flag                        | Short | Description                                                                                                                                                                                                                                           | Default        |
| --------------------------- | ----- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------- |
| `--output OUTPUT`           | `-o`  | Output file path (prints to stdout if omitted)                                                                                                                                                                                                        | None           |
| `--optionality OPTIONALITY` |       | How to determine optional fields: `RequiredOnly` (only fields not listed as required are optional), `NullableOnly` (only fields marked `nullable: true` are optional), `RequiredAndNullable` (fields are optional if either not required or nullable) | `RequiredOnly` |
| `--indent INDENT`           |       | Number of spaces for indentation                                                                                                                                                                                                                      | `2`            |
| `--optional-query-params`   | `-q`  | Make all query parameters optional regardless of the spec                                                                                                                                                                                             | `false`        |
| `--help`                    | `-h`  | Print help                                                                                                                                                                                                                                            |                |

## Examples

Examples of generated clients can be found in the [examples](examples) directory.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```

This project relies on [birdie](https://github.com/giacomocavalieri/birdie) snapshots for testing. You can update them by running:

```bash
gleam run -m birdie
```

### Releases

Releases are handled with [goreleaser](https://goreleaser.com/) and GitHub Actions.

To dry-run a release, you can use:

```bash
goreleaser release --snapshot --skip=publish --clean
```

## References

- [giacomocavalieri/squirrel](https://github.com/giacomocavalieri/squirrel) a Postgres client generator for Gleam, which inspired the design of this project.
- [oapi-codegen](https://github.com/oapi-codegen/oapi-codegen) a Go code generator for OpenAPI specifications. Extremely similar project (that probably works better) but does not support Gleam.
