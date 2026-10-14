defmodule HelpdeskWeb.EygHighlight do
  @moduledoc """
  Adds EYG syntax highlighting to AshAdmin pages.

  AshAdmin renders its own layout and has no place for an application's scripts,
  so this plug adds one before the page is sent.
  """
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    Plug.Conn.register_before_send(conn, fn conn ->
      body =
        :helpdesk@markup.inject(Plug.Conn.get_resp_header(conn, "content-type"), conn.resp_body)

      %{conn | resp_body: body}
    end)
  end
end
