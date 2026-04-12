import argv
import gilly/internal/error.{describe_error}
import gilly/internal/gilly
import gleam/io
import gleam/option.{type Option, None, Some}
import gleam/result
import simplifile

pub fn main() -> Nil {
  let action = parse_cli_args()
  case action {
    GenerateCode(source, output) ->
      case gilly.generate_code_from_file(source) {
        Ok(code) -> {
          case output {
            Some(path) -> {
              let _ =
                simplifile.write(path, code)
                |> result.map_error(fn(e) {
                  io.println(
                    "Error writing file: " <> simplifile.describe_error(e),
                  )
                })
              Nil
            }
            _ -> io.println(code)
          }
        }
        Error(e) -> io.println("Error generating code: " <> describe_error(e))
      }
    ShowHelp -> io.println("Usage: gilly <path_to_openapi_spec.json>")
  }
}

type Action {
  GenerateCode(source: String, output: Option(String))
  ShowHelp
}

fn parse_cli_args() -> Action {
  case argv.load().arguments {
    [source] -> GenerateCode(source, None)
    [source, output] -> GenerateCode(source, Some(output))
    _ -> ShowHelp
  }
}
