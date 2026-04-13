import birdie
import gilly/internal/codegen
import gilly/openapi/openapi.{
  type OpenAPI, type PathItem, Components, Info, OpenAPI, PathItem,
}
import gilly/openapi/operation.{
  type Operation, MediaType, Operation, Parameter, Path, Query, RequestBody,
  Response,
}
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
    servers: [],
    paths: [],
    components: Some(Components(schemas:)),
  )
}

fn default_config() -> codegen.Config {
  codegen.Config(
    optionality: codegen.RequiredOnly,
    indent: 2,
    optional_query_params: False,
  )
}

fn generate(spec: OpenAPI) -> String {
  codegen.generate_schemas(spec, default_config())
}

fn generate_with(spec: OpenAPI, optionality: codegen.Optionality) -> String {
  let config = default_config()
  codegen.generate_schemas(spec, codegen.Config(..config, optionality:))
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

// --- Operation generation ----------------------------------------------------

fn empty_path_item() -> PathItem {
  PathItem(get: None, post: None, put: None, delete: None, patch: None)
}

fn empty_operation(operation_id: String) -> Operation {
  Operation(
    operation_id: Some(operation_id),
    summary: None,
    description: None,
    tags: [],
    parameters: [],
    request_body: None,
    responses: [],
  )
}

fn spec_with_paths(
  paths: List(#(String, PathItem)),
  schemas: List(#(String, schema.Schema)),
) -> OpenAPI {
  OpenAPI(
    version: v3(),
    info: Info(title: "Test", version: "1.0.0", description: None),
    servers: [],
    paths: paths,
    components: Some(Components(schemas:)),
  )
}

fn generate_ops(spec: OpenAPI) -> String {
  codegen.generate_operations(spec, default_config())
}

pub fn simple_get_no_params_test() {
  spec_with_paths(
    [
      #(
        "/store/inventory",
        PathItem(
          ..empty_path_item(),
          get: Some(
            Operation(
              ..empty_operation("getInventory"),
              summary: Some("Returns pet inventories"),
            ),
          ),
        ),
      ),
    ],
    [],
  )
  |> generate_ops
  |> birdie.snap(title: "codegen operation simple get no params")
}

pub fn get_with_path_param_test() {
  spec_with_paths(
    [
      #(
        "/pet/{petId}",
        PathItem(
          ..empty_path_item(),
          get: Some(
            Operation(
              ..empty_operation("getPetById"),
              summary: Some("Find pet by ID"),
              parameters: [
                Parameter(
                  name: "petId",
                  in_: Path,
                  description: Some("ID of pet to return"),
                  required: True,
                  schema: Some(schema.Integer(
                    base(IntegerType),
                    IntegerSchema(minimum: None, maximum: None, format: None),
                  )),
                ),
              ],
              responses: [
                #(
                  "200",
                  Response(description: "successful operation", content: [
                    #(
                      "application/json",
                      MediaType(
                        schema: Some(schema.Ref(ref: "#/components/schemas/Pet")),
                      ),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
    [
      #(
        "Pet",
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
          ]),
        ),
      ),
    ],
  )
  |> generate_ops
  |> birdie.snap(title: "codegen operation get with path param")
}

pub fn get_with_query_param_test() {
  spec_with_paths(
    [
      #(
        "/pet/findByStatus",
        PathItem(
          ..empty_path_item(),
          get: Some(
            Operation(
              ..empty_operation("findPetsByStatus"),
              summary: Some("Finds pets by status"),
              parameters: [
                Parameter(
                  name: "status",
                  in_: Query,
                  description: Some("Status values"),
                  required: True,
                  schema: Some(schema.String(
                    base(StringType),
                    StringSchema(
                      min_length: None,
                      max_length: None,
                      enum: None,
                      format: None,
                    ),
                  )),
                ),
              ],
              responses: [
                #(
                  "200",
                  Response(description: "successful operation", content: [
                    #(
                      "application/json",
                      MediaType(
                        schema: Some(schema.Array(
                          base(schema.ArrayType),
                          ArraySchema(
                            min_items: None,
                            max_items: None,
                            items: schema.Ref(ref: "#/components/schemas/Pet"),
                          ),
                        )),
                      ),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
    [
      #(
        "Pet",
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
          ]),
        ),
      ),
    ],
  )
  |> generate_ops
  |> birdie.snap(title: "codegen operation get with query param")
}

pub fn post_with_request_body_test() {
  spec_with_paths(
    [
      #(
        "/pet",
        PathItem(
          ..empty_path_item(),
          post: Some(
            Operation(
              ..empty_operation("addPet"),
              summary: Some("Add a new pet"),
              request_body: Some(
                RequestBody(
                  description: Some("Pet object"),
                  required: True,
                  content: [
                    #(
                      "application/json",
                      MediaType(
                        schema: Some(schema.Ref(ref: "#/components/schemas/Pet")),
                      ),
                    ),
                  ],
                ),
              ),
              responses: [
                #(
                  "200",
                  Response(description: "Successful operation", content: [
                    #(
                      "application/json",
                      MediaType(
                        schema: Some(schema.Ref(ref: "#/components/schemas/Pet")),
                      ),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
    [
      #(
        "Pet",
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
          ]),
        ),
      ),
    ],
  )
  |> generate_ops
  |> birdie.snap(title: "codegen operation post with request body")
}

pub fn post_with_inline_request_body_test() {
  spec_with_paths(
    [
      #(
        "/containers/{region}/containers",
        PathItem(
          ..empty_path_item(),
          post: Some(
            Operation(
              ..empty_operation("createContainer"),
              summary: Some("Create a new container"),
              parameters: [
                Parameter(
                  name: "region",
                  in_: Path,
                  description: Some("The region you want to target"),
                  required: True,
                  schema: Some(schema.String(
                    base(StringType),
                    StringSchema(
                      min_length: None,
                      max_length: None,
                      enum: None,
                      format: None,
                    ),
                  )),
                ),
              ],
              request_body: Some(
                RequestBody(
                  description: Some("Container creation request"),
                  required: True,
                  content: [
                    #(
                      "application/json",
                      MediaType(
                        schema: Some(schema.Object(
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
                              "description",
                              schema.String(
                                BaseSchema(..base(StringType), nullable: True),
                                StringSchema(
                                  min_length: None,
                                  max_length: None,
                                  enum: None,
                                  format: None,
                                ),
                              ),
                            ),
                            #(
                              "min_scale",
                              schema.Integer(
                                BaseSchema(..base(IntegerType), nullable: True),
                                IntegerSchema(
                                  minimum: None,
                                  maximum: None,
                                  format: None,
                                ),
                              ),
                            ),
                          ]),
                        )),
                      ),
                    ),
                  ],
                ),
              ),
              responses: [
                #(
                  "200",
                  Response(description: "Successful operation", content: [
                    #(
                      "application/json",
                      MediaType(
                        schema: Some(schema.Ref(
                          ref: "#/components/schemas/Container",
                        )),
                      ),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
    [
      #(
        "Container",
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
          ]),
        ),
      ),
    ],
  )
  |> generate_ops
  |> birdie.snap(title: "codegen operation post with inline request body")
}

pub fn delete_with_path_param_test() {
  spec_with_paths(
    [
      #(
        "/pet/{petId}",
        PathItem(
          ..empty_path_item(),
          delete: Some(
            Operation(
              ..empty_operation("deletePet"),
              summary: Some("Deletes a pet"),
              parameters: [
                Parameter(
                  name: "petId",
                  in_: Path,
                  description: None,
                  required: True,
                  schema: Some(schema.Integer(
                    base(IntegerType),
                    IntegerSchema(minimum: None, maximum: None, format: None),
                  )),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
    [],
  )
  |> generate_ops
  |> birdie.snap(title: "codegen operation delete with path param")
}

pub fn get_with_optional_query_params_test() {
  spec_with_paths(
    [
      #(
        "/containers",
        PathItem(
          ..empty_path_item(),
          get: Some(
            Operation(
              ..empty_operation("listContainers"),
              summary: Some("List containers"),
              parameters: [
                Parameter(
                  name: "name",
                  in_: Query,
                  description: None,
                  required: False,
                  schema: Some(schema.String(
                    base(StringType),
                    StringSchema(
                      min_length: None,
                      max_length: None,
                      enum: None,
                      format: None,
                    ),
                  )),
                ),
                Parameter(
                  name: "page",
                  in_: Query,
                  description: None,
                  required: False,
                  schema: Some(schema.Integer(
                    base(IntegerType),
                    IntegerSchema(minimum: None, maximum: None, format: None),
                  )),
                ),
              ],
              responses: [
                #(
                  "200",
                  Response(description: "successful operation", content: []),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
    [],
  )
  |> generate_ops
  |> birdie.snap(title: "codegen operation get with optional query params")
}

pub fn get_with_mixed_path_and_query_params_test() {
  spec_with_paths(
    [
      #(
        "/regions/{region}/containers",
        PathItem(
          ..empty_path_item(),
          get: Some(
            Operation(
              ..empty_operation("listRegionContainers"),
              summary: Some("List containers in region"),
              parameters: [
                Parameter(
                  name: "region",
                  in_: Path,
                  description: None,
                  required: True,
                  schema: Some(schema.String(
                    base(StringType),
                    StringSchema(
                      min_length: None,
                      max_length: None,
                      enum: None,
                      format: None,
                    ),
                  )),
                ),
                Parameter(
                  name: "page",
                  in_: Query,
                  description: None,
                  required: False,
                  schema: Some(schema.Integer(
                    base(IntegerType),
                    IntegerSchema(minimum: None, maximum: None, format: None),
                  )),
                ),
                Parameter(
                  name: "page_size",
                  in_: Query,
                  description: None,
                  required: False,
                  schema: Some(schema.Integer(
                    base(IntegerType),
                    IntegerSchema(minimum: None, maximum: None, format: None),
                  )),
                ),
                Parameter(
                  name: "name",
                  in_: Query,
                  description: None,
                  required: False,
                  schema: Some(schema.String(
                    base(StringType),
                    StringSchema(
                      min_length: None,
                      max_length: None,
                      enum: None,
                      format: None,
                    ),
                  )),
                ),
              ],
              responses: [
                #(
                  "200",
                  Response(description: "successful operation", content: []),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
    [],
  )
  |> generate_ops
  |> birdie.snap(
    title: "codegen operation get with mixed path and query params",
  )
}

pub fn get_with_required_integer_query_param_test() {
  spec_with_paths(
    [
      #(
        "/items",
        PathItem(
          ..empty_path_item(),
          get: Some(
            Operation(
              ..empty_operation("listItems"),
              summary: Some("List items"),
              parameters: [
                Parameter(
                  name: "limit",
                  in_: Query,
                  description: Some("Maximum number of items"),
                  required: True,
                  schema: Some(schema.Integer(
                    base(IntegerType),
                    IntegerSchema(minimum: None, maximum: None, format: None),
                  )),
                ),
              ],
              responses: [
                #(
                  "200",
                  Response(description: "successful operation", content: []),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
    [],
  )
  |> generate_ops
  |> birdie.snap(
    title: "codegen operation get with required integer query param",
  )
}

pub fn get_with_array_query_param_test() {
  spec_with_paths(
    [
      #(
        "/pet/findByTags",
        PathItem(
          ..empty_path_item(),
          get: Some(
            Operation(
              ..empty_operation("findPetsByTags"),
              summary: Some("Find pets by tags"),
              parameters: [
                Parameter(
                  name: "tags",
                  in_: Query,
                  description: Some("Tags to filter by"),
                  required: True,
                  schema: Some(schema.Array(
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
                  )),
                ),
              ],
              responses: [
                #(
                  "200",
                  Response(description: "successful operation", content: []),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
    [],
  )
  |> generate_ops
  |> birdie.snap(title: "codegen operation get with array query param")
}
