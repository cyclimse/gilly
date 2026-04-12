import birdie
import gilly/internal/codegen
import gilly/openapi/openapi.{type OpenAPI, Components, Info, OpenAPI}
import gilly/openapi/schema.{
  type BaseSchema, ArraySchema, BaseSchema, BooleanType, IntegerSchema,
  IntegerType, ObjectSchema, ObjectType, StringSchema, StringType,
}
import gilly/openapi/version.{Version}
import gleam/option.{None, Some}

fn v3() -> version.Version {
  Version(major: 3, minor: Some(0), patch: Some(0))
}

fn base(type_name: schema.TypeName) -> BaseSchema {
  BaseSchema(type_name:, title: None, description: None, nullable: False)
}

fn spec_with_schemas(schemas: List(#(String, schema.Schema))) -> OpenAPI {
  OpenAPI(
    version: v3(),
    info: Info(title: "Test", version: "1.0.0", description: None),
    paths: [],
    components: Some(Components(schemas:)),
  )
}

fn generate(spec: OpenAPI) -> String {
  let config = codegen.Config(optionality: codegen.RequiredOnly, indent: 2)
  codegen.generate_schemas(spec, config)
}

fn generate_with(spec: OpenAPI, optionality: codegen.Optionality) -> String {
  let config = codegen.Config(optionality:, indent: 2)
  codegen.generate_schemas(spec, config)
}

// --- Simple types ------------------------------------------------------------

pub fn type_alias_string_test() {
  spec_with_schemas([
    #(
      "MyString",
      schema.String(
        base(StringType),
        StringSchema(
          min_length: None,
          max_length: None,
          enum: None,
          format: None,
        ),
      ),
    ),
  ])
  |> generate
  |> birdie.snap(title: "codegen type alias string")
}

pub fn type_alias_integer_test() {
  spec_with_schemas([
    #(
      "MyInt",
      schema.Integer(
        base(IntegerType),
        IntegerSchema(minimum: None, maximum: None, format: None),
      ),
    ),
  ])
  |> generate
  |> birdie.snap(title: "codegen type alias integer")
}

// --- Object types ------------------------------------------------------------

pub fn empty_object_test() {
  spec_with_schemas([
    #(
      "EmptyRecord",
      schema.Object(
        base(ObjectType),
        ObjectSchema(required: [], properties: []),
      ),
    ),
  ])
  |> generate
  |> birdie.snap(title: "codegen empty object")
}

pub fn object_all_required_test() {
  spec_with_schemas([
    #(
      "User",
      schema.Object(
        base(ObjectType),
        ObjectSchema(required: ["name", "age"], properties: [
          #(
            "name",
            schema.String(
              base(StringType),
              StringSchema(
                min_length: None,
                max_length: None,
                enum: None,
                format: None,
              ),
            ),
          ),
          #(
            "age",
            schema.Integer(
              base(IntegerType),
              IntegerSchema(minimum: None, maximum: None, format: None),
            ),
          ),
        ]),
      ),
    ),
  ])
  |> generate
  |> birdie.snap(title: "codegen object all required")
}

pub fn object_mixed_required_test() {
  spec_with_schemas([
    #(
      "User",
      schema.Object(
        base(ObjectType),
        ObjectSchema(required: ["name"], properties: [
          #(
            "name",
            schema.String(
              base(StringType),
              StringSchema(
                min_length: None,
                max_length: None,
                enum: None,
                format: None,
              ),
            ),
          ),
          #(
            "email",
            schema.String(
              base(StringType),
              StringSchema(
                min_length: None,
                max_length: None,
                enum: None,
                format: None,
              ),
            ),
          ),
        ]),
      ),
    ),
  ])
  |> generate
  |> birdie.snap(title: "codegen object mixed required")
}

// --- Nullable / Optionality --------------------------------------------------

pub fn nullable_field_with_nullable_only_test() {
  let nullable_base =
    BaseSchema(
      type_name: StringType,
      title: None,
      description: None,
      nullable: True,
    )
  spec_with_schemas([
    #(
      "Config",
      schema.Object(
        base(ObjectType),
        ObjectSchema(required: [], properties: [
          #(
            "name",
            schema.String(
              base(StringType),
              StringSchema(
                min_length: None,
                max_length: None,
                enum: None,
                format: None,
              ),
            ),
          ),
          #(
            "label",
            schema.String(
              nullable_base,
              StringSchema(
                min_length: None,
                max_length: None,
                enum: None,
                format: None,
              ),
            ),
          ),
        ]),
      ),
    ),
  ])
  |> generate_with(codegen.NullableOnly)
  |> birdie.snap(title: "codegen nullable field with NullableOnly")
}

