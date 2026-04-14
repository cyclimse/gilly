import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

import argv
import clip.{type Command}
import clip/arg
import clip/flag
import clip/help
import clip/opt
import simplifile

import gilly/common.{type Optionality, version}
import gilly/error.{describe_error}
import gilly/gilly

type Args {
  Generate(
    source: String,
    output: Option(String),
    optionality: Optionality,
    indent: Int,
    optional_query_params: Bool,
    client_default_parameters: List(String),
  )
  Version
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

fn optionality_opt() -> opt.Opt(Optionality) {
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
      "RequiredOnly" -> Ok(common.RequiredOnly)
      "NullableOnly" -> Ok(common.NullableOnly)
      "RequiredAndNullable" -> Ok(common.RequiredAndNullable)
      _ ->
        Error(
          "Invalid optionality: '"
          <> s
          <> "'. Must be one of: RequiredOnly, NullableOnly, RequiredAndNullable",
        )
    }
  })
  |> opt.default(common.RequiredOnly)
}

fn indent_opt() -> opt.Opt(Int) {
  opt.new("indent")
  |> opt.help("Number of spaces for indentation (default: 2)")
  |> opt.int
  |> opt.default(2)
}

fn optional_query_params_flag() -> flag.Flag {
  flag.new("optional-query-params")
  |> flag.short("q")
  |> flag.help("Make query parameters optional (default: false)")
}

fn client_default_parameters_opt() -> opt.Opt(List(String)) {
  opt.new("client-default-parameters")
  |> opt.help(
    "Comma-separated list of parameter names to promote to the Client type as defaults (e.g. \"region\")",
  )
  |> opt.map(fn(s) {
    string.split(s, ",")
    |> list.map(string.trim)
    |> list.filter(fn(s) { s != "" })
  })
  |> opt.default([])
}

fn generate_command() -> Command(Args) {
  clip.command({
    use source <- clip.parameter
    use output <- clip.parameter
    use optionality <- clip.parameter
    use indent <- clip.parameter
    use optional_query_params <- clip.parameter
    use client_default_parameters <- clip.parameter
    Generate(
      source:,
      output:,
      optionality:,
      indent:,
      optional_query_params:,
      client_default_parameters:,
    )
  })
  |> clip.arg(source_arg())
  |> clip.opt(output_opt())
  |> clip.opt(optionality_opt())
  |> clip.opt(indent_opt())
  |> clip.flag(optional_query_params_flag())
  |> clip.opt(client_default_parameters_opt())
  |> clip.help(help.simple(
    "generate",
    "Generate code from an OpenAPI specification",
  ))
}

fn version_command() -> Command(Args) {
  clip.return(Version)
  |> clip.help(help.simple("version", "Print the version of Gilly"))
}

fn command() -> Command(Args) {
  clip.subcommands_with_default(
    [
      #("generate", generate_command()),
      #("version", version_command()),
    ],
    generate_command(),
  )
}

pub fn main() -> Nil {
  let result =
    command()
    |> clip.help(help.simple(
      "gilly",
      "✨ Generate Gleam SDKs from OpenAPI specifications.",
    ))
    |> clip.run(argv.load().arguments)

  case result {
    Error(e) -> io.println_error(e)
    Ok(args) -> run(args)
  }
}

fn run(args: Args) -> Nil {
  case args {
    Version -> io.println("Gilly version " <> version)
    Generate(
      source:,
      output:,
      optionality:,
      indent:,
      optional_query_params:,
      client_default_parameters:,
    ) -> {
      let builder =
        gilly.new()
        |> gilly.with_optionality(optionality)
        |> gilly.with_indent(indent)
        |> gilly.with_optional_query_params(optional_query_params)
        |> gilly.with_client_default_parameters(client_default_parameters)

      case gilly.generate_code_from_file(builder, source) {
        Ok(code) -> {
          case output {
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
        Error(e) ->
          io.println_error("Error generating code: " <> describe_error(e))
      }
    }
  }
}
