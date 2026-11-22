defmodule MarginaliaWeb.DraftLive.Show do
  @moduledoc """
  A draft, read by anybody, with its notes beside it and the chat.

  Read-only and deliberately not `WorkLive.Show`. That page carries the
  controls that spend money and the ones that write to the draft — read,
  summarise, rewrite, edit — and the reliable way to keep those away from
  strangers is for the public page not to have them rather than for every
  one of them to check.

  The chat is the exception, because a reading without it is half of one.
  It is the writer's own chat — `Chat.Editor`, with its tools and its modes —
  run with `public: true`, which takes away the two tools that are the
  writer's rather than the book's. The conversation lives in the socket, as
  on `/cases`: a reader's questions are not stored against the draft, and no
  account is minted to hold them.

  A draft in a published folder is a chapter of that reading, so it links
  back to it and on to its neighbours.
  """
  use MarginaliaWeb, :live_view

  alias Marginalia.{Accounts, Folders, Reading, Stacks, Works}
  alias Marginalia.Chat.Editor

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case Works.public_draft(slug) do
      nil ->
        {:ok, socket |> put_flash(:error, "No such draft.") |> push_navigate(to: ~p"/drafts")}

      work ->
        {reading, prev, next} = neighbours(work)

        {:ok,
         assign(socket,
           page_title: work.title,
           page_description: String.slice(work.first_impression || work.title, 0, 300),
           page_robots: "index, follow",
           work: work,
           page: Reading.page(work),
           changed: Works.revision_count(work.id),
           reading: reading,
           prev: prev,
           next: next,
           chat_open: false,
           chat_thinking: false,
           chat_mutter: [],
           chat_history: [],
           focus: nil,
           mode: Editor.default_mode(),
           modes: Editor.modes()
         )}
    end
  end

  # The published folder this draft sits in, and the drafts either side of it
  # in the order the reading lists them. A folder that is not published is
  # not a reading, and its name is not anybody else's business.
  defp neighbours(%{folder_id: nil}), do: {nil, nil, nil}

  defp neighbours(work) do
    with %{published_at: %DateTime{}} = folder <- Folders.get_folder(work.user_id, work.folder_id) do
      docs = Stacks.documents(work.user_id, folder.id)
      i = Enum.find_index(docs, &(&1.id == work.id))
      prev = if i && i > 0, do: Enum.at(docs, i - 1)
      next = if i, do: Enum.at(docs, i + 1)
      {folder, prev, next}
    else
      _ -> {nil, nil, nil}
    end
  end

  # --- the chat -------------------------------------------------------------

  @impl true
  def handle_event("toggle_chat", _params, socket),
    do: {:noreply, assign(socket, chat_open: !socket.assigns.chat_open)}

  def handle_event("close_chat", _params, socket),
    do: {:noreply, assign(socket, chat_open: false)}

  def handle_event("set_mode", %{"mode" => mode}, socket) do
    mode = if mode in Editor.mode_names(), do: mode, else: Editor.default_mode()
    {:noreply, assign(socket, mode: mode)}
  end

  # Clicking a note opens the chat already holding the note and the sections
  # it touches, the same as it does for the writer.
  def handle_event("discuss", %{"key" => key}, socket) do
    case Reading.focus(socket.assigns.work, key) do
      nil -> {:noreply, socket}
      focus -> {:noreply, assign(socket, focus: focus, chat_open: true)}
    end
  end

  def handle_event("clear_focus", _params, socket), do: {:noreply, assign(socket, focus: nil)}

  def handle_event("chat_send", %{"message" => text}, socket) do
    text = String.trim(text)
    a = socket.assigns

    if text == "" or a.chat_thinking do
      {:noreply, socket}
    else
      history = a.chat_history ++ [%{"role" => "user", "content" => text}]
      window = Marginalia.Chat.context_window(history)
      {work, focus, mode} = {a.work, a.focus, a.mode}
      # the owner's key and the owner's choice of model: this is their page
      provider = Accounts.provider_for(Accounts.owner())

      {:noreply,
       socket
       |> assign(
         chat_history: history,
         chat_thinking: true,
         chat_mutter: Marginalia.Mutterings.some(8),
         focus: nil
       )
       |> start_async(:chat, fn ->
         Editor.ask(work, window, public: true, focus: focus, mode: mode, provider: provider)
       end)}
    end
  end

  @impl true
  def handle_async(:chat, {:ok, {:ok, text}}, socket) do
    {:noreply,
     assign(socket,
       chat_thinking: false,
       chat_history: socket.assigns.chat_history ++ [%{"role" => "assistant", "content" => text}]
     )}
  end

  def handle_async(:chat, {:ok, {:error, reason}}, socket),
    do: {:noreply, socket |> assign(chat_thinking: false) |> chat_failed(reason)}

  def handle_async(:chat, {:exit, reason}, socket),
    do: {:noreply, socket |> assign(chat_thinking: false) |> chat_failed(reason)}

  defp chat_failed(socket, reason) when is_binary(reason),
    do: put_flash(socket, :error, "That did not go through: #{reason}")

  defp chat_failed(socket, reason),
    do: put_flash(socket, :error, "That did not go through: #{inspect(reason)}")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <MarginaliaWeb.LinkChat.bubble
        open={@chat_open}
        history={@chat_history}
        thinking={@chat_thinking}
        mutter={@chat_mutter}
        count={length(@chat_history)}
        pointing={@focus}
        modes={@modes}
        mode={@mode}
        title="About this draft"
        label="Talk about this draft"
        hint={
          "This one has read the whole draft and holds every note in the margin. Ask what a " <>
            "passage is doing, where a thread goes, or what pays off later — or click a note " <>
            "to start from it. It will not write any of the book."
        }
        placeholder="Ask about this draft"
        openers={[
          "What is this section doing?",
          "Which threads are still open by the end?",
          "Where is the tension in this?"
        ]}
      />

      <div class="mx-auto max-w-5xl px-6 py-8">
        <div class="mg-meta">
          <%= if @reading do %>
            <.link navigate={~p"/reading/#{@reading.slug}"}>← {@reading.name}</.link>
          <% else %>
            <.link navigate={~p"/drafts"}>← Drafts</.link>
          <% end %>
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
                <button
                  class={"mg-note " <> n.kind}
                  phx-click="discuss"
                  phx-value-key={n.key}
                  title="Talk about this"
                >
                  <span class="who">{String.replace(n.kind, "_", " ")}</span>
                  <span class="said">{n.title}</span>
                  <span :if={n.body} class="why">{n.body}</span>
                </button>
              </div>
            <% end %>
          </div>
        </div>

        <nav :if={@prev || @next} class="st-nav mt-10">
          <.link :if={@prev} navigate={~p"/drafts/#{@prev.slug}"}>← {@prev.title}</.link>
          <.link :if={@next} navigate={~p"/drafts/#{@next.slug}"}>{@next.title} →</.link>
        </nav>
      </div>
    </Layouts.app>
    """
  end
end
