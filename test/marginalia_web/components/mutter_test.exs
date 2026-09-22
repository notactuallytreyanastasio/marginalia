defmodule MarginaliaWeb.MutterComponentTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias MarginaliaWeb.CoreComponents

  test "the first line, the rest for the hook to rotate through, then the three dots" do
    lines = ["The cheese knows.", "Nobody orders rye.", "Butter, again."]
    html = render_component(&CoreComponents.mutter/1, lines: lines, label: "reading it")

    assert html =~ ~s(class="mg-mutter")
    assert html =~ "The cheese knows."
    refute html =~ ">Nobody orders rye.<"

    assert html =~ ~s(phx-hook=".Rotate") or
             html =~ ~s(phx-hook="MarginaliaWeb.CoreComponents.Rotate")

    assert html =~ ~s(phx-update="ignore")
    assert html =~ Phoenix.HTML.html_escape(Jason.encode!(lines)) |> Phoenix.HTML.safe_to_string()
    assert length(Regex.scan(~r/class="mg-dot"/, html)) == 3
    assert html =~ ~s(aria-label="reading it")
  end

  test "no lines yet means the dots alone, as before" do
    html = render_component(&CoreComponents.mutter/1, lines: [])
    refute html =~ "mg-mutter"
    assert length(Regex.scan(~r/class="mg-dot"/, html)) == 3
  end
end
