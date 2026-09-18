defmodule MarginaliaWeb.WorkLive.New do
  @moduledoc """
  Upload a draft.

  Paste, drop a text file, or give it the address of something published —
  a lot of what people want to read closely is already on the web, and
  nobody is going to retype it.

  The intent field is optional and does more work
  than it looks like it does: every note is written against what the writer
  says the draft is supposed to do, which is what keeps the read from
  defaulting to generic craft advice.
  """
  use MarginaliaWeb, :live_view

  alias Marginalia.{Import, Works}
  alias Marginalia.Works.Upload

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Upload a draft", error: nil, preview: nil, fetching: false, url: "")
     |> assign(form: to_form(Works.change_work()))
     |> allow_upload(:manuscript,
       accept: ~w(.txt .md .markdown .text),
       max_entries: 1,
       max_file_size: 8_000_000
     )}
  end

  @impl true
  def handle_event("validate", %{"work" => params}, socket) do
    {:noreply, assign(socket, form: to_form(Works.change_work(%Works.Work{}, params)))}
  end

  # Pulling a published piece in. The fetch happens off the socket, because
  # a slow site should not freeze the page it was typed into.
  def handle_event("fetch", %{"url" => url}, socket) do
    url = String.trim(url)

    cond do
      url == "" ->
        {:noreply, socket}

      socket.assigns.fetching ->
        {:noreply, socket}

      true ->
        {:noreply,
         socket
         |> assign(fetching: true, error: nil, url: url)
         |> start_async(:fetch, fn -> Import.fetch(url) end)}
    end
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :manuscript, ref)}
  end

  def handle_event("save", %{"work" => params}, socket) do
    uploaded =
      consume_uploaded_entries(socket, :manuscript, fn %{path: path}, entry ->
        {:ok, {entry.client_name, File.read!(path)}}
      end)

    {title, body} =
      case uploaded do
        [{name, contents} | _] -> {blank(params["title"]) || Path.rootname(name), contents}
        [] -> {blank(params["title"]), params["body"] || ""}
      end

    # Same rule as the plain POST in WorkController, because a writer should
    # not get a different answer depending on whether their socket was up
    case Upload.prepare(title, body, blank(params["intent"])) do
      {:ok, attrs} ->
        case Works.create_work(socket.assigns.current_scope.user.id, attrs) do
          {:ok, work} ->
            {:noreply, push_navigate(socket, to: ~p"/works/#{work.slug}")}

          {:error, %Ecto.Changeset{} = cs} ->
            {:noreply, assign(socket, form: to_form(cs), error: nil)}

          {:error, :no_sections} ->
            {:noreply, assign(socket, error: "Couldn't find any text to split into sections.")}
        end

      {:error, :empty} ->
        {:noreply,
         assign(socket, error: "There's no text there yet — paste a draft or attach a file.")}

      {:error, {:too_long, words}} ->
        {:noreply, assign(socket, error: Upload.too_long_message(words))}
    end
  end

  defdelegate blank(value), to: Upload

  @impl true
  def handle_async(:fetch, {:ok, {:ok, %{title: title, markdown: md, url: url}}}, socket) do
    params = %{"title" => title, "body" => md, "source_url" => url}

    {:noreply,
     socket
     |> assign(fetching: false, form: to_form(Works.change_work(%Works.Work{}, params)))
     |> put_flash(
       :info,
       "Read #{words(md)} words from #{host(url)}. Check it over before uploading."
     )}
  end

  def handle_async(:fetch, {:ok, {:error, reason}}, socket),
    do: {:noreply, assign(socket, fetching: false, error: why(reason))}

  def handle_async(:fetch, {:exit, _reason}, socket),
    do: {:noreply, assign(socket, fetching: false, error: why(:unreachable))}

  # Said plainly, because "error: :private_address" tells a writer nothing
  defp why(:bad_scheme), do: "That needs to be an http or https address."
  defp why(:bad_url), do: "That does not look like a web address."
  defp why(:no_host), do: "That address has no site in it."

  defp why(:private_address),
    do: "That address points at a private network, so it will not be fetched."

  defp why(:too_little_text),
    do:
      "There was not enough prose on that page to read. A paywall, or a page that builds itself with JavaScript."

  defp why(:too_big), do: "That page is too large."
  defp why(:unparseable), do: "That page could not be read as HTML."
  defp why({:http, 404}), do: "That page was not found."
  defp why({:http, status}), do: "That site answered with a #{status}."
  defp why(:unreachable), do: "That site could not be reached."
  defp why(other), do: "That did not work: #{inspect(other)}"

  defp words(text), do: text |> String.split() |> length()
  defp host(url), do: URI.parse(url).host || url

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-2xl px-6 py-10">
        <h1 style="font-family:var(--mg-serif)" class="text-2xl font-semibold tracking-tight">
          Upload a draft
        </h1>
        <p class="mg-prose mt-2 text-[0.95rem] text-[var(--mg-dim)]">
          Paste it or attach a <code>.txt</code>/<code>.md</code> file. Nothing is read until you
          confirm how it's divided on the next screen.
        </p>

        <%= if @error do %>
          <div class="mt-5 border-l-2 border-[var(--mg-accent)] pl-3 py-1.5 text-[0.85rem]">
            {@error}
          </div>
        <% end %>

        <%!-- Its own form, and above the main one: a form nested inside a
              form is invalid HTML and the browser silently drops the inner
              one, so Enter would have submitted the upload instead. --%>
        <form phx-submit="fetch" class="mt-6">
          <label class="mg-label block mb-1.5" for="import-url">Read it off the web</label>
          <div class="flex gap-2 items-start">
            <input
              type="url"
              id="import-url"
              name="url"
              value={@url}
              placeholder="https://…"
              disabled={@fetching}
              class="flex-1 min-w-0 px-2.5 py-1.5 border border-[var(--mg-rule)] rounded-sm bg-[var(--mg-paper)] text-[0.9rem]"
            />
            <button type="submit" class="mg-btn sm shrink-0" disabled={@fetching}>
              {if @fetching, do: "Reading…", else: "Fetch"}
            </button>
          </div>
          <p class="mg-hint mt-1.5">
            The article is pulled out and turned into markdown — headings, lists and links
            kept, navigation and footers dropped. It fills in the fields below for you to
            check before uploading.
          </p>
        </form>

        <%!-- The action is load-bearing even though LiveView never uses it.
              `form/1` only emits the hidden CSRF token when there is one, and
              without a token the plain-POST fallback in WorkController is
              rejected before it can save anything. --%>
        <.form
          for={@form}
          action={~p"/works/new"}
          method="post"
          phx-change="validate"
          phx-submit="save"
          class="mt-6 space-y-5"
        >
          <.input field={@form[:title]} label="Title" placeholder="Working title is fine" />

          <div>
            <.input
              field={@form[:intent]}
              type="textarea"
              rows="2"
              label="In a sentence or two, what is this supposed to do to a reader?"
              placeholder="Optional — but it's what stops the notes being generic."
            />
          </div>

          <div>
            <label class="mg-label block mb-1.5">Attach a file</label>
            <div
              phx-drop-target={@uploads.manuscript.ref}
              class="border border-dashed border-[var(--mg-rule)] rounded-sm p-5 text-[0.85rem] bg-[var(--mg-card)]"
            >
              <.live_file_input upload={@uploads.manuscript} />
              <%= for entry <- @uploads.manuscript.entries do %>
                <div class="mt-2 flex items-center gap-2">
                  <span>{entry.client_name}</span>
                  <button
                    type="button"
                    class="opacity-60 hover:opacity-100"
                    phx-click="cancel-upload"
                    phx-value-ref={entry.ref}
                  >
                    remove
                  </button>
                </div>
                <%= for err <- upload_errors(@uploads.manuscript, entry) do %>
                  <p class="text-[var(--mg-accent)] text-[0.75rem] mt-1">{error_to_string(err)}</p>
                <% end %>
              <% end %>
            </div>
          </div>

          <div class="flex items-center gap-3 text-[var(--mg-dim)]">
            <hr class="flex-1 border-0 border-t border-[var(--mg-rule)]" />
            <span class="mg-label">or</span>
            <hr class="flex-1 border-0 border-t border-[var(--mg-rule)]" />
          </div>

          <.input
            field={@form[:body]}
            type="textarea"
            rows="12"
            label="Paste the draft"
            placeholder="Paste the whole thing. Chapter headings or markdown headings help it divide the draft correctly."
          />

          <button type="submit" class="mg-btn">Continue</button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  defp error_to_string(:too_large), do: "That file is too big (8MB limit)."
  defp error_to_string(:not_accepted), do: "Only .txt and .md for now."
  defp error_to_string(:too_many_files), do: "One file at a time."
  defp error_to_string(other), do: to_string(other)
end
