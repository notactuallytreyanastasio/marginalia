defmodule MarginaliaWeb.WorkController do
  @moduledoc """
  Uploading a draft when there is no live socket.

  `/works/new` is a LiveView, and the form it renders carries `method="post"`
  like any other form. When LiveView's JavaScript is not driving that form —
  the tab was open across a deploy and the reconnect failed, a proxy ate the
  websocket, scripts are blocked — the browser does the only thing the markup
  tells it to, and posts to the page's own address.

  Until this existed, nothing answered that. Phoenix raised `NoRouteError`
  and a writer who had just pasted several thousand words got a bare 404 with
  the text gone. It is in the log: one person, four attempts, ten minutes,
  every one of them a `POST /works/new` → `Sent 404`. Their websocket had died
  at 19:23:18Z, which is the second a deploy restarted the container.

  A file cannot come through this path — `live_file_input` uploads over the
  socket, so with no socket there is no file and the form does not even carry
  one. That case is named rather than guessed at.
  """
  use MarginaliaWeb, :controller

  alias Marginalia.Works
  alias Marginalia.Works.Upload

  def create(conn, params) do
    work = Map.get(params, "work", %{})

    case Upload.prepare(work["title"], work["body"], work["intent"]) do
      {:ok, attrs} ->
        save(conn, work, attrs)

      {:error, :empty} ->
        again(
          conn,
          work,
          "There's no text there yet — paste the draft into the box below. " <>
            "Attaching a file needs JavaScript, which is not running on this page."
        )

      {:error, {:too_long, words}} ->
        again(conn, work, Upload.too_long_message(words))
    end
  end

  defp save(conn, work, attrs) do
    case Works.create_work(conn.assigns.current_scope.user.id, attrs) do
      {:ok, saved} ->
        redirect(conn, to: ~p"/works/#{saved.slug}")

      {:error, :no_sections} ->
        again(conn, work, "Couldn't find any text to split into sections.")

      {:error, %Ecto.Changeset{} = changeset} ->
        again(conn, work, first_error(changeset))
    end
  end

  # Re-render rather than redirect. The entire point of this path is that the
  # writer's text survives, and a redirect would drop it on the floor exactly
  # the way the 404 did.
  defp again(conn, work, error) do
    conn
    |> put_status(:unprocessable_entity)
    |> render(:new, work: work, error: error)
  end

  defp first_error(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), "") |> to_string()
      end)
    end)
    |> Enum.flat_map(fn {field, msgs} -> Enum.map(msgs, &"#{field} #{&1}") end)
    |> List.first()
    |> case do
      nil -> "That draft could not be saved."
      message -> String.capitalize(message) <> "."
    end
  end
end
