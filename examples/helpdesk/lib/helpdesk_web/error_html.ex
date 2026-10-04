defmodule HelpdeskWeb.ErrorHTML do
  @moduledoc false

  # Render "404.html" as "Not Found" and so on.
  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)
end
