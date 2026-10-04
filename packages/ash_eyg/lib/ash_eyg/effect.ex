defmodule AshEyg.Effect do
  @moduledoc """
  An effect an EYG program can perform.

  `lift` is the type of the value the program gives the host, `lower` the type of the reply.
  `handle` is called with the lifted value and the actor, tenant and context of the run,
  it returns the reply.
  """

  @enforce_keys [:label, :lift, :lower, :handle]
  defstruct [:label, :lift, :lower, :handle, :resource, :action]

  @type t :: %__MODULE__{
          label: String.t(),
          lift: term(),
          lower: term(),
          handle: (term(), keyword() -> term()),
          resource: module() | nil,
          action: atom() | nil
        }

  @doc """
  An effect implemented by the host, for use alongside the effects of Ash actions.

      AshEyg.Effect.new("Log", :string, {:record, :empty}, fn {:string, message}, _opts ->
        IO.puts(message)
        {:record, %{}}
      end)
  """
  def new(label, lift, lower, handle) when is_function(handle, 2) do
    %__MODULE__{label: label, lift: lift, lower: lower, handle: handle}
  end
end