// --- Arrays ------------------------------------------------------------------

pub fn array_field_test() {
  spec_with_schemas([
    #(
      "TagList",
      schema.Object(
        base(ObjectType),
        ObjectSchema(required: ["tags"], properties: [
          #(
            "tags",
            schema.Array(
              base(schema.ArrayType),
              ArraySchema(
                min_items: None,
                max_items: None,
                items: schema.String(
                  base(StringType),
                  StringSchema(
                    min_length: None,
                    max_length: None,
                    enum: None,
                    format: None,
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    ),
  ])
  |> generate
  |> birdie.snap(title: "codegen array field")
}

// --- Refs --------------------------------------------------------------------

pub fn ref_field_test() {
  spec_with_schemas([
    #(
      "Pet",
      schema.Object(
        base(ObjectType),
        ObjectSchema(required: ["category"], properties: [
          #("category", schema.Ref(ref: "#/components/schemas/Category")),
        ]),
      ),
    ),
  ])
  |> generate
  |> birdie.snap(title: "codegen ref field")
}

// --- Descriptions / comments -------------------------------------------------

pub fn description_on_type_and_field_test() {
  let described_base =
    BaseSchema(
      type_name: ObjectType,
      title: None,
      description: Some("A user account."),
      nullable: False,
    )
  let described_field_base =
    BaseSchema(
      type_name: StringType,
      title: None,
      description: Some("The user's display name."),
      nullable: False,
    )
  spec_with_schemas([
    #(
      "User",
      schema.Object(
        described_base,
        ObjectSchema(required: ["name"], properties: [
          #(
            "name",
            schema.String(
              described_field_base,
              StringSchema(
                min_length: None,
                max_length: None,
                enum: None,
                format: None,
              ),
            ),
          ),
        ]),
      ),
    ),
  ])
  |> generate
  |> birdie.snap(title: "codegen description on type and field")
}

// --- String enum (currently falls back to String) ----------------------------

pub fn string_enum_field_test() {
  spec_with_schemas([
    #(
      "Order",
      schema.Object(
        base(ObjectType),
        ObjectSchema(required: ["status"], properties: [
          #(
            "status",
            schema.String(
              base(StringType),
              StringSchema(
                min_length: None,
                max_length: None,
                enum: Some(["pending", "approved", "delivered"]),
                format: None,
              ),
            ),
          ),
        ]),
      ),
    ),
  ])
  |> generate
  |> birdie.snap(title: "codegen string enum field")
}

pub fn top_level_string_enum_test() {
  spec_with_schemas([
    #(
      "OrderStatus",
      schema.String(
        base(StringType),
        StringSchema(
          min_length: None,
          max_length: None,
          enum: Some(["pending", "approved", "delivered"]),
          format: None,
        ),
      ),
    ),
  ])
  |> generate
  |> birdie.snap(title: "codegen top level string enum")
}

pub fn multiple_enums_test() {
  spec_with_schemas([
    #(
      "Pet",
      schema.Object(
        base(ObjectType),
        ObjectSchema(required: ["status", "size"], properties: [
          #(
            "status",
            schema.String(
              base(StringType),
              StringSchema(
                min_length: None,
                max_length: None,
                enum: Some(["available", "sold"]),
                format: None,
              ),
            ),
          ),
          #(
            "size",
            schema.String(
              base(StringType),
              StringSchema(
                min_length: None,
                max_length: None,
                enum: Some(["small", "medium", "large"]),
                format: None,
              ),
            ),
          ),
        ]),
      ),
    ),
  ])
  |> generate
  |> birdie.snap(title: "codegen multiple enums")
}

// --- Keyword escaping --------------------------------------------------------

pub fn keyword_field_name_test() {
  spec_with_schemas([
    #(
      "Resource",
      schema.Object(
        base(ObjectType),
        ObjectSchema(required: ["type"], properties: [
          #(
            "type",
            schema.String(
              base(StringType),
              StringSchema(
                min_length: None,
                max_length: None,
                enum: None,
                format: None,
              ),
            ),
          ),
        ]),
      ),
    ),
  ])
  |> generate
  |> birdie.snap(title: "codegen keyword field name")
}

// --- Boolean field ------------------------------------------------------------

pub fn boolean_field_test() {
  spec_with_schemas([
    #(
      "Feature",
      schema.Object(
        base(ObjectType),
        ObjectSchema(required: ["enabled"], properties: [
          #("enabled", schema.Boolean(base(BooleanType))),
        ]),
      ),
    ),
  ])
  |> generate
  |> birdie.snap(title: "codegen boolean field")
}
