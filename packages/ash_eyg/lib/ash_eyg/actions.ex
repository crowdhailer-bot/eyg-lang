defmodule AshEyg.Actions do
  @moduledoc "Derive typed effects through Gleam from Ash resource metadata."
  def effects(domain) do
    for resource <- Ash.Domain.Info.resources(domain),
        AshEyg.Resource in Spark.extensions(resource),
        AshEyg.Resource.Info.eyg_expose?(resource),
        action <- Ash.Resource.Info.actions(resource),
        {:ok, effect} <- [effect(domain, resource, action)],
        do: effect
  end

  def effect(domain, resource, action) do
    case :ash_eyg@actions.build(AshEyg.Native.descriptor(domain, resource, action)) do
      {:ok, {:effect, label, lift, lower, handle}} ->
        {:ok,
         %AshEyg.Effect{
           label: label,
           lift: lift,
           lower: lower,
           handle: handle,
           resource: resource,
           action: action.name
         }}

      {:error, nil} ->
        :error
    end
  end
end
