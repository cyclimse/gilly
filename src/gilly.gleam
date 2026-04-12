import argv
import clip.{type Command}
import clip/arg
import clip/help
import clip/opt
import gilly/internal/codegen
import gilly/internal/error.{describe_error}
import gilly/internal/gilly
import gleam/io
import gleam/option.{type Option, None, Some}
import gleam/result
import simplifile

type Args {
  Args(
    source: String,
    output: Option(String),
    optionality: codegen.Optionality,
    indent: Int,
  )
}

fn source_arg() -> arg.Arg(String) {
  arg.new("source")
  |> arg.help("Path to the OpenAPI specification file (JSON)")
}

fn output_opt() -> opt.Opt(Option(String)) {
  opt.new("output")
  |> opt.short("o")
  |> opt.help("Output file path (prints to stdout if omitted)")
  |> opt.map(Some)
  |> opt.default(None)
}

fn optionality_opt() -> opt.Opt(codegen.Optionality) {
  opt.new("optionality")
  |> opt.help(
    "How to determine optional fields:
    - RequiredOnly: Only fields that are required in the OpenAPI spec are non-optional (default)
    - NullableOnly: Fields are optional if they are marked `nullable: true`
    - RequiredAndNullable: Fields are optional if they are either not required or marked `nullable: true`
",
  )
  |> opt.try_map(fn(s) {
    case s {
      "RequiredOnly" -> Ok(codegen.RequiredOnly)
      "NullableOnly" -> Ok(codegen.NullableOnly)
      "RequiredAndNullable" -> Ok(codegen.RequiredAndNullable)
      _ ->
        Error(
          "Invalid optionality: '"
          <> s
          <> "'. Must be one of: RequiredOnly, NullableOnly, RequiredAndNullable",
        )
    }
  })
  |> opt.default(codegen.RequiredOnly)
}

fn indent_opt() -> opt.Opt(Int) {
  opt.new("indent")
  |> opt.help("Number of spaces for indentation (default: 2)")
  |> opt.int
  |> opt.default(2)
}

fn command() -> Command(Args) {
  clip.command({
    use source <- clip.parameter
    use output <- clip.parameter
    use optionality <- clip.parameter
    use indent <- clip.parameter
    Args(source:, output:, optionality:, indent:)
  })
  |> clip.arg(source_arg())
  |> clip.opt(output_opt())
  |> clip.opt(optionality_opt())
  |> clip.opt(indent_opt())
}

pub fn main() -> Nil {
  let result =
    command()
    |> clip.help(help.simple(
      "gilly",
      "Generate Gleam types from an OpenAPI specification",
    ))
    |> clip.run(argv.load().arguments)

  case result {
    Error(e) -> io.println_error(e)
    Ok(args) -> run(args)
  }
}

fn run(args: Args) -> Nil {
  let builder =
    gilly.new()
    |> gilly.with_optionality(args.optionality)
    |> gilly.with_indent(args.indent)

  case gilly.generate_code_from_file(builder, args.source) {
    Ok(code) -> {
      case args.output {
        Some(path) -> {
          let _ =
            simplifile.write(path, code)
            |> result.map_error(fn(e) {
              io.println_error(
                "Error writing file: " <> simplifile.describe_error(e),
              )
            })
          Nil
        }
        None -> io.println(code)
      }
    }
    Error(e) -> io.println_error("Error generating code: " <> describe_error(e))
  }
}
