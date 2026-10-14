defmodule HelpdeskWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :helpdesk

  @session_options [
    store: :cookie,
    key: "_helpdesk_key",
    signing_salt: "oZuqiClsm23daSJ",
    same_site: "Lax"
  ]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])

  plug(Plug.Static, at: "/", from: :helpdesk, gzip: false, only: ~w(assets))

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Jason
  )

  plug(Plug.Session, @session_options)
  plug(HelpdeskWeb.Router)
end
