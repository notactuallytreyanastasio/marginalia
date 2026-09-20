defmodule MarginaliaWeb.DraftLive.Show do
  @moduledoc """
  A draft, read by anybody, with its notes beside it.

  Read-only and deliberately not `WorkLive.Show`. That page carries the
  controls that spend money and the ones that write to the draft — read,
  summarise, rewrite, edit — and the reliable way to keep those away from
  strangers is for the public page not to have them rather than for every
  one of them to check.
  """
  use MarginaliaWeb, :live_view

  alias Marginalia.{Reading, Works}

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case Works.public_draft(slug) do
      nil ->
        {:ok, socket |> put_flash(:error, "No such draft.") |> push_navigate(to: ~p"/drafts")}

      work ->
        {:ok,
         assign(socket,
           page_title: work.title,
           page_description: String.slice(work.first_impression || work.title, 0, 300),
           page_robots: "index, follow",
           work: work,
           page: Reading.page(work),
           changed: Works.revision_count(work.id)
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-5xl px-6 py-8">
        <div class="mg-meta">
          <.link navigate={~p"/drafts"}>← Drafts</.link>
        </div>

        <h1 style="font-family:var(--mg-serif)" class="text-2xl font-semibold tracking-tight mt-2">
          {@work.title}
        </h1>
        <p class="mg-meta">
          {@work.word_count} words
          <span :if={@changed > 0}>
            ·
            <.link navigate={~p"/drafts/#{@work.slug}/changes"}>
              {@changed} change{if @changed == 1, do: "", else: "s"} since it arrived
            </.link>
          </span>
        </p>

        <div class="mg-read mt-6">
          <div class="mg-read-body">
            <%= for sec <- @page do %>
              <div class="mg-read-head">
                <div class="mg-label">Section {sec.section.ordinal}</div>
                <h2 style="font-family:var(--mg-serif)" class="text-[1.45rem] font-semibold mt-1">
                  {sec.section.title}
                </h2>
                <div :if={sec.section.summary} class="mg-sum-text">{sec.section.summary}</div>
              </div>

              <div :for={b <- sec.blocks} class="mg-block" id={"block-#{b.ref}"}>
                {Reading.render_block(b.text, b.mark, b.ref, nil)}
              </div>
            <% end %>
          </div>

          <div class="mg-read-rail">
            <%= for sec <- @page, b <- sec.blocks, n <- b.notes do %>
              <div class={"mg-note-slot " <> n.kind} data-anchor={b.ref}>
                <div class={"mg-note " <> n.kind}>
                  <span class="who">{String.replace(n.kind, "_", " ")}</span>
                  <span class="said">{n.title}</span>
                  <span :if={n.body} class="why">{n.body}</span>
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
