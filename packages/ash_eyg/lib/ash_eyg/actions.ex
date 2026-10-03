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
  Actions with a required input of a type `AshEyg.Type` cannot map are not exposed.
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
    label =
      AshEyg.Domain.Info.name(domain) <>
        AshEyg.Resource.Info.name(resource) <> Macro.camelize(to_string(action.name))

    with {:ok, inputs} <- inputs(resource, action),
         {:ok, value} <- reply(resource, action) do
      lift = Type.record(Enum.map(inputs, &{&1.name, &1.eyg}))

      %Effect{
        label: label,
        lift: lift,
        lower: Type.result(value, :string),
        resource: resource,
        action: action.name,
        handle: fn {:record, fields}, opts ->
          params = decode(inputs, fields)

          case call(domain, resource, action, params, opts) do
            {:ok, value} -> {:tagged, "Ok", encode(resource, action, value)}
            {:error, error} -> {:tagged, "Error", {:string, message(error)}}
          end
        end
      }
      |> then(&{:ok, &1})
    end
  end

  defp inputs(resource, action) do
    key = primary_key(resource)

    keys =
      case action.type do
        type when type in [:update, :destroy] and not is_nil(key) ->
          [field(Ash.Resource.Info.attribute(resource, key), true)]

        type when type in [:update, :destroy] ->
          [:error]

        _ ->
          []
      end

    attributes =
      for name <- Map.get(action, :accept) || [] do
        attribute = Ash.Resource.Info.attribute(resource, name)
        required? = action.type == :create and required?(attribute)
        field(attribute, required?)
      end

    arguments =
      for argument <- action.arguments, argument.public? do
        field(argument, required?(argument))
      end

    Enum.reduce_while(keys ++ attributes ++ arguments, {:ok, []}, fn
      {:ok, field}, {:ok, fields} -> {:cont, {:ok, fields ++ [field]}}
      {:skip, _}, acc -> {:cont, acc}
      _, _ -> {:halt, :error}
    end)
  end

  defp required?(field), do: not field.allow_nil? and is_nil(field.default)

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
        if required?, do: :error, else: {:skip, field.name}
    end
  end

  defp reply(resource, action) do
    case action.type do
      :read -> {:ok, {:list, record_type(resource)}}
      type when type in [:create, :update] -> {:ok, record_type(resource)}
      :destroy -> {:ok, Type.unit()}
      :action when is_nil(action.returns) -> {:ok, Type.unit()}
      :action -> Type.eyg_type(action.returns, action.constraints, action.allow_nil?)
    end
  end

  defp record_type(resource) do
    Type.record(Enum.map(attributes(resource), &{&1.name, &1.eyg}))
  end

  # The primary key and public attributes of a resource, that EYG can represent.
  defp attributes(resource) do
    key = Ash.Resource.Info.primary_key(resource)

    resource
    |> Ash.Resource.Info.attributes()
    |> Enum.filter(&(&1.public? or &1.name in key))
    |> Enum.flat_map(fn attribute ->
      nullable? = attribute.allow_nil? and attribute.name not in key

      case Type.eyg_type(attribute.type, attribute.constraints, nullable?) do
        {:ok, eyg} ->
          [
            %{
              name: to_string(attribute.name),
              attribute: attribute,
              nullable?: nullable?,
              eyg: eyg
            }
          ]

        :error ->
          []
      end
    end)
  end

  defp primary_key(resource) do
    case Ash.Resource.Info.primary_key(resource) do
      [key] -> key
      _ -> nil
    end
  end

  defp decode(inputs, fields) do
    Enum.reduce(inputs, %{}, fn input, params ->
      case {input.optional?, Map.fetch!(fields, input.name)} do
        {true, {:tagged, "None", _}} ->
          params

        {_, value} ->
          value = Type.from_eyg(input.type, input.constraints, input.optional?, value)
          Map.put(params, input.key, value)
      end
    end)
  end

  defp call(domain, resource, action, params, opts) do
    opts = Keyword.put(opts, :domain, domain)

    case action.type do
      :read ->
        resource |> Ash.Query.for_read(action.name, params, opts) |> Ash.read(opts)

      :create ->
        resource |> Ash.Changeset.for_create(action.name, params, opts) |> Ash.create(opts)

      :update ->
        {id, params} = Map.pop(params, primary_key(resource))

        with {:ok, record} <- Ash.get(resource, id, opts) do
          record |> Ash.Changeset.for_update(action.name, params, opts) |> Ash.update(opts)
        end

      :destroy ->
        {id, params} = Map.pop(params, primary_key(resource))

        with {:ok, record} <- Ash.get(resource, id, opts),
             :ok <-
               record |> Ash.Changeset.for_destroy(action.name, params, opts) |> Ash.destroy(opts) do
          {:ok, nil}
        end

      :action ->
        case resource
             |> Ash.ActionInput.for_action(action.name, params, opts)
             |> Ash.run_action(opts) do
          :ok -> {:ok, nil}
          other -> other
        end
    end
  end

  defp encode(resource, action, value) do
    case action.type do
      :read -> {:linked_list, Enum.map(value, &encode_record(resource, &1))}
      type when type in [:create, :update] -> encode_record(resource, value)
      :destroy -> {:record, %{}}
      :action when is_nil(action.returns) -> {:record, %{}}
      :action -> Type.to_eyg(action.returns, action.constraints, action.allow_nil?, value)
    end
  end

  defp encode_record(resource, record) do
    fields =
      Map.new(attributes(resource), fn %{attribute: attribute} = field ->
        value = Map.get(record, attribute.name)
        {field.name, Type.to_eyg(attribute.type, attribute.constraints, field.nullable?, value)}
      end)

    {:record, fields}
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
