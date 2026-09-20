defmodule MarginaliaWeb.ErrorPageTest do
  @moduledoc """
  The page nobody writes.

  A stranger following a stale link is fairly likely to see this one first,
  and the generated default is the status name as plain text on a white page
  with no way back to anything.
  """
  use MarginaliaWeb.ConnCase, async: true

  alias MarginaliaWeb.ErrorHTML

  # ~H returns a Rendered struct rather than {:safe, iodata}; this is what
  # Phoenix itself does with it on the way to the wire.
  defp render(template),
    do: ErrorHTML.render(template, []) |> Phoenix.LiveViewTest.rendered_to_string()

  test "404 is a page, not the words Not Found" do
    html = render("404.html")

    assert html =~ "<!DOCTYPE html>"
    assert html =~ "Nothing at that address"
    refute html == "Not Found"
  end

  test "it offers somewhere to go" do
    html = render("404.html")

    for path <- ~w(/ /cases /drafts /reading) do
      assert html =~ ~s(href="#{path}"), "a dead end with no way out of it"
    end
  end

  test "500 does not blame the visitor" do
    html = render("500.html")

    assert html =~ "Something broke"
    assert html =~ "That is this end, not yours"
  end

  test "neither is indexed" do
    for t <- ~w(404.html 500.html) do
      assert render(t) =~ ~s(name="robots" content="noindex")
    end
  end

  test "they depend on nothing that could also be broken" do
    html = render("500.html")

    # its own markup and its own styles: an error page that needs the app
    # layout, the socket or the asset pipeline is one that fails when they do.
    # (`phx-r` is a HEEx debug annotation in dev and test builds, not
    # something the page depends on, so it is not what is checked here.)
    refute html =~ "/assets/"
    refute html =~ "phx-hook"
    refute html =~ "data-phx-session"
    assert html =~ "<style>"
  end

  test "anything else keeps the plain status name" do
    assert ErrorHTML.render("418.html", []) == "I'm a teapot"
  end
end
