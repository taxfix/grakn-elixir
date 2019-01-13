defmodule Grakn.Graql do
  @moduledoc false

  alias Grakn.Query

  defmodule Datatypes do
    @moduledoc false

    defstruct string: :string,
              long: :long,
              double: :double,
              boolean: :boolean,
              date: :date
  end

  defmacro __using__([]) do
    quote do
      import Grakn.Graql
    end
  end

  def datatypes, do: %Datatypes{}

  defmacro pattern("$" <> var, isa: entity_type) do
    quote do
      Query.graql("$#{unquote(var)} isa #{unquote(entity_type)};")
    end
  end

  defmacro pattern("$" <> var, isa: entity_type, has: attributes) do
    quote do
      Query.graql(
        "$#{unquote(var)} isa #{unquote(entity_type)} #{unquote(expand_key_values(attributes))};"
      )
    end
  end

  defmacro define(label, [sub: :entity] = opts), do: define_body(label, opts)
  defmacro define(label, [sub: :entity, has: _] = opts), do: define_body(label, opts)
  defmacro define(label, [sub: :entity, plays: _] = opts), do: define_body(label, opts)
  defmacro define(label, [sub: :entity, has: _, plays: _] = opts), do: define_body(label, opts)
  defmacro define(label, [sub: :entity, plays: _, has: _] = opts), do: define_body(label, opts)
  defmacro define(label, sub: :attribute), do: define_body(label, sub: :attribute)
  defmacro define(label, [sub: :attribute, datatype: _] = opts), do: define_body(label, opts)
  defmacro define(label, [sub: :relationship, relates: _] = opts), do: define_body(label, opts)

  defmacro define(label, [sub: :relationship, relates: _, has: _] = opts),
    do: define_body(label, opts)

  # Rules
  defmacro define(label, [sub: :rule, when: body, then: head] = opts) do
    body_patterns =
      body
      |> List.wrap()
      |> Enum.map(fn
        %Grakn.Query{graql: pattern} -> pattern
        string_pattern when is_bitstring(string_pattern) -> string_pattern
        _ -> error(label, opts)
      end)

    head_patterns =
      head
      |> List.wrap()
      |> Enum.map(fn
        %Grakn.Query{graql: pattern} -> pattern
        string_pattern when is_bitstring(string_pattern) -> string_pattern
        _ -> error(label, opts)
      end)

    quote do
      Query.graql(
        "define #{unquote(label)} sub rule, when { #{unquote(body_patterns)} } then { #{
          unquote(head_patterns)
        } };"
      )
    end
  end

  # Allow any arbitrary sub types
  defmacro define(label, [sub: _type] = opts), do: define_body(label, opts)
  defmacro define(label, [sub: _type, has: _] = opts), do: define_body(label, opts)
  defmacro define(label, [sub: _type, plays: _] = opts), do: define_body(label, opts)
  defmacro define(label, [sub: _type, has: _, plays: _] = opts), do: define_body(label, opts)
  defmacro define(label, [sub: _type, plays: _, has: _] = opts), do: define_body(label, opts)
  defmacro define(label, [sub: _type, relates: _] = opts), do: define_body(label, opts)

  defmacro define(label, opts), do: error(label, opts)

  defp error(label, opts), do: raise("Graql compile error: #{inspect({label, opts})}")

  defp define_body(label, opts) do
    quote do
      modifiers =
        unquote(opts)
        |> Enum.map(&expand_key_values/1)
        |> Enum.join(", ")

      Query.graql("define #{unquote(label)} #{modifiers};")
    end
  end

  def expand_key_values({key, [_ | _] = values}) do
    values
    |> Enum.map(fn value -> "#{key} #{value}" end)
    |> Enum.join(", ")
  end

  def expand_key_values({key, value}), do: "#{key} #{value}"
end
