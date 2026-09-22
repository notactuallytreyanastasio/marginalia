defmodule MarginaliaWeb.MutterComponentTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias MarginaliaWeb.CoreComponents

  test "words, then the three dots" do
    html =
      render_component(&CoreComponents.mutter/1, text: "The cheese knows.", label: "reading it")

    assert html =~ ~s(<span class="mg-mutter">The cheese knows.</span>)
    assert length(Regex.scan(~r/class="mg-dot"/, html)) == 3
    assert html =~ ~s(aria-label="reading it")
  end

  test "no words yet means the dots alone, as before" do
    html = render_component(&CoreComponents.mutter/1, text: nil)
    refute html =~ "mg-mutter"
    assert length(Regex.scan(~r/class="mg-dot"/, html)) == 3
  end
end
