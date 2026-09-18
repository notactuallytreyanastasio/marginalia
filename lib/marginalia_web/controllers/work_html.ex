defmodule MarginaliaWeb.WorkHTML do
  @moduledoc """
  The upload form, rendered without a live socket.

  Deliberately a plain form, and deliberately not a second copy of the
  LiveView's page: no URL fetch, no drop target, no attach — every one of
  those needs the socket that is by definition missing here. What it keeps
  is the only thing that matters when a submit has already gone wrong, which
  is the writer's text, still in the box.
  """
  use MarginaliaWeb, :html

  def new(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-2xl px-6 py-10">
        <h1 style="font-family:var(--mg-serif)" class="text-2xl font-semibold tracking-tight">
          Upload a draft
        </h1>

        <div class="mt-5 border-l-2 border-[var(--mg-accent)] pl-3 py-1.5 text-[0.85rem]">
          {@error}
        </div>

        <p class="mg-prose mt-4 text-[0.95rem] text-[var(--mg-dim)]">
          This page is running without its live connection, so it is the plain
          version: paste and press Continue. Reload to get the full one back,
          but copy your text somewhere first — a reload will empty this box.
        </p>

        <form action={~p"/works/new"} method="post" class="mt-6 space-y-5">
          <input type="hidden" name="_csrf_token" value={get_csrf_token()} />

          <.input
            id="work_title"
            name="work[title]"
            value={@work["title"]}
            label="Title"
            placeholder="Working title is fine"
          />

          <.input
            id="work_intent"
            name="work[intent]"
            value={@work["intent"]}
            type="textarea"
            rows="2"
            label="In a sentence or two, what is this supposed to do to a reader?"
            placeholder="Optional — but it's what stops the notes being generic."
          />

          <.input
            id="work_body"
            name="work[body]"
            value={@work["body"]}
            type="textarea"
            rows="12"
            label="Paste the draft"
            placeholder="Paste the whole thing. Chapter headings or markdown headings help it divide the draft correctly."
          />

          <button type="submit" class="mg-btn">Continue</button>
        </form>
      </div>
    </Layouts.app>
    """
  end
end
