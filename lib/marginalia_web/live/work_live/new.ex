defmodule MarginaliaWeb.WorkLive.New do
  @moduledoc """
  Upload a draft.

  Paste or drop a text file. The intent field is optional and does more work
  than it looks like it does: every note is written against what the writer
  says the draft is supposed to do, which is what keeps the read from
  defaulting to generic craft advice.
  """
  use MarginaliaWeb, :live_view

  alias Marginalia.Works

  @max_words 120_000

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Upload a draft", error: nil, preview: nil)
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
        [{name, contents} | _] ->
          {blank(params["title"]) || Path.rootname(name), contents}

        [] ->
          {blank(params["title"]) || "Untitled draft", params["body"] || ""}
      end

    words = length(String.split(body, ~r/\s+/, trim: true))

    cond do
      words == 0 ->
        {:noreply, assign(socket, error: "There's no text there yet — paste a draft or attach a file.")}

      words > @max_words ->
        {:noreply,
         assign(socket,
           error:
             "That's #{format_int(words)} words, and the limit is #{format_int(@max_words)} for now. Split it and upload the first part."
         )}

      true ->
        attrs = %{"title" => title, "body" => body, "intent" => blank(params["intent"])}

        case Works.create_work(socket.assigns.current_scope.user.id, attrs) do
          {:ok, work} ->
            {:noreply, push_navigate(socket, to: ~p"/works/#{work.slug}")}

          {:error, %Ecto.Changeset{} = cs} ->
            {:noreply, assign(socket, form: to_form(cs), error: nil)}

          {:error, :no_sections} ->
            {:noreply, assign(socket, error: "Couldn't find any text to split into sections.")}
        end
    end
  end

  defp blank(nil), do: nil
  defp blank(""), do: nil
  defp blank(s), do: String.trim(s)

  defp format_int(n) do
    n |> Integer.to_string() |> String.reverse() |> String.replace(~r/(\d{3})(?=\d)/, "\\1,") |> String.reverse()
  end

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
          <div class="mt-5 border-l-2 border-[var(--mg-accent)] pl-3 py-1.5 text-[0.85rem]">{@error}</div>
        <% end %>

        <.form for={@form} phx-change="validate" phx-submit="save" class="mt-6 space-y-5">
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
