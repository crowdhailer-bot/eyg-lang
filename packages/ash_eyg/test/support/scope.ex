defmodule AshEyg.Test.Scope do
  use Ash.Resource.Actions.Implementation
  @impl true
  def run(_input, _opts, context),
    do: {:ok, :ash_eyg@test_scope.describe(context.actor, context.tenant, context.source_context)}
end
