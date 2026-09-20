defmodule MarginaliaWeb.DraftLive.Changes do
  @moduledoc """
  What a published draft used to say, beside what it says now.

  The same two columns the writer sees on their own work, read-only and
  without the history's controls. It is here because "every change is kept"
  is the one claim on the front page a stranger could not check: the diff
  existed only behind a login, which makes it a promise rather than a
  demonstration.
  """
  use MarginaliaWeb, :live_view

  alias Marginalia.{Diff, Works}

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case Works.public_draft(slug) do
      nil ->
        {:ok, socket |> put_flash(:error, "No such draft.") |> push_navigate(to: ~p"/drafts")}

      work ->
        rows = Diff.rows(Works.baseline(work), work.body)

        {:ok,
         assign(socket,
           page_title: "#{work.title} — what changed",
           page_description: "Every change made to this draft, as a before and after.",
           page_robots: "index, follow",
           work: work,
           rows: rows,
           stat: Diff.stat(rows),
           revisions: Enum.reverse(Works.revisions(work.id))
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mg-diff">
        <div class="mg-meta">
          <.link navigate={~p"/drafts/#{@work.slug}"}>← {@work.title}</.link>
        </div>

        <div class="mg-diff-head">
          <span class="mg-label">Changes since it arrived</span>
          <span class="mg-meta ml-auto">
            {@stat.changed} edited · {@stat.added} added · {@stat.removed} removed
          </span>
        </div>

        <p :if={not Diff.any?(@rows)} class="mg-empty">
          Nothing has been changed yet.
        </p>

        <div :if={Diff.any?(@rows)} class="mg-diff-cols">
          <div class="mg-diff-colhead"><span>As it arrived</span><span>Now</span></div>

          <div :for={row <- @rows} class={"mg-diff-row " <> kind(row)}>
            <%= case row do %>
              <% {:same, l, _} -> %>
                <div class="side old">{l}</div>
                <div class="side new">{l}</div>
              <% {:change, l, r} -> %>
                <div class="side old">
                  <span :for={{op, t} <- Diff.words(l, r)} class={klass(op, :old)}>{t}</span>
                </div>
                <div class="side new">
                  <span :for={{op, t} <- Diff.words(l, r)} class={klass(op, :new)}>{t}</span>
                </div>
              <% {:del, l} -> %>
                <div class="side old gone">{l}</div>
                <div class="side new empty"></div>
              <% {:ins, r} -> %>
                <div class="side old empty"></div>
                <div class="side new fresh">{r}</div>
            <% end %>
          </div>
        </div>

        <div :if={@revisions != []} class="mg-diff-log">
          <div class="mg-label">Every change, newest first</div>
          <ol class="mg-rows">
            <li :for={rev <- @revisions}>
              <span class="n">{rev.seq}</span>
              <span class="mg-meta">
                {rev.origin}{if rev.note, do: " — #{rev.note}"} · section {rev.section_ordinal}
              </span>
              <div class="mg-diff-patch">
                <span :for={{op, t} <- Diff.words(rev.before, rev.after)} class={klass(op, :new)}>{t}</span>
              </div>
            </li>
          </ol>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp kind({:same, _, _}), do: "same"
  defp kind({:change, _, _}), do: "change"
  defp kind({:del, _}), do: "del"
  defp kind({:ins, _}), do: "ins"

  defp klass(:same, _), do: "w"
  defp klass(:del, :old), do: "w del"
  defp klass(:del, :new), do: "w hide"
  defp klass(:ins, :old), do: "w hide"
  defp klass(:ins, :new), do: "w ins"
end
