defmodule Helpdesk.RuntimeTest do
  use ExUnit.Case
  @checks :helpdesk@runtime_checks
  test "triage effects restrict scripts", do: @checks.triage_scope()
  test "triage assigns tickets", do: @checks.triage_assigns()
  test "generic action retains validated packages", do: @checks.generic_packages()
  test "generic action validates before effects", do: @checks.generic_validation()
end
