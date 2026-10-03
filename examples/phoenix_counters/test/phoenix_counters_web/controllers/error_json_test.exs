defmodule PhoenixCountersWeb.ErrorJSONTest do
  use PhoenixCountersWeb.ConnCase, async: true

  test "renders 404" do
    assert PhoenixCountersWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert PhoenixCountersWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
