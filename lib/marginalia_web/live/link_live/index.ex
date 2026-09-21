defmodule MarginaliaWeb.LinkLive.Index do
  @moduledoc """
  Every pair of drafts this writer has related, and the way to make another.

  The Link button on a draft answers "relate this one to something". This
  page answers the other question — "what have I related, and to what" —
  which the per-draft menu cannot, because a link belongs to two drafts and
  appears under both.

  Making one here is the same one click: pick two, and the pass that reads
  both graphs starts. The row then fills in live, so the page can be left
  open while it runs.
  """
  use MarginaliaWeb, :live_view

  alias Marginalia.{Folders, Links, Works}
  alias Marginalia.Links.Bulk
  alias Marginalia.Analysis.Linker

  # How many pairs to draw before asking. Four hundred rows is not a list, it
  # is a wall — and the page above them holds two tools and a diagram per
  # cluster, so the list starts below the fold before a single row is drawn.
  @page 40

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    {:ok,
     socket
     |> assign(
       page_title: "Linked drafts",
       a: nil,
       b: nil,
       folders: Folders.list_folders(user.id),
       bulk_folder: nil,
       bulk: nil,
       bulk_running: false,
       filter: "",
       limit: @page
     )
     |> load(user)}
  end

  defp load(socket, user) do
    links = Links.for_user(user.id)

    assign(socket,
      user: user,
      links: links,
      clusters: Links.clusters(user.id),
      drafts: Links.linkable(user.id),
      unread: Enum.count(Works.list_works(user.id), &(&1.status != "read")),
      stats: Map.new(links, &{&1.id, Links.stats(&1)})
    )
  end

  @impl true
  # Triage first, relate second. A folder of a hundred and eleven is six
  # thousand pairs; the point of this button is to not run six thousand
  # model calls, so the cheap pass runs on its own and shows its work.
  def handle_event("bulk_propose", %{"folder" => id}, socket) do
    user = socket.assigns.user

    case Integer.parse(id) do
      {folder_id, _} ->
        provider = Marginalia.Accounts.provider_for(user)

        {:noreply,
         socket
         |> assign(bulk_running: true, bulk: nil, bulk_folder: folder_id)
         |> start_async(:bulk, fn ->
           Bulk.run(user.id, folder_id, provider: provider, propose_only: true)
         end)}

      _ ->
        {:noreply, socket}
    end
  end

  # Only now does anything cost per pair, and only the pairs shown above.
  def handle_event("bulk_relate", _params, socket) do
    %{user: user, bulk: bulk} = socket.assigns

    if bulk && bulk.pairs != [] do
      provider = Marginalia.Accounts.provider_for(user)
      pairs = bulk.pairs

      {:noreply,
       socket
       |> assign(bulk_running: true)
       |> start_async(:relate, fn ->
         {:ok, Marginalia.Links.Bulk.relate_pairs(pairs, provider: provider)}
       end)}
    else
      {:noreply, socket}
    end
  end

  # Narrowing happens here rather than over the wire per keystroke: the pairs
  # are already in the socket, and matching four hundred titles is cheaper
  # than asking the database what it already told us.
  def handle_event("filter", %{"q" => q}, socket),
    do: {:noreply, assign(socket, filter: q, limit: @page)}

  def handle_event("more", _params, socket),
    do: {:noreply, assign(socket, limit: socket.assigns.limit + @page)}

  def handle_event("pick", params, socket) do
    {:noreply, assign(socket, a: id(params["a"]), b: id(params["b"]))}
  end

  def handle_event("make", params, socket) do
    socket =
      assign(socket,
        a: id(params["a"]) || socket.assigns.a,
        b: id(params["b"]) || socket.assigns.b
      )

    a = socket.assigns

    with true <- is_integer(a.a) and is_integer(a.b),
         true <- a.a != a.b,
         {:ok, link} <- Links.get_or_create(a.a, a.b) do
      if link.status not in ["linking"], do: Linker.start(link)

      {:noreply, push_navigate(socket, to: ~p"/links/#{link.id}")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Pick two different drafts.")}
    end
  end

  @impl true
  def handle_async(:bulk, {:ok, {:ok, result}}, socket),
    do: {:noreply, assign(socket, bulk_running: false, bulk: result)}

  def handle_async(:bulk, {:ok, {:error, reason}}, socket),
    do:
      {:noreply,
       socket
       |> assign(bulk_running: false)
       |> put_flash(:error, "Could not read that folder: #{inspect(reason)}")}

  def handle_async(:bulk, {:exit, reason}, socket),
    do:
      {:noreply,
       socket |> assign(bulk_running: false) |> put_flash(:error, "Crashed: #{inspect(reason)}")}

  def handle_async(:relate, {:ok, {:ok, out}}, socket) do
    {:noreply,
     socket
     |> assign(bulk_running: false, bulk: nil)
     |> load(socket.assigns.user)
     |> put_flash(:info, "Started #{length(out.started)} readings.")}
  end

  def handle_async(:relate, {:exit, reason}, socket),
    do:
      {:noreply,
       socket |> assign(bulk_running: false) |> put_flash(:error, "Crashed: #{inspect(reason)}")}

  # Either title, case-insensitively. A pair is two documents and somebody
  # looking for one of them does not know or care which side it landed on.
  defp matching(links, q) do
    case String.trim(q || "") do
      "" ->
        links

      q ->
        q = String.downcase(q)

        Enum.filter(links, fn l ->
          String.contains?(String.downcase(l.a_work.title || ""), q) or
            String.contains?(String.downcase(l.b_work.title || ""), q)
        end)
    end
  end

  @impl true
  def render(assigns) do
    found = matching(assigns.links, assigns.filter)

    assigns =
      assign(assigns,
        found: found,
        shown: Enum.take(found, assigns.limit),
        webs: Enum.filter(assigns.clusters, &(length(&1.works) > 2)),
        page: @page
      )

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="lx">
        <h1>Linked drafts</h1>
        <p class="lede">
          A link relates two drafts' <strong>maps</strong> — every beat, the spine, the
          threads — and draws the edges between them: what develops what, what answers what,
          where they argue. Both drafts have to have been read first, because that is what
          produces the maps.
        </p>

        <%!-- Triage, then relate. A folder of 111 documents is 6,105 pairs, so
              the cheap pass runs alone and shows what it chose before
              anything is spent per pair. --%>
        <%!-- Folded. It is the tool you reach for once and then scroll past
              every time afterwards, and it sits between the page's title and
              the thing the page is actually for. --%>
        <details :if={@folders != []} class="lx-fold" open={@bulk != nil or @bulk_running}>
          <summary><span class="mg-label">relate a whole folder</span></summary>

          <form phx-submit="bulk_propose" class="lx-bulk-pick">
            <select name="folder" disabled={@bulk_running}>
              <option :for={f <- @folders} value={f.id}>{f.name}</option>
            </select>
            <button type="submit" class="mg-btn sm" disabled={@bulk_running}>
              {if @bulk_running, do: "Reading the folder…", else: "Work out what to relate"}
            </button>
          </form>

          <div :if={@bulk} class="lx-bulk-out">
            <p :if={@bulk.pairs == []} class="none">
              Nothing in that folder looked worth relating.
            </p>

            <ol :if={@bulk.pairs != []} class="mg-rows">
              <li :for={p <- @bulk.pairs}>
                <span class="n">{p.expect}</span>
                <strong>{p.a.title}</strong>
                ↔ <strong>{p.b.title}</strong>
                <p class="mg-meta">{p.why}</p>
              </li>
            </ol>

            <p :if={@bulk.skipped != ""} class="mg-meta">
              Left out: {@bulk.skipped}
            </p>

            <p :if={@bulk.dropped != []} class="cut-err">
              {length(@bulk.dropped)} proposal(s) discarded: {Enum.join(@bulk.dropped, "; ")}
            </p>

            <p :if={Bulk.ineligible(@bulk.pairs) != []} class="cut-err">
              {length(Bulk.ineligible(@bulk.pairs))} of these cannot be read yet — {Enum.join(
                Bulk.ineligible(@bulk.pairs),
                "; "
              )}
            </p>

            <button
              :if={@bulk.pairs != [] and Bulk.ineligible(@bulk.pairs) != @bulk.pairs}
              class="mg-btn sm"
              phx-click="bulk_relate"
              disabled={@bulk_running}
              data-confirm="Read each of these pairs against each other? That is one model call per pair."
            >
              Relate these {length(@bulk.pairs) - length(Bulk.ineligible(@bulk.pairs))}
            </button>
          </div>
        </details>

        <div class="lx-make">
          <span class="mg-label">relate two drafts</span>

          <%= if length(@drafts) < 2 do %>
            <p class="none">
              You need two drafts that have been read. <.link navigate={~p"/works/new"}>Upload another</.link>.
            </p>
          <% else %>
            <%!-- One form, two selects. It was two forms, one per select,
                  and neither carried an id — so every change appended a
                  fresh copy instead of patching the existing one and the
                  row filled up with dead dropdowns. --%>
            <form id="make-link" class="row" phx-change="pick" phx-submit="make">
              <select id="pick-a" name="a" class="lx-pick">
                <option value="">Choose a draft…</option>
                <option
                  :for={d <- @drafts}
                  value={d.id}
                  selected={@a == d.id}
                  disabled={@b == d.id}
                >
                  {d.title} · {d.word_count}w
                </option>
              </select>

              <span class="x" aria-hidden="true">↔</span>

              <select id="pick-b" name="b" class="lx-pick">
                <option value="">Choose a draft…</option>
                <option
                  :for={d <- @drafts}
                  value={d.id}
                  selected={@b == d.id}
                  disabled={@a == d.id}
                >
                  {d.title} · {d.word_count}w
                </option>
              </select>

              <button type="submit" class="mg-btn" disabled={is_nil(@a) or is_nil(@b)}>
                Link them
              </button>
            </form>
          <% end %>

          <%!-- shown whether or not the picker is: someone with a draft
                part-way through the read will otherwise just find it
                missing from the list and wonder --%>
          <p :if={@unread > 0} class="none pending">
            {@unread} {if @unread == 1, do: "draft is", else: "drafts are"} still being read.
            They can be linked once that finishes.
          </p>
        </div>

        <%= if @links == [] do %>
          <p class="none mt-8">Nothing linked yet.</p>
        <% else %>
          <%!-- Links are pairs, but pairs chain. Three documents with two
                links between them are one body of work, and a flat list of
                pairs is the one shape that cannot show that.

                Folded, because each of these is a 300px diagram and a
                writer with nine clusters had three screens of them between
                the top of the page and the first row of the list. --%>
          <details :if={@webs != []} class="lx-fold">
            <summary>
              <span class="mg-label">
                {length(@webs)} {if length(@webs) == 1, do: "web", else: "webs"} of three or more
              </span>
            </summary>

            <div :for={c <- @webs} class="lx-web">
              <span class="mg-label">{length(c.works)} drafts, {length(c.links)} links</span>
              <.constellation cluster={c} />
            </div>
          </details>

          <form phx-change="filter" id="lx-filter" class="lx-filter">
            <input
              type="text"
              name="q"
              value={@filter}
              placeholder="narrow by either draft's title"
              autocomplete="off"
              phx-debounce="150"
            />
            <span class="mg-label">
              {length(@found)} of {length(@links)} linked
            </span>
          </form>

          <p :if={@found == []} class="none">
            Nothing matches “{@filter}”.
          </p>

          <.link :for={l <- @shown} navigate={~p"/links/#{l.id}"} class="lx-row">
            <div class="min-w-0">
              <span class="pair">
                {l.a_work.title} <span class="x">↔</span> {l.b_work.title}
              </span>
              <p :if={l.summary} class="sum">{Links.summary(l)}</p>
              <p :if={l.status == "failed"} class="sum err">{l.error}</p>
            </div>

            <div class="right">
              <%= if l.status == "linked" do %>
                <span class="n">{@stats[l.id].edges} edges</span>
                <span :for={{t, n} <- top(@stats[l.id])} class={["k", t]}>{t} {n}</span>
              <% else %>
                <span class={["st", l.status]}>{l.status}</span>
              <% end %>
            </div>
          </.link>

          <div :if={length(@found) > length(@shown)} class="lx-more">
            <button class="mg-btn sm" phx-click="more">
              Show {min(@page, length(@found) - length(@shown))} more
              <span class="mg-meta">of {length(@found) - length(@shown)} left</span>
            </button>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  attr :cluster, :map, required: true

  # Each draft on a circle, every link a chord between two of them. Laid
  # out in Elixir rather than by a force simulation: these are handfuls of
  # documents, the positions should be the same every time you look, and a
  # graph that rearranges itself while you read it is worse than one that
  # is slightly less pretty.
  defp constellation(assigns) do
    works = assigns.cluster.works
    n = length(works)
    at = Map.new(Enum.with_index(works), fn {w, i} -> {w.id, point(i, n)} end)

    assigns = assign(assigns, at: at, n: n)

    ~H"""
    <svg class="lx-svg" viewBox="0 0 520 300" preserveAspectRatio="xMidYMid meet">
      <%!-- the pairs nobody has related yet, drawn as the question they are --%>
      <line
        :for={{a, b} <- @cluster.missing}
        x1={elem(@at[a.id], 0)}
        y1={elem(@at[a.id], 1)}
        x2={elem(@at[b.id], 0)}
        y2={elem(@at[b.id], 1)}
        class="gap"
      />

      <.link :for={l <- @cluster.links} navigate={~p"/links/#{l.id}"} class="edge">
        <line
          x1={elem(@at[l.a_work_id], 0)}
          y1={elem(@at[l.a_work_id], 1)}
          x2={elem(@at[l.b_work_id], 0)}
          y2={elem(@at[l.b_work_id], 1)}
        />
        <text
          x={mid(@at[l.a_work_id], @at[l.b_work_id], 0)}
          y={mid(@at[l.a_work_id], @at[l.b_work_id], 1)}
        >
          {count(l)}
        </text>
      </.link>

      <.link :for={w <- @cluster.works} navigate={~p"/works/#{w.slug}"} class="node">
        <circle cx={elem(@at[w.id], 0)} cy={elem(@at[w.id], 1)} r="7" />
        <text
          x={elem(@at[w.id], 0)}
          y={label_y(@at[w.id])}
          text-anchor="middle"
        >
          {short(w.title)}
        </text>
      </.link>
    </svg>

    <p :if={@cluster.missing != []} class="lx-gap">
      Not related yet:
      <span :for={{a, b} <- @cluster.missing} class="pair">
        {short(a.title)} ↔ {short(b.title)}
      </span>
    </p>
    """
  end

  # evenly around a circle, starting at the top
  defp point(i, n) do
    angle = :math.pi() * 2 * i / n - :math.pi() / 2
    {260 + 170 * :math.cos(angle), 150 + 105 * :math.sin(angle)}
  end

  defp mid({x1, _y1}, {x2, _y2}, 0), do: (x1 + x2) / 2
  defp mid({_x1, y1}, {_x2, y2}, 1), do: (y1 + y2) / 2 - 4

  # labels go below a node in the lower half and above in the upper, so they
  # never land on the chords crossing the middle
  defp label_y({_x, y}), do: if(y > 150, do: y + 22, else: y - 14)

  defp count(link), do: link |> Links.edges() |> length()

  defp short(title) when byte_size(title) > 32, do: String.slice(title, 0, 30) <> "…"
  defp short(title), do: title

  defp id(nil), do: nil
  defp id(""), do: nil

  defp id(v) when is_binary(v) do
    case Integer.parse(v) do
      {i, _} -> i
      :error -> nil
    end
  end

  defp id(v) when is_integer(v), do: v

  defp top(stats) do
    stats.by_type |> Enum.sort_by(fn {_t, n} -> -n end) |> Enum.take(3)
  end
end
