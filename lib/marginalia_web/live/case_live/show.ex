defmodule MarginaliaWeb.CaseLive.Show do
  @moduledoc """
  One case: its documents, and a way through the connections between them.

  The first version of this page put all 181 connections in one column and
  let the reader scroll. That is a dump, not a tool — nobody reads 181 of
  anything in order, and the question a reader actually arrives with is
  narrower than the page: where does the dissent answer the majority, what
  did the argument already settle, what does everyone keep saying about
  consent.

  So the connections live in a box you search and slice: by what kind of
  relation it is, by which two documents it runs between, and by any word
  in the reason or in either passage. The box scrolls; the page does not.
  """
  use MarginaliaWeb, :live_view

  alias Marginalia.{Cases, Links}

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case Cases.published() |> Enum.find(&(&1.slug == slug)) do
      nil ->
        {:ok, socket |> put_flash(:error, "No such case.") |> push_navigate(to: ~p"/cases")}

      c ->
        {:ok,
         socket
         |> assign(
           page_title: c.name,
           page_url: url(~p"/cases/#{c.slug}"),
           page_image: ~p"/images/og-cases.png",
           case: c,
           all: edges(c),
           q: "",
           kind: nil,
           pair: nil,
           open: nil,
           shut: false
         )
         |> filter()}
    end
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket),
    do: {:noreply, socket |> assign(q: q) |> filter()}

  def handle_event("kind", %{"k" => k}, socket),
    do: {:noreply, socket |> assign(kind: toggle(socket.assigns.kind, k)) |> filter()}

  def handle_event("pair", %{"p" => p}, socket),
    do: {:noreply, socket |> assign(pair: toggle(socket.assigns.pair, p)) |> filter()}

  def handle_event("clear", _params, socket),
    do: {:noreply, socket |> assign(q: "", kind: nil, pair: nil) |> filter()}

  def handle_event("open", %{"id" => id}, socket) do
    id = String.to_integer(id)
    {:noreply, assign(socket, open: if(socket.assigns.open == id, do: nil, else: id))}
  end

  def handle_event("toggle_docs", _params, socket),
    do: {:noreply, assign(socket, shut: !socket.assigns.shut)}

  defp toggle(current, value), do: if(current == value, do: nil, else: value)

  defp filter(socket) do
    a = socket.assigns
    q = a.q |> to_string() |> String.trim() |> String.downcase()

    shown =
      a.all
      |> Enum.filter(&(is_nil(a.kind) or &1.edge.edge_type == a.kind))
      |> Enum.filter(&(is_nil(a.pair) or &1.pair == a.pair))
      |> Enum.filter(&(q == "" or String.contains?(&1.haystack, q)))

    assign(socket, shown: shown)
  end

  # every connection in the case, flattened with what it needs to be found
  defp edges(c) do
    by_id = Map.new(c.works, &{&1.id, &1})

    c.links
    |> Enum.flat_map(fn link ->
      link
      |> Links.edges()
      |> Enum.map(fn e ->
        from = by_id[e.from.work_id]
        to = by_id[e.to.work_id]

        %{
          edge: e,
          link: link,
          from_work: from,
          to_work: to,
          pair: pair(from, to),
          haystack:
            [e.rationale, e.from.title, e.to.title, e.from.quote, e.to.quote]
            |> Enum.reject(&is_nil/1)
            |> Enum.join(" ")
            |> String.downcase()
        }
      end)
    end)
    |> Enum.sort_by(&order(&1.edge.edge_type))
  end

  defp pair(%{collection_role: a}, %{collection_role: b}), do: Enum.sort([a, b]) |> Enum.join("+")
  defp pair(_, _), do: "?"

  defp order("tension"), do: 0
  defp order("answers"), do: 1
  defp order("requires"), do: 2
  defp order("develops"), do: 3
  defp order("pays_off"), do: 4
  defp order(_), do: 5

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="cs-one">
        <div class="cs-one-top">
          <.link navigate={~p"/cases"} class="back">← all cases</.link>
          <h1>{@case.name}</h1>
          <span class="tally">
            {length(@case.works)} documents · {commas(@case.words)} words · {length(@all)} connections
          </span>
          <button class="fold" phx-click="toggle_docs">
            {if @shut, do: "show the documents", else: "hide the documents"}
          </button>
        </div>

        <div :if={not @shut} class="cs-docs">
          <section :for={w <- @case.works} class={["doc", w.collection_role]}>
            <div class="head">
              <span class="mg-label">{role(w)}</span>
              <span class="n">{w.word_count} words</span>
            </div>
            <p :if={w.first_impression} class="impression">
              {String.slice(w.first_impression, 0, 340)}…
            </p>
            <.link navigate={~p"/works/#{w.slug}"} class="open">Read it →</.link>
          </section>
        </div>

        <%!-- Straight into the thing this is all for: one document read
              down the left with another following along on the right. It
              was reachable only from inside a connection, three clicks and
              a scroll away from the top of the page. --%>
        <%!-- The whole case at once comes first. Reading the opinion
              against one other document at a time is the specialist move;
              what a reader wants on arrival is the opinion with everything
              else in the margin. --%>
        <div class="cs-all">
          <.link navigate={~p"/cases/#{@case.slug}/read"} class="cs-all-go">
            <span class="mg-label">read the case</span>
            <span class="t">{lead_title(@case)}</span>
            <span class="s">
              with {others_count(@case)} other documents in the margin — the dissent and the
              argument on the same paragraph
            </span>
          </.link>
        </div>

        <div class="cs-go">
          <span class="mg-label">or one against another</span>
          <div class="ways">
            <.link
              :for={l <- @case.links}
              navigate={~p"/links/#{l.id}?lead=#{lead_slug(@case, l)}"}
              class="way"
            >
              <span class="t">{way(@case, l)}</span>
              <span class="n">{count(l)} connections</span>
            </.link>
          </div>
        </div>

        <%!-- The connections, in a box you can slice rather than a column
              you scroll past. --%>
        <div class="cs-find">
          <div class="bar">
            <form phx-change="search" class="q" id="cs-q">
              <input
                type="search"
                name="q"
                value={@q}
                placeholder="Search the reasons and both passages — consent, Humphrey's, stare decisis…"
                phx-debounce="150"
                autocomplete="off"
              />
            </form>
            <span class="count">
              {length(@shown)}<span :if={length(@shown) != length(@all)}> of {length(@all)}</span>
            </span>
            <%!-- `or` demands a boolean on its left, and a nil filter is
                  not one: `false or nil` raises rather than returning nil --%>
            <button :if={filtered?(@q, @kind, @pair)} class="clear" phx-click="clear">clear</button>
          </div>

          <div class="chips">
            <button
              :for={{k, n} <- counts(@all, & &1.edge.edge_type)}
              class={["chip", k, @kind == k && "on"]}
              phx-click="kind"
              phx-value-k={k}
            >{String.replace(k, "_", " ")} <span class="n">{n}</span></button>

            <span class="sep" aria-hidden="true"></span>

            <button
              :for={{p, n} <- counts(@all, & &1.pair)}
              class={["chip pair", @pair == p && "on"]}
              phx-click="pair"
              phx-value-p={p}
            >{pair_label(p)} <span class="n">{n}</span></button>
          </div>

          <div class="rows" id="edges">
            <p :if={@shown == []} class="nothing">
              Nothing matches that. <button phx-click="clear">Clear the filters</button>
            </p>

            <div
              :for={e <- @shown}
              class={["row", e.edge.edge_type, @open == e.edge.id && "open"]}
            >
              <button phx-click="open" phx-value-id={e.edge.id}>
                <span class="rel">{String.replace(e.edge.edge_type, "_", " ")}</span>
                <span class="why">{e.edge.rationale}</span>
                <span class="who">{short(e.from_work)}→{short(e.to_work)}</span>
              </button>

              <div :if={@open == e.edge.id} class="both">
                <div class="side">
                  <span class="mg-label">{role(e.from_work)} · {e.edge.from.title}</span>
                  <blockquote :if={e.edge.from.quote}>{plain(e.edge.from.quote)}</blockquote>
                </div>
                <div class="side">
                  <span class="mg-label">{role(e.to_work)} · {e.edge.to.title}</span>
                  <blockquote :if={e.edge.to.quote}>{plain(e.edge.to.quote)}</blockquote>
                </div>
                <.link navigate={~p"/links/#{e.link.id}"} class="read">
                  Read these two side by side →
                </.link>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # the document you read down the left: the opinion when it is in the pair,
  # otherwise whichever comes first in reading order
  defp lead_title(c) do
    case Marginalia.Cases.default_lead(c) do
      nil -> c.name
      w -> w.title
    end
  end

  defp others_count(c), do: max(length(c.works) - 1, 0)

  defp lead_slug(c, link) do
    c |> ends(link) |> hd() |> Map.fetch!(:slug)
  end

  defp way(c, link) do
    [a, b] = ends(c, link)
    "#{role(a)} ↔ #{role(b)}"
  end

  defp ends(c, link) do
    by_id = Map.new(c.works, &{&1.id, &1})

    [by_id[link.a_work_id], by_id[link.b_work_id]]
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(&order_role(&1.collection_role))
  end

  defp order_role("opinion"), do: 0
  defp order_role("concurrence"), do: 1
  defp order_role("dissent"), do: 2
  defp order_role("argument"), do: 3
  defp order_role(_), do: 4

  defp count(link), do: link |> Links.edges() |> length()

  defp filtered?(q, kind, pair), do: q != "" or not is_nil(kind) or not is_nil(pair)

  defp counts(all, fun),
    do: all |> Enum.frequencies_by(fun) |> Enum.sort_by(fn {_k, n} -> -n end)

  defp pair_label(p) do
    p |> String.split("+") |> Enum.map_join(" ↔ ", &String.capitalize/1)
  end

  defp role(nil), do: "—"

  # A case has one opinion and any number of everything else: three
  # advocates all labelled "Oral argument" and two dissents both labelled
  # "Dissent" is not a label, it is a shrug. The document's own name after
  # the case name is what distinguishes them.
  defp role(w) do
    case String.split(w.title, " — ", parts: 2) do
      [_case, rest] -> rest
      [whole] -> whole
    end
  end

  defp commas(n) do
    n
    |> to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  defp short(nil), do: "—"

  defp short(w) do
    case w.collection_role do
      "opinion" -> "Op"
      "dissent" -> "Diss"
      "concurrence" -> "Conc"
      "argument" -> "Arg"
      _ -> "?"
    end
  end

  defp plain(q), do: Marginalia.Reading.plain(q)
end
