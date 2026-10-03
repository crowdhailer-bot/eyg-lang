defmodule PhoenixCountersWeb.PageController do
  use PhoenixCountersWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
