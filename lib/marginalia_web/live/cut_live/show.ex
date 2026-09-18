defmodule MarginaliaWeb.CutLive.Show do
  @moduledoc """
  What a folder turned out to say.

  The members are the spine of the page, not a footnote to it. A reading whose
  evidence you cannot walk back into is a paragraph you have to take on faith,
  and the whole point of doing this over a folder is that the folder is still
  right there to check against.
  """
  use MarginaliaWeb, :live_view

  alias Marginalia.Cuts

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user_id = socket.assigns.current_scope.user.id

    case Cuts.get_cut(user_id, id) do
      nil ->
        {:ok, socket |> put_flash(:error, "No such reading.") |> push_navigate(to: ~p"/cuts")}

      cut ->
        socket =
          socket
          |> assign(page_title: cut.title, cut: cut, focus: nil)
          |> assign_weave()

        {:ok, if(cut.status == "draft", do: start_read(socket), else: socket)}
    end
  end

  defp start_read(socket) do
    user_id = socket.assigns.current_scope.user.id
    {:ok, cut} = Cuts.set_status(socket.assigns.cut, "reading")

    socket
    |> assign(cut: cut)
    |> start_async(:read, fn -> Cuts.read(cut, user_id) end)
  end

  defp reload(socket) do
    user_id = socket.assigns.current_scope.user.id
    assign_weave(assign(socket, cut: Cuts.get_cut(user_id, socket.assigns.cut.id)))
  end

  @doc false
  # Who is in this folder is knowable before the read and does not change
  # because of it, so the page can show the members while it waits. What the
  # read adds is which of them turned out to be connected.
  defp assign_weave(socket) do
    user_id = socket.assigns.current_scope.user.id
    cut = socket.assigns.cut

    members =
      case cut.members do
        m when is_list(m) and m != [] -> m
        _ -> cut.folder_id |> then(&Cuts.members(user_id, &1)) |> Enum.map(&stringify/1)
      end

    assign(socket, members: members, links: links(cut))
  end

  defp stringify(m),
    do: %{"n" => m.n, "kind" => m.kind, "id" => m.id, "label" => m.label, "read?" => m.read?}

  # A claim is an edge between every pair of members it cites: that is what
  # "holds across two or more" means, drawn.
  defp links(%{status: "read"} = cut) do
    for {items, kind} <- [{cut.threads || [], "thread"}, {cut.tensions || [], "tension"}],
        item <- items,
        pair <- pairs(Enum.map(item["evidence"] || [], & &1["member"]) |> Enum.uniq()),
        do: %{"a" => elem(pair, 0), "b" => elem(pair, 1), "kind" => kind}
  end

  defp links(_cut), do: []

  defp pairs(ns) do
    for a <- ns, b <- ns, a < b, do: {a, b}
  end

  @impl true
  def handle_async(:read, {:ok, {:ok, _}}, socket), do: {:noreply, reload(socket)}

  def handle_async(:read, {:ok, other}, socket),
    do: {:noreply, socket |> reload() |> put_flash(:error, "The read stopped: #{inspect(other)}")}

  def handle_async(:read, {:exit, reason}, socket) do
    {:ok, cut} = Cuts.set_status(socket.assigns.cut, "failed", inspect(reason))
    {:noreply, socket |> assign(cut: cut) |> put_flash(:error, "The read crashed.")}
  end

  @impl true
  def handle_event("again", _params, socket), do: {:noreply, start_read(socket)}

  def handle_event("focus", %{"n" => n}, socket) do
    n = String.to_integer(n)
    {:noreply, assign(socket, focus: if(socket.assigns.focus == n, do: nil, else: n))}
  end

  def handle_event("delete", _params, socket) do
    {:ok, _} = Cuts.delete_cut(socket.assigns.cut)
    {:noreply, socket |> put_flash(:info, "Reading deleted.") |> push_navigate(to: ~p"/cuts")}
  end

  # ==========================================================================

  @impl true
  def render(assigns) do
    user_id = assigns.current_scope.user.id

    assigns =
      assign(assigns,
        members: assigns.cut.members || [],
        stale: assigns.cut.status == "read" and not Cuts.current?(assigns.cut, user_id)
      )

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-3xl px-6 py-10">
        <div class="mg-meta"><.link navigate={~p"/cuts"}>← every reading</.link></div>
        <h1 style="font-family:var(--mg-serif)" class="mt-2 text-2xl font-semibold tracking-tight">
          {@cut.title}
        </h1>
        <p :if={@cut.question not in [nil, ""]} class="cut-ask">{@cut.question}</p>

        <%!-- The read is asking whether anything holds across two or more of
              these, so while it runs the page draws pairs being tried, and
              when it lands the pairs that held stay drawn. Members first,
              because they are knowable before the answer is. --%>
        <div
          :if={@members != []}
          id={"weave-#{@cut.id}"}
          class="cut-weave"
          phx-hook=".Weave"
          phx-update="ignore"
          data-status={@cut.status}
          data-members={Jason.encode!(@members)}
          data-links={Jason.encode!(@links)}
        >
          <svg aria-hidden="true"></svg>
        </div>

        <%!-- who was read. Clicking one lights the claims that rest on it. --%>
        <div :if={@members != []} class="cut-members">
          <button
            :for={m <- @members}
            type="button"
            phx-click="focus"
            phx-value-n={m["n"]}
            class={"cut-member" <> if(@focus == m["n"], do: " on", else: "")}
          >
            <span class="i">{m["n"]}</span>
            <span class="l">{m["label"]}</span>
            <span :if={m["kind"] == "folder" and not m["read?"]} class="u">not read</span>
          </button>
        </div>
        <p :if={Enum.any?(@members, &(&1["kind"] == "folder" and not &1["read?"]))} class="cut-hole">
          Some of these have not been read yet, so this stands on their titles rather than
          on what they say. Read them first and this will be worth more.
        </p>

        <%= case @cut.status do %>
          <% "reading" -> %>
            <p class="cut-working">Reading this folder. One call, and it is the slow kind.</p>
          <% "failed" -> %>
            <p class="cut-err mt-6">
              {@cut.status_detail}
              <button class="mg-btn sm ghost ml-2" phx-click="again">try again</button>
            </p>
          <% "read" -> %>
            <p :if={@stale} class="cut-stale">
              This folder has changed since it was read.
              <button class="mg-btn sm ghost ml-2" phx-click="again">read again</button>
            </p>

            <h2 class="cut-h">Thesis</h2>
            <p class="cut-thesis">{@cut.thesis}</p>

            <.group title="Through-lines" items={@cut.threads} focus={@focus} />
            <.group title="Tensions" items={@cut.tensions} focus={@focus} />

            <div :if={@cut.not_supported not in [nil, ""]}>
              <h2 class="cut-h">What this does not show</h2>
              <p class="cut-body">{@cut.not_supported}</p>
            </div>
          <% _ -> %>
            <p class="cut-working">Queued.</p>
        <% end %>

        <div class="mt-10 flex flex-wrap items-center gap-2 border-t border-[var(--mg-rule)] pt-4">
          <button :if={@cut.status == "read"} class="mg-btn sm ghost" phx-click="again">
            read again
          </button>
          <span :if={@cut.dropped != []} class="mg-meta">
            {length(@cut.dropped)} claim{if length(@cut.dropped) == 1, do: "", else: "s"} dropped
            for quotes that could not be found
          </span>
          <button
            class="mg-btn sm ghost ml-auto"
            phx-click="delete"
            data-confirm="Delete this reading?"
          >delete</button>
        </div>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".Weave">
        // A member per row, and arcs between the pairs a claim rests on.
        //
        // While the read runs, the arcs shown are *candidates*: every pair of
        // members, tried one at a time. That is not decoration — it is the
        // question being asked, which is whether anything holds across two or
        // more of these. When the answer lands the candidates stop and the
        // pairs that actually held are drawn in, so the waiting state and the
        // result are the same picture at two moments.
        const ROW = 26, PAD = 12, GUT = 22;

        export default {
          mounted() { this.draw(); },
          updated() { this.draw(); },
          destroyed() { this.stop(); },

          stop() {
            cancelAnimationFrame(this.frame);
            clearTimeout(this.timer);
            this.frame = this.timer = null;
          },

          draw() {
            this.stop();
            const members = JSON.parse(this.el.dataset.members || "[]");
            const links = JSON.parse(this.el.dataset.links || "[]");
            const reading = this.el.dataset.status === "reading";
            const svg = this.el.querySelector("svg");
            if (members.length < 2) { svg.innerHTML = ""; this.el.hidden = true; return; }

            const h = PAD * 2 + members.length * ROW;
            const w = 280;
            svg.setAttribute("viewBox", `0 0 ${w} ${h}`);
            svg.setAttribute("height", h);
            const y = (n) => PAD + (n - 1) * ROW + ROW / 2;

            const rows = members.map((m) => `
              <line class="cw-rule" x1="${GUT}" y1="${y(m.n)}" x2="${w - 8}" y2="${y(m.n)}"></line>
              <circle class="cw-dot" cx="${GUT}" cy="${y(m.n)}" r="3.2"></circle>
              <text class="cw-lbl" x="${GUT - 10}" y="${y(m.n) + 3.5}">${m.n}</text>`).join("");

            // The `d` alone, so both kinds of arc keep their class name as a
            // literal in the markup they build. A class that only exists as a
            // function argument is one nothing can check for.
            const curve = (a, b) => {
              const y1 = y(a), y2 = y(b);
              const bulge = Math.min(46, 14 + Math.abs(y1 - y2) * 0.42);
              return `M ${GUT} ${y1} C ${GUT + bulge} ${y1}, ${GUT + bulge} ${y2}, ${GUT} ${y2}`;
            };

            svg.innerHTML = rows + links.map((l) =>
              `<path class="cw-arc k-${l.kind}" fill="none" d="${curve(l.a, l.b)}"></path>`
            ).join("");

            // draw the settled arcs in, once
            svg.querySelectorAll(".cw-arc").forEach((p, i) => {
              const len = p.getTotalLength();
              p.style.strokeDasharray = len;
              p.style.strokeDashoffset = len;
              p.style.animation = `cw-draw .7s ease ${0.1 + i * 0.09}s forwards`;
            });

            if (reading) this.tryPairs(svg, members, curve);
          },

          // Every pair, in order, on a loop. The order is fixed rather than
          // random so two people watching the same folder see the same thing.
          tryPairs(svg, members, curve) {
            if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
            const pairs = [];
            for (let i = 0; i < members.length; i++)
              for (let j = i + 1; j < members.length; j++)
                pairs.push([members[i].n, members[j].n]);

            let k = 0;
            const step = () => {
              svg.querySelectorAll(".cw-try").forEach((n) => n.remove());
              const [a, b] = pairs[k % pairs.length];
              svg.insertAdjacentHTML(
                "beforeend",
                `<path class="cw-try" fill="none" d="${curve(a, b)}"></path>`
              );
              const p = svg.querySelector(".cw-try");
              const len = p.getTotalLength();
              p.style.setProperty("--len", len);
              p.style.strokeDasharray = len;
              p.style.strokeDashoffset = len;
              p.style.animation = "cw-try 1.15s ease-in-out forwards";
              [a, b].forEach((n) => {
                const dot = svg.querySelectorAll(".cw-dot")[n - 1];
                if (dot) { dot.classList.remove("lit"); void dot.offsetWidth; dot.classList.add("lit"); }
              });
              k++;
              this.timer = setTimeout(step, 1250);
            };
            step();
          },
        }
      </script>
    </Layouts.app>
    """
  end

  attr :title, :string, required: true
  attr :items, :list, required: true
  attr :focus, :any, required: true

  defp group(assigns) do
    assigns = assign(assigns, :items, shown(assigns.items, assigns.focus))

    ~H"""
    <div :if={@items != []}>
      <h2 class="cut-h">{@title}</h2>
      <div :for={item <- @items} class="cut-claim">
        <p class="c">{item["claim"]}</p>
        <blockquote :for={ev <- item["evidence"] || []}>
          {ev["quote"]}
          <cite>{ev["label"] || "member #{ev["member"]}"}</cite>
        </blockquote>
      </div>
    </div>
    """
  end

  # Focusing a member narrows to the claims that actually cite it — the
  # question "what is this one doing here" answered by subtraction.
  defp shown(items, nil), do: items || []

  defp shown(items, n) do
    (items || [])
    |> Enum.filter(fn i ->
      Enum.any?(i["evidence"] || [], &(&1["member"] == n))
    end)
  end
end
