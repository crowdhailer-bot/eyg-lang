defmodule HelpdeskWeb.EygHighlight do
  @moduledoc """
  Adds EYG syntax highlighting to AshAdmin pages.

  AshAdmin renders its own layout and has no place for an application's scripts,
  so this plug adds one before the page is sent.
  """
  @behaviour Plug

  @script ~s|<script type="module" src="/assets/admin_eyg.js"></script>|

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    Plug.Conn.register_before_send(conn, fn conn ->
      case Plug.Conn.get_resp_header(conn, "content-type") do
        ["text/html" <> _] ->
          body =
            conn.resp_body
            |> IO.iodata_to_binary()
            |> String.replace("</html>", @script <> "</html>")

          %{conn | resp_body: body}

        _ ->
          conn
      end
    end)
  end
end
