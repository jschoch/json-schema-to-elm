defmodule JS2E.Printers.AnyOfPrinter do
  @moduledoc """
  A printer for printing an 'any of' type decoder.
  """

  @templates_location Application.get_env(:js2e, :templates_location)
  @type_location Path.join(@templates_location, "any_of/type.elm.eex")
  @decoder_location Path.join(@templates_location, "any_of/decoder.elm.eex")
  @encoder_location Path.join(@templates_location, "any_of/encoder.elm.eex")

  require Elixir.{EEx, Logger}
  import JS2E.Printers.Util
  alias JS2E.{Printer, TypePath, Types}
  alias JS2E.Types.AnyOfType

  EEx.function_from_file(:defp, :type_template, @type_location,
    [:type_name, :fields])

  EEx.function_from_file(:defp, :decoder_template, @decoder_location,
    [:decoder_name, :type_name, :clauses])

  EEx.function_from_file(:defp, :encoder_template, @encoder_location,
    [:encoder_name, :type_name, :argument_name, :properties])

  @spec print_type(
    Types.typeDefinition,
    Types.typeDictionary,
    Types.schemaDictionary
  ) :: String.t
  def print_type(%AnyOfType{name: name,
                            path: _path,
                            types: types}, type_dict, schema_dict) do

    type_name = upcase_first name
    fields = create_type_fields(types, type_dict, schema_dict)

    type_template(type_name, fields)
  end

  @spec create_type_fields(
    [TypePath.t],
    Types.typeDictionary,
    Types.schemaDictionary
  ) :: [map]
  defp create_type_fields(types, type_dict, schema_dict) do
    types
    |> Enum.map(&(create_type_field(&1, type_dict, schema_dict)))
  end

  @spec create_type_field(
    TypePath.t,
    Types.typeDictionary,
    Types.schemaDictionary
  ) :: map
  defp create_type_field(type_path, type_dict, schema_dict) do

    field_type =
      type_path
      |> Printer.resolve_type(type_dict, schema_dict)
      |> create_type_name

    field_name = downcase_first field_type

    %{name: field_name,
      type: "Maybe #{field_type}"}
  end

  @spec create_type_name(Types.typeDefinition) :: String.t
  defp create_type_name(property_type) do

    if primitive_type?(property_type) do
      property_type_value = property_type.type

      case property_type_value do
        "integer" ->
          "Int"

        "number" ->
          "Float"

        _ ->
          upcase_first property_type_value
      end

    else
      property_type_name = upcase_first property_type.name
    end
  end

  @spec print_decoder(
    Types.typeDefinition,
    Types.typeDictionary,
    Types.schemaDictionary
  ) :: String.t
  def print_decoder(%AnyOfType{name: name,
                               path: _path,
                               types: type_paths},
    type_dict, schema_dict) do

    decoder_name = "#{name}Decoder"
    type_name = upcase_first name
    clauses = create_decoder_clauses(type_paths, type_dict, schema_dict)

    decoder_template(decoder_name, type_name, clauses)
  end

  @spec create_decoder_clauses(
    [TypePath.t],
    Types.typeDictionary,
    Types.schemaDictionary
  ) :: [map]
  defp create_decoder_clauses(type_paths, type_dict, schema_dict) do

    type_paths
    |> Enum.map(fn type_path ->
      create_decoder_property(type_path, type_dict, schema_dict)
    end)
  end

  @spec create_decoder_property(
    TypePath.t,
    Types.typeDictionary,
    Types.schemaDictionary
  ) :: map
  defp create_decoder_property(type_path, type_dict, schema_dict) do

    property_type =
      type_path
      |> Printer.resolve_type(type_dict, schema_dict)

    property_name = property_type.name
    decoder_name = create_decoder_name(property_type)

    cond do
      union_type?(property_type) || one_of_type?(property_type) ->
        create_decoder_union_clause(property_name, decoder_name)

      enum_type?(property_type) ->
        property_type_decoder =
          property_type.type
          |> determine_primitive_type_decoder()

        create_decoder_enum_clause(
          property_name, property_type_decoder, decoder_name)

      true ->
        create_decoder_normal_clause(property_name, decoder_name)
    end
  end

  @spec determine_primitive_type_decoder(String.t) :: String.t
  defp determine_primitive_type_decoder(property_type_value) do
    case property_type_value do
      "integer" ->
        "Decode.int"

      "number" ->
        "Decode.float"

      _ ->
        "Decode.#{property_type_value}"
    end
  end

  @spec create_decoder_name(Types.typeDefinition) :: String.t
  defp create_decoder_name(property_type) do

    if primitive_type?(property_type) do
      determine_primitive_type_decoder(property_type.type)
    else
      property_type_name = property_type.name
      "#{property_type_name}Decoder"
    end
  end

  defp create_decoder_union_clause(property_name, decoder_name) do
    %{property_name: property_name,
      decoder_name: decoder_name}
  end

  defp create_decoder_enum_clause(property_name,
    property_type_decoder, decoder_name) do

    %{property_name: property_name,
      property_decoder: property_type_decoder,
      decoder_name: decoder_name}
  end

  defp create_decoder_normal_clause(property_name, decoder_name) do
    %{property_name: property_name,
    decoder_name: decoder_name}
  end

  @spec print_encoder(
    Types.typeDefinition,
    Types.typeDictionary,
    Types.schemaDictionary
  ) :: String.t
  def print_encoder(%AnyOfType{name: name,
                               path: _path,
                               types: type_paths},
    type_dict, schema_dict) do

    type_name = upcase_first name
    encoder_name = "encode#{type_name}"
    argument_name = downcase_first type_name

    properties = create_encoder_properties(type_paths, type_dict, schema_dict)

    template = encoder_template(encoder_name, type_name,
      argument_name, properties)
    trim_newlines(template)
  end

  defp create_encoder_properties(type_paths, type_dict, schema_dict) do

      type_paths
      |> Enum.map(fn type_path ->
      Printer.resolve_type(type_path, type_dict, schema_dict)
    end)
      |> Enum.reduce([], fn (property, properties) ->
        encoder_name = create_encoder_name(property)
        updated_property = Map.put(property, :encoder_name, encoder_name)
        properties ++ [updated_property]
      end)
  end

end
