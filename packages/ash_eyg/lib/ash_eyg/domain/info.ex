defmodule AshEyg.Domain.Info do
  @moduledoc "Introspection for `AshEyg.Domain`."
  use Spark.InfoGenerator, extension: AshEyg.Domain, sections: [:eyg]

  @doc "The prefix of every effect label from this domain."
  def name(domain) do
    case eyg_name(domain) do
      {:ok, name} -> name
      :error -> domain |> Module.split() |> List.last()
    end
  end
end
