defmodule Marginalia.Recovery do
  @moduledoc """
  Work that was in flight when the machine went away.

  A read and a link both run in a detached task, and the row they belong to
  carries the status while they do. If the release restarts mid-run — a
  deploy, a crash, a box rebooting — the task dies and the row is left
  saying "reading" or "linking" for ever. Nothing is working on it, nothing
  will, and the page shows a spinner that never resolves. That happened
  once: a deploy went out while twelve links were running and every one of
  them stopped silently, still claiming to be in progress.

  There is no process to resume, so the honest thing is to mark them
  failed, say why, and let the writer press the button again. Guessing that
  a half-finished read can be continued would be worse: the passes are not
  idempotent and a partial graph looks exactly like a complete one.
  """
  require Logger

  import Ecto.Query

  alias Marginalia.{Links, Repo, Works}

  @note "interrupted by a restart"

  @doc "Called on boot, before anything can be served."
  def sweep do
    links = reset(Links.Link, "linking", %{status: "failed", error: @note})
    works = reset(Works.Work, "reading", %{status: "failed", status_detail: @note})

    if links + works > 0 do
      Logger.warning(
        "marginalia: #{links} links and #{works} reads were interrupted by a restart, marked failed"
      )
    end

    {links, works}
  end

  defp reset(schema, from, changes) do
    changes = Map.put(changes, :updated_at, DateTime.utc_now() |> DateTime.truncate(:second))
    {n, _} = schema |> where([r], r.status == ^from) |> Repo.update_all(set: Map.to_list(changes))
    n
  end
end
