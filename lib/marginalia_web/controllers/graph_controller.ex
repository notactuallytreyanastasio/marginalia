defmodule MarginaliaWeb.GraphController do
  @moduledoc """
  Download the knowledge graph. Addressed by the draft's slug, so anyone
  holding the link can export what they can already read, and a guessed id
  gets nothing.
  """
  use MarginaliaWeb, :controller

  alias Marginalia.{Works, Graph}

  def json(conn, %{"id" => id}) do
    with_work(conn, id, fn work ->
      conn
      |> put_resp_content_type("application/json")
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{slug(work)}-graph.json"))
      |> send_resp(200, Graph.to_json(work))
    end)
  end

  def dot(conn, %{"id" => id}) do
    with_work(conn, id, fn work ->
      conn
      |> put_resp_content_type("text/vnd.graphviz")
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{slug(work)}-graph.dot"))
      |> send_resp(200, Graph.to_dot(work))
    end)
  end

  @doc """
  The build trace: every tool call and the server's answer, refusals included.

  Downloadable because the point of the trace is that someone other than this
  page can check it.
  """
  def trace(conn, %{"id" => id}) do
    # the trace is how the thing works rather than what it found, so unlike
    # the graph it does not travel with the link
    with_owner(conn, id, fn work ->
      body =
        %{
          work: %{id: work.id, title: work.title},
          stats: Works.event_stats(work.id),
          events:
            Works.list_events(work.id)
            |> Enum.map(fn e ->
              %{
                seq: e.seq,
                narrative: e.narrative,
                tool: e.tool,
                args: decode(e.args),
                result: decode(e.result),
                ok: e.ok,
                at: e.inserted_at
              }
            end)
        }
        |> Jason.encode!(pretty: true)

      conn
      |> put_resp_content_type("application/json")
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{slug(work)}-trace.json"))
      |> send_resp(200, body)
    end)
  end

  defp with_owner(conn, slug, fun) do
    user = conn.assigns.current_scope.user

    case Works.get_by_slug(slug) do
      %{user_id: uid} = work when uid == :erlang.map_get(:id, user) -> fun.(work)
      _ -> conn |> put_status(:not_found) |> text("not found")
    end
  end

  defp decode(nil), do: nil

  defp decode(json) do
    case Jason.decode(json) do
      {:ok, v} -> v
      _ -> json
    end
  end

  # Addressed by slug, like the page itself: whoever can read the draft can
  # export what they are looking at. The slug is the permission.
  defp with_work(conn, slug, fun) do
    case Works.get_by_slug(slug) do
      nil -> conn |> put_status(:not_found) |> text("not found")
      work -> fun.(work)
    end
  end

  defp slug(work) do
    work.title
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> String.slice(0, 50)
    |> case do
      "" -> "draft"
      s -> s
    end
  end
end
