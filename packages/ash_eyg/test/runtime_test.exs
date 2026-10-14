defmodule AshEyg.RuntimeTest do
  use ExUnit.Case
  @checks :ash_eyg@runtime_checks
  test "Ash effect discovery and types", do: @checks.discovery_and_types()
  test "Ash CRUD actions and generic replies", do: @checks.crud_and_generic()
  test "Ash actor, tenant and context", do: @checks.host_scope()
  test "restricted effects and errors before actions", do: @checks.restricted_effects()
  test "host effects", do: @checks.host_effects()

  test "package validation, rollback and independent sessions",
    do: @checks.packages_and_sessions()

  test "Ash generic action bridge", do: @checks.generic_action_bridge()
  test "Gleam type conversion and command arguments", do: @checks.conversion_and_tools()
end
