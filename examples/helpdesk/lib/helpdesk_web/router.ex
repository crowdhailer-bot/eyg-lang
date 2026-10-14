defmodule HelpdeskWeb.Router do
  use Phoenix.Router
  import AshAdmin.Router

  admin_browser_pipeline(:browser)

  scope "/" do
    pipe_through [:browser, HelpdeskWeb.EygHighlight]

    ash_admin("/admin")
  end
end
