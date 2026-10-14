defmodule AshEyg.Type do
  @moduledoc "Ash metadata bridge to Gleam's EYG type and value conversions."
  def unit, do: :ash_eyg@type_.unit()

  def eyg_type(type, constraints, nullable \\ false) do
    case AshEyg.Native.shape(type, constraints) do
      {:ok, shape} -> {:ok, :ash_eyg@type_.type_(shape, nullable)}
      {:error, nil} -> :error
    end
  end

  def to_eyg(type, constraints, value), do: to_eyg(type, constraints, false, value)

  def to_eyg(type, constraints, nullable, value) do
    {:ok, shape} = AshEyg.Native.shape(type, constraints)
    :ash_eyg@type_.encode(shape, nullable, value)
  end

  def from_eyg(type, constraints, value), do: from_eyg(type, constraints, false, value)

  def from_eyg(type, constraints, nullable, value) do
    {:ok, shape} = AshEyg.Native.shape(type, constraints)
    :ash_eyg@type_.decode(shape, nullable, value)
  end

  def record(fields), do: :eyg@analysis@type_@isomorphic.record(fields)
  def union(variants), do: :eyg@analysis@type_@isomorphic.union(variants)
  def option(type), do: :ash_eyg@type_.option(type)
  def result(value, reason), do: :eyg@analysis@type_@isomorphic.result(value, reason)
end
