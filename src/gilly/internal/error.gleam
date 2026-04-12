import gilly/openapi/error as openapi_error
import gleam/string
import simplifile

/// Error types for Gilly operations, such as reading files, parsing OpenAPI specs, and generating code.
/// 
/// Note: I'm trying to keep them ordered in the way they would occur in the flow of operations, 
/// from reading the file to generating code.
/// If you're adding new error types, please try to place them in the appropriate order for better readability.
pub type Error {
  /// The provided file has an unsupported extension.
  UnsupportedFileType(source: String, supported: List(String))

  /// Reading the provided file failed. 
  /// This could be due to the file not existing, insufficient permissions, or other I/O errors.
  ReadingFile(source: String, inner: simplifile.FileError)

  /// The OpenAPI JSON could not be parsed or decoded correctly.
  ParsingOpenAPI(source: String, inner: openapi_error.Error)
}

pub fn describe_error(error: Error) -> String {
  case error {
    UnsupportedFileType(source, supported) ->
      "Unsupported file type for '"
      <> source
      <> "'. Supported file types are: "
      <> string.join(supported, ", ")
    ReadingFile(source, inner) ->
      "Failed to read file '"
      <> source
      <> "': "
      <> simplifile.describe_error(inner)
    ParsingOpenAPI(source, inner) ->
      "Failed to parse OpenAPI specification from file '"
      <> source
      <> "': "
      <> openapi_error.describe_error(inner)
  }
}
