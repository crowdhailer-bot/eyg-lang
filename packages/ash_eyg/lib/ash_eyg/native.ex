defmodule AshEyg.Native do
  @moduledoc false

  # Bind Ash metadata and host values. Type conversion and action signatures
  # are built in Gleam, without allocating atoms from script text.
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

  def shape({:array, type}, constraints) do
    with {:ok, item} <- shape(type, Keyword.get(constraints, :items, [])),
         do: {:ok, {:array, item}}
  end

  def shape(type, constraints) do
    type = Ash.Type.get_type(type)

    cond do
      Ash.Type.NewType.new_type?(type) ->
        shape(Ash.Type.NewType.subtype_of(type), Ash.Type.NewType.constraints(type, constraints))

      type in @strings ->
        {:ok, :text}

      type == Ash.Type.Integer ->
        {:ok, :integer}

      type == Ash.Type.Boolean ->
        {:ok, :boolean}

      type == Ash.Type.Atom ->
        case Keyword.get(constraints, :one_of) do
          nil -> {:ok, :text}
          atoms -> {:ok, {:choice, Enum.map(atoms, &{Macro.camelize(to_string(&1)), &1})}}
        end

      true ->
        {:error, nil}
    end
  end

  def descriptor(domain, resource, action) do
    attributes = Ash.Resource.Info.attributes(resource)
    keys = Ash.Resource.Info.primary_key(resource)

    key_inputs =
      if action.type in [:update, :destroy],
        do: Enum.map(keys, &metadata_field(Ash.Resource.Info.attribute(resource, &1), true)),
        else: []

    accepted =
      for key <- Map.get(action, :accept) || [] do
        attribute = Ash.Resource.Info.attribute(resource, key)
        metadata_field(attribute, action.type == :create and required?(attribute))
      end

    arguments =
      for argument <- action.arguments,
          argument.public?,
          do: metadata_field(argument, required?(argument))

    outputs =
      for attribute <- attributes,
          attribute.public? or attribute.name in keys,
          do: metadata_field(attribute, not attribute.allow_nil? or attribute.name in keys)

    returns = Map.get(action, :returns)
    kind = if action.type == :action, do: :generic, else: action.type

    {:descriptor,
     AshEyg.Domain.Info.name(domain) <>
       AshEyg.Resource.Info.name(resource) <> Macro.camelize(to_string(action.name)), resource,
     {domain, action}, kind, action.type not in [:update, :destroy] or length(keys) == 1,
     key_inputs ++ accepted ++ arguments, outputs,
     if(is_nil(returns), do: {:error, nil}, else: shape(returns, action.constraints)),
     Map.get(action, :allow_nil?, false), is_nil(returns)}
  end

  defp metadata_field(field, required),
    do:
      {:field, to_string(field.name), field.name, shape(field.type, field.constraints), required}

  defp required?(field), do: not field.allow_nil? and is_nil(field.default)

  def call({:descriptor, _, resource, {domain, action}, _, _, _, _, _, _, _}, params, opts) do
    params = Map.new(params)
    opts = Keyword.put(opts, :domain, domain)

    result =
      case action.type do
        :read ->
          resource |> Ash.Query.for_read(action.name, params, opts) |> Ash.read(opts)

        :create ->
          resource |> Ash.Changeset.for_create(action.name, params, opts) |> Ash.create(opts)

        :update ->
          {id, params} = Map.pop(params, hd(Ash.Resource.Info.primary_key(resource)))

          with {:ok, record} <- Ash.get(resource, id, opts),
               do:
                 record |> Ash.Changeset.for_update(action.name, params, opts) |> Ash.update(opts)

        :destroy ->
          {id, params} = Map.pop(params, hd(Ash.Resource.Info.primary_key(resource)))

          with {:ok, record} <- Ash.get(resource, id, opts),
               :ok <-
                 record
                 |> Ash.Changeset.for_destroy(action.name, params, opts)
                 |> Ash.destroy(opts),
               do: {:ok, nil}

        :action ->
          case resource
               |> Ash.ActionInput.for_action(action.name, params, opts)
               |> Ash.run_action(opts) do
            :ok -> {:ok, nil}
            other -> other
          end
      end

    case result do
      {:error, reason} -> {:error, error_message(reason)}
      other -> other
    end
  end

  defp error_message(error) do
    error
    |> Ash.Error.to_error_class()
    |> Map.get(:errors, [])
    |> Enum.map_join("\n", &(&1 |> Map.replace(:bread_crumbs, []) |> Exception.message()))
  end

  def field(value, key), do: Map.get(value, key)
  def is_null(value), do: is_nil(value)
  def null, do: nil
  def text(value), do: to_string(value)
  def integer(value) when is_integer(value), do: value
  def boolean(value) when is_boolean(value), do: value
  def values(value) when is_list(value), do: value
  def identity(value), do: value

  def effect(%AshEyg.Effect{label: label, lift: lift, lower: lower, handle: handle}),
    do: {:effect, label, lift, lower, handle}

  def effects(opts), do: Keyword.fetch!(opts, :effects)
  def options(opts), do: Keyword.take(opts, [:actor, :tenant, :context])
end
