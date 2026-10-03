defmodule PhoenixCounters.Counters.Eyg do
  @moduledoc """
  Check and run EYG scripts that use only the counters effects.
  """

  alias PhoenixCounters.Counters.Effects

  @doc "Parse a script without checking it."
  def parse(source) do
    case :eyg_beam.parse(source) do
      {:ok, nil} -> :ok
      {:error, message} -> {:error, message}
    end
  end

  @doc "Type check a script, returns its type or the errors rendered against the source."
  def check(source), do: :eyg_beam.check(source, Effects.effects(), packages())

  @doc "Type check a script then run it, returns the value rendered as EYG."
  def run(source) do
    case :eyg_beam.run(source, Effects.effects(), packages(), &Effects.handle/2) do
      {:ok, value} -> {:ok, :eyg_beam.inspect(value)}
      {:error, message} -> {:error, message}
    end
  end

  @doc "Make `@standard` available to scripts."
  def load_packages do
    path = Application.fetch_env!(:phoenix_counters, :standard_library)
    {:ok, standard} = :eyg_beam.load_package(File.read!(path))
    :persistent_term.put({__MODULE__, :packages}, %{"standard" => standard})
  end

  defp packages, do: :persistent_term.get({__MODULE__, :packages})
end
