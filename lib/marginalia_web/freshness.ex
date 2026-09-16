defmodule MarginaliaWeb.Freshness do
  @moduledoc """
  Reload a tab whose assets predate the running server.

  A deploy changes the markup the server sends and the JavaScript that drives
  it at the same time, but a tab that was already open keeps the old bundle.
  That combination fails in a way that looks like the app is broken rather
  than stale: markup referring to a `phx-hook` the old bundle has never heard
  of throws on mount, and from there nothing on the page responds. It also
  fails silently in the other direction — new CSS classes with no rules
  behind them, so a considered piece of layout renders as a pile of text.

  LiveView already tells us this has happened: `phx-track-static` sends the
  asset URLs the page was built with, and `static_changed?/1` compares them
  against what this server would serve now. All that is missing is acting on
  it, which has to be a real browser navigation rather than a live one — the
  point is to fetch the new bundle.

  The `_fresh` parameter is a fuse. If an intermediary ever cached the HTML,
  the reloaded page would come back just as stale and we would bounce
  forever; a page that has already been sent round once is left alone.
  """

  import Phoenix.LiveView

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket) and static_changed?(socket) do
      {:cont, attach_hook(socket, :stale_assets, :handle_params, &reload/3)}
    else
      {:cont, socket}
    end
  end

  defp reload(params, uri, socket) do
    if Map.has_key?(params, "_fresh") do
      {:cont, socket}
    else
      {:halt, redirect(socket, external: bust(uri))}
    end
  end

  defp bust(uri) do
    parsed = URI.parse(uri)
    query = URI.decode_query(parsed.query || "") |> Map.put("_fresh", "1")
    URI.to_string(%{parsed | query: URI.encode_query(query)})
  end
end
