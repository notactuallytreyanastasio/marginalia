defmodule MarginaliaWeb.WorkLive.Index do
  @moduledoc """
  A writer's drafts, as a tree of folders.

  The list used to be flat and ordered by id, which is the right shape for
  five drafts and the wrong one for fifty. Folders are made here and filled by
  dragging, because the thing a writer wants to say — *this one goes with
  those* — is a gesture, and a select box asking them to name the destination
  again for each draft is that gesture spelled out longhand.
  """
  use MarginaliaWeb, :live_view

  alias Marginalia.{Folders, Works}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Your drafts", collapsed: MapSet.new(), renaming: nil)
     |> load()}
  end

  defp load(socket) do
    user_id = socket.assigns.current_scope.user.id
    tree = Folders.tree(user_id)

    assign(socket,
      tree: tree,
      count: total(tree),
      unfiled: Folders.unfiled_collection_count(user_id)
    )
  end

  defp total(node),
    do: length(node.works) + Enum.sum(Enum.map(node.folders, & &1.count))

  # ==========================================================================
  # Events
  # ==========================================================================

  @impl true
  def handle_event("new_folder", %{"name" => name}, socket) do
    user_id = socket.assigns.current_scope.user.id

    case String.trim(name) do
      "" ->
        {:noreply, socket}

      name ->
        case Folders.create_folder(user_id, %{name: name}) do
          {:ok, _folder} -> {:noreply, load(socket)}
          {:error, changeset} -> {:noreply, put_flash(socket, :error, first_error(changeset))}
        end
    end
  end

  def handle_event("backfill", _params, socket) do
    user_id = socket.assigns.current_scope.user.id

    case Folders.backfill_from_collections(user_id) do
      {:ok, 0} ->
        {:noreply, socket}

      {:ok, n} ->
        {:noreply,
         socket
         |> put_flash(:info, "Filed #{n} #{if n == 1, do: "draft", else: "drafts"} by case.")
         |> load()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not file those.")}
    end
  end

  def handle_event("toggle", %{"id" => id}, socket) do
    id = String.to_integer(id)
    collapsed = socket.assigns.collapsed

    collapsed =
      if MapSet.member?(collapsed, id),
        do: MapSet.delete(collapsed, id),
        else: MapSet.put(collapsed, id)

    {:noreply, assign(socket, collapsed: collapsed)}
  end

  def handle_event("rename_start", %{"id" => id}, socket) do
    {:noreply, assign(socket, renaming: String.to_integer(id))}
  end

  def handle_event("rename_cancel", _params, socket) do
    {:noreply, assign(socket, renaming: nil)}
  end

  def handle_event("rename", %{"folder_id" => id, "name" => name}, socket) do
    user_id = socket.assigns.current_scope.user.id

    case Folders.rename_folder(user_id, id, name) do
      {:ok, _folder} ->
        {:noreply, socket |> assign(renaming: nil) |> load()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, put_flash(socket, :error, first_error(changeset))}

      {:error, _} ->
        {:noreply, assign(socket, renaming: nil)}
    end
  end

  def handle_event("delete_folder", %{"id" => id}, socket) do
    user_id = socket.assigns.current_scope.user.id

    case Folders.delete_folder(user_id, id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Folder gone. What was in it moved up a level.")
         |> load()}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  # One event for both kinds of drop. The browser knows what was picked up and
  # what it landed on; the server decides whether that is allowed.
  def handle_event("move", %{"kind" => kind, "id" => id, "into" => into}, socket) do
    user_id = socket.assigns.current_scope.user.id
    into = if into in ["root", "", nil], do: nil, else: into

    result =
      case kind do
        "work" -> Folders.move_work(user_id, id, into)
        "folder" -> Folders.move_folder(user_id, id, into)
        _ -> {:error, :unknown}
      end

    case result do
      {:ok, _} ->
        {:noreply, load(socket)}

      {:error, :cycle} ->
        {:noreply, put_flash(socket, :error, "A folder cannot go inside itself.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, put_flash(socket, :error, first_error(changeset))}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    user_id = socket.assigns.current_scope.user.id

    case Works.get_work(user_id, id) do
      nil ->
        {:noreply, socket}

      work ->
        {:ok, _} = Works.delete_work(work)
        {:noreply, socket |> put_flash(:info, "Deleted.") |> load()}
    end
  end

  defp first_error(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Enum.flat_map(fn {field, msgs} -> Enum.map(msgs, &"#{field} #{&1}") end)
    |> List.first()
    |> Kernel.||("That did not work.")
  end

  # ==========================================================================
  # Render
  # ==========================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-4xl px-6 py-10">
        <div class="flex items-baseline gap-3 border-b border-[var(--mg-rule)] pb-4">
          <h1 style="font-family:var(--mg-serif)" class="text-2xl font-semibold tracking-tight">
            Your drafts
          </h1>
          <span class="mg-meta">{@count}</span>
          <form id="new-folder" phx-submit="new_folder" class="ml-auto flex items-center gap-2">
            <input
              type="text"
              name="name"
              value=""
              autocomplete="off"
              placeholder="New folder"
              class="mg-input sm mg-newfolder"
            />
            <button class="mg-btn sm ghost" type="submit">add folder</button>
          </form>
          <.link navigate={~p"/works/new"} class="mg-btn">Upload a draft</.link>
        </div>

        <p :if={@unfiled > 0} class="mg-tidy">
          {@unfiled} of these already say which case they belong to.
          <button phx-click="backfill" class="mg-btn sm ghost">file them by case</button>
        </p>

        <%= if @count == 0 and @tree.folders == [] do %>
          <p class="mg-empty mt-8">Nothing here yet. Bring the draft in the drawer.</p>
        <% else %>
          <div id="tree" phx-hook=".Tree" class="mg-tree mt-2">
            <div class="mg-tree-root" data-drop-kind="folder" data-drop-id="root">
              <.level node={@tree} collapsed={@collapsed} renaming={@renaming} depth={0} />
              <p :if={@tree.folders != []} class="mg-tree-hint">
                drag a draft onto a folder to file it · drop it out here to unfile it
              </p>
            </div>
          </div>
        <% end %>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".Tree">
        // Native HTML5 drag and drop, delegated from the tree container so it
        // survives every re-render LiveView does underneath it. No library:
        // this is dragstart, dragover, drop, and the work is in deciding what
        // is under the cursor.
        //
        // The one real rule is that a folder cannot be dropped into its own
        // subtree. Because a folder's children are rendered *inside* its
        // element, that rule is just `dragged.contains(target)` — the illegal
        // targets are exactly the ones the dragged element encloses. The
        // server checks it again by walking parent_id, since this is a fact
        // about the tree rather than about the mouse.
        export default {
          mounted() {
            this.drag = null;

            this.on("dragstart", (e) => {
              const row = e.target.closest("[data-drag-id]");
              if (!row || !this.el.contains(row)) return;
              this.drag = {
                el: row,
                kind: row.dataset.dragKind,
                id: row.dataset.dragId,
              };
              row.classList.add("is-dragging");
              e.dataTransfer.effectAllowed = "move";
              // Firefox will not start a drag at all unless the payload is set.
              e.dataTransfer.setData("text/plain", row.dataset.dragId);
            });

            this.on("dragend", () => this.clear());

            // dragover is the only place the highlight is decided. A
            // dragleave handler is the obvious way to turn it off and the
            // wrong one: leave fires every time the cursor crosses into a
            // child of the row it is already over, so the row you are aiming
            // at strobes while you hold still.
            this.on("dragover", (e) => {
              const target = this.target(e);
              if (!target) return this.unlight();
              e.preventDefault();
              e.dataTransfer.dropEffect = "move";
              if (target !== this.lit) {
                this.unlight();
                this.lit = target;
                target.classList.add("is-over");
              }
            });

            this.on("drop", (e) => {
              const target = this.target(e);
              if (!target) return this.clear();
              e.preventDefault();
              const into = target.dataset.dropId;
              const drag = this.drag;
              this.clear();
              // Dropping something back where it already was is not a move.
              if (drag.kind === "folder" && into === drag.id) return;
              this.pushEvent("move", {kind: drag.kind, id: drag.id, into: into});
            });
          },

          destroyed() { this.clear(); },

          on(name, fn) { this.el.addEventListener(name, fn); },

          // The drop zone under the cursor, or null if this drop is illegal.
          target(e) {
            if (!this.drag) return null;
            const zone = e.target.closest("[data-drop-id]");
            if (!zone || !this.el.contains(zone)) return null;
            if (this.drag.el.contains(zone)) return null;
            return zone;
          },

          unlight() {
            if (this.lit) this.lit.classList.remove("is-over");
            this.lit = null;
          },

          clear() {
            this.unlight();
            if (this.drag) this.drag.el.classList.remove("is-dragging");
            this.drag = null;
          },
        }
      </script>
    </Layouts.app>
    """
  end

  attr :node, :map, required: true
  attr :collapsed, :any, required: true
  attr :renaming, :any, required: true
  attr :depth, :integer, required: true

  defp level(assigns) do
    ~H"""
    <div
      :for={child <- @node.folders}
      class="mg-fold"
      draggable="true"
      data-drag-kind="folder"
      data-drag-id={child.folder.id}
    >
      <div
        class="mg-frow"
        data-drop-kind="folder"
        data-drop-id={child.folder.id}
        style={"padding-left:#{@depth * 1.25 + 0.4}rem"}
      >
        <button
          type="button"
          class="mg-twist"
          phx-click="toggle"
          phx-value-id={child.folder.id}
          aria-label={if open?(@collapsed, child.folder.id), do: "Collapse", else: "Expand"}
        >{if open?(@collapsed, child.folder.id), do: "▾", else: "▸"}</button>

        <%= if @renaming == child.folder.id do %>
          <form
            id={"rename-#{child.folder.id}"}
            phx-submit="rename"
            class="flex flex-1 items-center gap-2"
          >
            <input type="hidden" name="folder_id" value={child.folder.id} />
            <input
              type="text"
              name="name"
              value={child.folder.name}
              autocomplete="off"
              class="mg-input sm flex-1"
              phx-mounted={JS.focus()}
              phx-window-keydown="rename_cancel"
              phx-key="Escape"
            />
            <button class="mg-btn sm ghost" type="submit">save</button>
          </form>
        <% else %>
          <button
            type="button"
            class="mg-fname"
            phx-click="toggle"
            phx-value-id={child.folder.id}
          >{child.folder.name}</button>
          <span class="mg-meta">{child.count}</span>
          <span class="mg-frow-tools">
            <button
              class="mg-btn sm ghost"
              phx-click="rename_start"
              phx-value-id={child.folder.id}
            >rename</button>
            <button
              class="mg-btn sm ghost"
              phx-click="delete_folder"
              phx-value-id={child.folder.id}
              data-confirm="Delete this folder? The drafts in it move up a level, they are not deleted."
            >delete</button>
          </span>
        <% end %>
      </div>

      <div
        :if={open?(@collapsed, child.folder.id)}
        class="mg-fkids"
        style={"--rail:#{@depth * 1.25 + 0.95}rem"}
      >
        <p :if={child.folders == [] and child.works == []} class="mg-fempty">
          empty — drag a draft here
        </p>
        <.level node={child} collapsed={@collapsed} renaming={@renaming} depth={@depth + 1} />
      </div>
    </div>

    <div
      :for={w <- @node.works}
      class="mg-wrow"
      draggable="true"
      data-drag-kind="work"
      data-drag-id={w.id}
      style={"padding-left:#{@depth * 1.25 + 0.4}rem"}
    >
      <span class="mg-grip" aria-hidden="true">⠿</span>
      <div class="min-w-0 flex-1">
        <.link
          navigate={~p"/works/#{w.slug}"}
          style="font-family:var(--mg-serif)"
          class="text-[1.1rem] hover:text-[var(--mg-accent)]"
        >{w.title}</.link>
        <div class="mg-meta mt-0.5">{w.word_count} words</div>
      </div>
      <span class={"mg-badge " <> if(w.status == "read", do: "ink", else: "")}>{w.status}</span>
      <button
        class="mg-btn sm ghost"
        phx-click="delete"
        phx-value-id={w.id}
        data-confirm="Delete this draft, its map and its conversations?"
      >delete</button>
    </div>
    """
  end

  defp open?(collapsed, id), do: not MapSet.member?(collapsed, id)
end
