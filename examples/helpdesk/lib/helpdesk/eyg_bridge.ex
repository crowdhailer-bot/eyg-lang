defmodule Helpdesk.EygBridge do
  @moduledoc false
  def effects, do: AshEyg.effects(otp_app: :helpdesk)
  def action(effect), do: to_string(effect.action)
  def body_text(body), do: IO.iodata_to_binary(body)
  def identity(value), do: value
end
