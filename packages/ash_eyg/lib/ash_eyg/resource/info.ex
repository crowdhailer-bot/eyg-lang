defmodule AshEyg.Resource.Info do
  @moduledoc "Introspection for `AshEyg.Resource`."
  use Spark.InfoGenerator, extension: AshEyg.Resource, sections: [:eyg]

  @doc "The part of an effect label naming this resource."
  def name(resource) do
    case eyg_name(resource) do
      {:ok, name} -> name
      :error -> resource |> Module.split() |> List.last()
    end
  end
end
