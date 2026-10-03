defmodule AshEyg.Type do
  @moduledoc """
  Maps Ash types to EYG types, and values between them.

  | Ash                                         | EYG                     |
  | ------------------------------------------- | ----------------------- |
  | `:integer`                                  | `Integer`               |
  | `:boolean`                                  | `True({}) \\| False({})` |
  | `:atom` with `one_of`                       | a union, `:open` is `Open({})` |
  | `{:array, type}`                            | `List(type)`            |
  | strings, uuids, decimals, floats, dates and times | `String`          |
  | a value that can be `nil`                   | `Some(type) \\| None({})` |

  Fields of any other type are not exposed.
  """

  @unit {:record, :empty}
  @strings [
    Ash.Type.String,
    Ash.Type.CiString,
    Ash.Type.UUID,
    Ash.Type.UUIDv7,
    Ash.Type.Date,
    Ash.Type.Time,
    Ash.Type.UtcDatetime,
    Ash.Type.UtcDatetimeUsec,
    Ash.Type.DateTime,
    Ash.Type.NaiveDatetime,
    Ash.Type.Decimal,
    Ash.Type.Float
  ]

  @doc "The unit type `{}`."
  def unit, do: @unit

  @doc "The EYG type of an Ash type, wrapped in an option when the value can be `nil`."
  def eyg_type(type, constraints, nullable?) do
    with {:ok, eyg} <- eyg_type(type, constraints) do
      {:ok, if(nullable?, do: option(eyg), else: eyg)}
    end
  end

  def eyg_type({:array, type}, constraints) do
    with {:ok, eyg} <- eyg_type(type, Keyword.get(constraints, :items, [])) do
      {:ok, {:list, eyg}}
    end
  end

  def eyg_type(type, constraints) do
    case base(type, constraints) do
      {type, _} when type in @strings ->
        {:ok, :string}

      {Ash.Type.Integer, _} ->
        {:ok, :integer}

      {Ash.Type.Boolean, _} ->
        {:ok, union([{"True", @unit}, {"False", @unit}])}

      {Ash.Type.Atom, constraints} ->
        case Keyword.get(constraints, :one_of) do
          nil -> {:ok, :string}
          atoms -> {:ok, union(Enum.map(atoms, &{tag(&1), @unit}))}
        end

      _ ->
        :error
    end
  end

  @doc "Encode an Ash value as an EYG value."
  def to_eyg(type, constraints, nullable?, value) do
    case {nullable?, value} do
      {true, nil} -> {:tagged, "None", {:record, %{}}}
      {true, value} -> {:tagged, "Some", to_eyg(type, constraints, value)}
      {false, value} -> to_eyg(type, constraints, value)
    end
  end

  def to_eyg({:array, type}, constraints, values) do
    items = Keyword.get(constraints, :items, [])
    {:linked_list, Enum.map(values, &to_eyg(type, items, &1))}
  end

  def to_eyg(type, constraints, value) do
    case base(type, constraints) do
      {Ash.Type.Integer, _} -> {:integer, value}
      {Ash.Type.Boolean, _} -> {:tagged, if(value, do: "True", else: "False"), {:record, %{}}}
      {Ash.Type.Atom, _} when is_atom(value) -> atom_to_eyg(value, constraints)
      {_, _} -> {:string, to_string(value)}
    end
  end

  defp atom_to_eyg(value, constraints) do
    case Keyword.get(constraints, :one_of) do
      nil -> {:string, Atom.to_string(value)}
      _ -> {:tagged, tag(value), {:record, %{}}}
    end
  end

  @doc "Decode an EYG value as input to an Ash action."
  def from_eyg(type, constraints, nullable?, value) do
    case {nullable?, value} do
      {true, {:tagged, "None", _}} -> nil
      {true, {:tagged, "Some", value}} -> from_eyg(type, constraints, value)
      {false, value} -> from_eyg(type, constraints, value)
    end
  end

  def from_eyg({:array, type}, constraints, {:linked_list, values}) do
    items = Keyword.get(constraints, :items, [])
    Enum.map(values, &from_eyg(type, items, &1))
  end

  def from_eyg(type, constraints, value) do
    case {base(type, constraints), value} do
      {_, {:integer, value}} -> value
      {_, {:string, value}} -> value
      {{Ash.Type.Boolean, _}, {:tagged, tag, _}} -> tag == "True"
      {{Ash.Type.Atom, constraints}, {:tagged, tag, _}} -> tag_to_atom(tag, constraints)
    end
  end

  defp tag_to_atom(tag, constraints) do
    constraints |> Keyword.fetch!(:one_of) |> Enum.find(&(tag(&1) == tag))
  end

  defp base(type, constraints) do
    type = Ash.Type.get_type(type)

    if Ash.Type.NewType.new_type?(type) do
      base(Ash.Type.NewType.subtype_of(type), Ash.Type.NewType.constraints(type, constraints))
    else
      {type, constraints}
    end
  end

  defp tag(atom), do: atom |> Atom.to_string() |> Macro.camelize()

  @doc "The type of a record with these fields."
  def record(fields), do: :eyg_beam.record_type(fields)

  @doc "The type of a union with these variants."
  def union(variants), do: :eyg_beam.union_type(variants)

  @doc "The type of a value that may be missing."
  def option(type), do: union([{"Some", type}, {"None", @unit}])

  @doc "The type of a result."
  def result(value, reason), do: :eyg_beam.result_type(value, reason)
end
