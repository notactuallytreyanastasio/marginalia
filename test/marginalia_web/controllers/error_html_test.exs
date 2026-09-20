defmodule MarginaliaWeb.ErrorHTMLTest do
  @moduledoc """
  The generated version of this asserted the scaffold's behaviour: that 404
  renders the string "Not Found" and nothing else. That is exactly what was
  replaced, so the test that pinned it now pins the wrong thing.

  What is worth keeping is the shape — these go through Phoenix.Template the
  way the endpoint reaches them, not through the module directly.
  See `MarginaliaWeb.ErrorPageTest` for what the pages say.
  """
  use MarginaliaWeb.ConnCase, async: true

  import Phoenix.Template, only: [render_to_string: 4]

  test "404 renders a page through the template layer" do
    html = render_to_string(MarginaliaWeb.ErrorHTML, "404", "html", [])

    assert html =~ "<!DOCTYPE html>"
    assert html =~ "Nothing at that address"
  end

  test "500 does too" do
    html = render_to_string(MarginaliaWeb.ErrorHTML, "500", "html", [])

    assert html =~ "<!DOCTYPE html>"
    assert html =~ "Something broke"
  end

  test "a status with no page of its own still renders its name" do
    assert render_to_string(MarginaliaWeb.ErrorHTML, "403", "html", []) == "Forbidden"
  end
end
