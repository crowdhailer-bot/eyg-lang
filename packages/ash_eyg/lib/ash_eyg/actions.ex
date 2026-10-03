defmodule AshEyg.Actions do
  @moduledoc """
  Builds an effect for every action of the exposed resources in a domain.

  | Action    | Lift                                   | Reply                             |
  | --------- | -------------------------------------- | --------------------------------- |
  | `read`    | arguments                              | `Result(List(record), String)`    |
  | `create`  | accepted attributes and arguments      | `Result(record, String)`          |
  | `update`  | primary key, attributes and arguments  | `Result(record, String)`          |
  | `destroy` | primary key and arguments              | `Result({}, String)`              |
  | `action`  | arguments                              | `Result(returns, String)`         |

  A record has the primary key and public attributes of the resource.
  An input that is not required is an option, `None({})` leaves it out.
  Fields of a type `AshEyg.Type` cannot map are left out,
  an action with such a required input is not exposed.
  """

  alias AshEyg.{Effect, Type}

  @doc "Every effect of the exposed resources in a domain."
  def effects(domain) do
    for resource <- Ash.Domain.Info.resources(domain),
        AshEyg.Resource in Spark.extensions(resource),
        AshEyg.Resource.Info.eyg_expose?(resource),
        action <- Ash.Resource.Info.actions(resource),
        {:ok, effect} <- [effect(domain, resource, action)],
        do: effect
  end

  @doc "The effect for one action, or `:error` if the action cannot be exposed."
  def effect(domain, resource, action) do
    with {:ok, inputs} <- inputs(resource, action),
         {:ok, {reply, encode}} <- reply(resource, action) do
      {:ok,
       %Effect{
         label:
           AshEyg.Domain.Info.name(domain) <>
             AshEyg.Resource.Info.name(resource) <> Macro.camelize(to_string(action.name)),
         lift: record_type(inputs),
         lower: Type.result(reply, :string),
         resource: resource,
         action: action.name,
         handle: fn {:record, fields}, opts ->
           case call(domain, resource, action, decode(inputs, fields), opts) do
             {:ok, value} -> {:tagged, "Ok", encode.(value)}
             {:error, error} -> {:tagged, "Error", {:string, message(error)}}
           end
         end
       }}
    end
  end

  # A field is an input or attribute EYG can represent, optional fields are options.
  defp field(field, required?) do
    case Type.eyg_type(field.type, field.constraints, not required?) do
      {:ok, eyg} ->
        {:ok,
         %{
           name: to_string(field.name),
           key: field.name,
           type: field.type,
           constraints: field.constraints,
           optional?: not required?,
           eyg: eyg
         }}

      :error ->
        if required?, do: :error, else: :skip
    end
  end

  defp required?(field), do: not field.allow_nil? and is_nil(field.default)

  defp record_type(fields), do: Type.record(Enum.map(fields, &{&1.name, &1.eyg}))

  defp inputs(resource, action) do
    attributes =
      for name <- Map.get(action, :accept) || [] do
        attribute = Ash.Resource.Info.attribute(resource, name)
        field(attribute, action.type == :create and required?(attribute))
      end

    arguments =
      for argument <- action.arguments, argument.public?, do: field(argument, required?(argument))

    with {:ok, keys} <- keys(resource, action) do
      Enum.reduce_while(attributes ++ arguments, {:ok, keys}, fn
        {:ok, field}, {:ok, fields} -> {:cont, {:ok, fields ++ [field]}}
        :skip, acc -> {:cont, acc}
        :error, _ -> {:halt, :error}
      end)
    end
  end

  # Updates and destroys find their record by a single field primary key.
  defp keys(resource, %{type: type}) when type in [:update, :destroy] do
    case Ash.Resource.Info.primary_key(resource) do
      [key] ->
        with {:ok, field} <- field(Ash.Resource.Info.attribute(resource, key), true),
             do: {:ok, [field]}

      _ ->
        :error
    end
  end

  defp keys(_resource, _action), do: {:ok, []}

  # The type of a successful reply and a function to encode it.
  defp reply(resource, action) do
    attributes = attributes(resource)

    record =
      &{:record,
       Map.new(attributes, fn field -> {field.name, to_eyg(field, Map.get(&1, field.key))} end)}

    unit = {Type.unit(), fn _ -> {:record, %{}} end}

    case action.type do
      :read ->
        {:ok, {{:list, record_type(attributes)}, &{:linked_list, Enum.map(&1, record)}}}

      type when type in [:create, :update] ->
        {:ok, {record_type(attributes), record}}

      :destroy ->
        {:ok, unit}

      :action when is_nil(action.returns) ->
        {:ok, unit}

      :action ->
        %{returns: type, constraints: constraints, allow_nil?: optional?} = action

        with {:ok, eyg} <- Type.eyg_type(type, constraints, optional?),
             do: {:ok, {eyg, &Type.to_eyg(type, constraints, optional?, &1)}}
    end
  end

  # The primary key and public attributes of a resource.
  defp attributes(resource) do
    key = Ash.Resource.Info.primary_key(resource)

    for attribute <- Ash.Resource.Info.attributes(resource),
        attribute.public? or attribute.name in key,
        {:ok, field} <- [field(attribute, not attribute.allow_nil? or attribute.name in key)],
        do: field
  end

  defp to_eyg(field, value),
    do: Type.to_eyg(field.type, field.constraints, field.optional?, value)

  defp decode(inputs, fields) do
    for input <- inputs,
        value = Map.fetch!(fields, input.name),
        not (input.optional? and match?({:tagged, "None", _}, value)),
        into: %{},
        do: {input.key, Type.from_eyg(input.type, input.constraints, input.optional?, value)}
  end

  defp call(domain, resource, action, params, opts) do
    opts = Keyword.put(opts, :domain, domain)

    case action.type do
      :read ->
        resource |> Ash.Query.for_read(action.name, params, opts) |> Ash.read(opts)

      :create ->
        resource |> Ash.Changeset.for_create(action.name, params, opts) |> Ash.create(opts)

      :update ->
        {id, params} = Map.pop(params, hd(Ash.Resource.Info.primary_key(resource)))

        with {:ok, record} <- Ash.get(resource, id, opts) do
          record |> Ash.Changeset.for_update(action.name, params, opts) |> Ash.update(opts)
        end

      :destroy ->
        {id, params} = Map.pop(params, hd(Ash.Resource.Info.primary_key(resource)))

        with {:ok, record} <- Ash.get(resource, id, opts),
             :ok <-
               record |> Ash.Changeset.for_destroy(action.name, params, opts) |> Ash.destroy(opts),
             do: {:ok, nil}

      :action ->
        case resource
             |> Ash.ActionInput.for_action(action.name, params, opts)
             |> Ash.run_action(opts) do
          :ok -> {:ok, nil}
          other -> other
        end
    end
  end

  defp message(error) do
    error
    |> Ash.Error.to_error_class()
    |> Map.get(:errors, [])
    |> Enum.map_join("\n", fn error ->
      # Bread crumbs describe where in Ash the error happened, not what a program did wrong.
      error |> Map.replace(:bread_crumbs, []) |> Exception.message()
    end)
  end
end
