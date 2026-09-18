defmodule MarginaliaWeb.LinkWaiting do
  @moduledoc """
  What a linked pair shows while it is being worked out.

  The pass is a single model call, so there is no honest progress bar to
  draw — but there is something real to show: both maps exist already, and
  the question being asked is which of their nodes point at each other. So
  the wait shows the two sets of nodes and arcs being tried between them,
  with the titles of the pair currently under consideration.

  The nodes are real and the counts are real. **The arcs are not findings**
  and the copy says so: they are drawn at random to show the shape of the
  work, and every one of them fades. A drawn arc that looked like a result
  and then vanished when the real answer came back would be the worst kind
  of loading state — it would teach the reader to distrust the ones that
  stay.
  """
  use MarginaliaWeb, :html

  attr :a, :map, required: true
  attr :b, :map, required: true
  attr :a_nodes, :list, default: []
  attr :b_nodes, :list, default: []
  attr :status, :string, default: "linking"
  attr :error, :string, default: nil

  def waiting(assigns) do
    assigns =
      assign(assigns,
        pairs: length(assigns.a_nodes) * length(assigns.b_nodes),
        a_dots: sample(assigns.a_nodes),
        b_dots: sample(assigns.b_nodes)
      )

    ~H"""
    <div class="lw">
      <%= if @status == "failed" do %>
        <h2>That did not go through</h2>
        <p class="why">{@error}</p>
        <button class="mg-btn sm" phx-click="relink">Try again</button>
      <% else %>
        <div class="lw-head">
          <span class="mg-label">relating</span>
          <h2>{@a.title} <span class="x">↔</span> {@b.title}</h2>
          <p class="why">
            Reading both maps against each other — {length(@a_nodes)} nodes on one side, {length(
              @b_nodes
            )} on the other, {@pairs} possible pairs. A minute or two.
            This page fills in on its own.
          </p>
        </div>

        <div
          class="lw-stage"
          id="wiring"
          phx-hook=".Wiring"
          data-a={Jason.encode!(@a_dots)}
          data-b={Jason.encode!(@b_dots)}
        >
          <%!-- The nodes are rendered here rather than by the hook: the
                hook cannot run until the socket connects, and an empty box
                for six seconds is a worse loading state than the one it
                replaced. --%>
          <svg class="lw-svg" viewBox="0 0 680 360" preserveAspectRatio="xMidYMid meet">
            <g class="arcs"></g>
            <g class="dots">
              <circle
                :for={{_t, i} <- Enum.with_index(@a_dots)}
                cx="90"
                cy={y(i, length(@a_dots))}
                r="3.5"
                data-side="a"
                data-i={i}
                style={"animation-delay:#{i * 45}ms"}
              />
              <circle
                :for={{_t, i} <- Enum.with_index(@b_dots)}
                cx="590"
                cy={y(i, length(@b_dots))}
                r="3.5"
                data-side="b"
                data-i={i}
                style={"animation-delay:#{i * 45}ms"}
              />
            </g>
          </svg>

          <p class="lw-now">
            <span class="l"></span>
            <span class="arrow" aria-hidden="true">⇢</span>
            <span class="r"></span>
          </p>

          <p class="lw-fine">
            The nodes are yours. The lines are the pass trying pairs — none of them are
            findings yet, and they all fade. What it actually decides arrives at the end.
          </p>
        </div>
      <% end %>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".Wiring">
        // Two columns of real nodes, and arcs tried between them. Nothing
        // here is a result — see the note under it — it is the shape of the
        // work, drawn while the work happens.
        export default {
          mounted() {
            this.a = JSON.parse(this.el.dataset.a || "[]");
            this.b = JSON.parse(this.el.dataset.b || "[]");
            this.svg = this.el.querySelector(".lw-svg");
            this.arcs = this.svg.querySelector(".arcs");
            this.dots = this.svg.querySelector(".dots");
            this.now = {l: this.el.querySelector(".lw-now .l"), r: this.el.querySelector(".lw-now .r")};

            if (!this.a.length || !this.b.length) return;
            // the dots are already on the page; motion is all this adds
            if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

            this.tick = setInterval(() => this.tryPair(), 900);
            this.tryPair();
          },

          destroyed() { clearInterval(this.tick); },

          // mirrors y/2 in the component — the dots are placed server-side
          // and the arcs have to arrive at the same coordinates
          y(i, n) { return 30 + (i * (300 / Math.max(n - 1, 1))); },

          tryPair() {
            const ns = "http://www.w3.org/2000/svg";
            const i = Math.floor(Math.random() * this.a.length);
            const j = Math.floor(Math.random() * this.b.length);
            const y1 = this.y(i, this.a.length);
            const y2 = this.y(j, this.b.length);

            const path = document.createElementNS(ns, "path");
            path.setAttribute("d", `M 90 ${y1} C 300 ${y1}, 380 ${y2}, 590 ${y2}`);
            path.setAttribute("class", "arc");
            this.arcs.appendChild(path);

            // draw it on, hold, fade it out — then take it away entirely, so
            // nothing accumulates that could be mistaken for a result
            const len = path.getTotalLength();
            path.style.strokeDasharray = len;
            path.style.strokeDashoffset = len;
            path.getBoundingClientRect();
            path.style.transition = "stroke-dashoffset .7s ease-out, opacity .5s ease-in .9s";
            path.style.strokeDashoffset = 0;
            path.style.opacity = 0;
            setTimeout(() => path.remove(), 1800);

            this.lightUp("a", i);
            this.lightUp("b", j);
            this.now.l.textContent = this.a[i];
            this.now.r.textContent = this.b[j];
          },

          lightUp(side, i) {
            const dot = this.dots.querySelector(`circle[data-side="${side}"][data-i="${i}"]`);
            if (!dot) return;
            dot.classList.add("lit");
            setTimeout(() => dot.classList.remove("lit"), 1200);
          },
        };
      </script>
    </div>
    """
  end

  @doc false
  # mirrored by y() in the hook, which has to put the arcs on the same dots
  def y(i, n), do: 30 + i * (300 / max(n - 1, 1))

  # Enough dots to read as a map of the draft, few enough to stay legible.
  # Evenly spaced rather than the first N, so the shape is of the whole
  # document and not just its opening.
  @dots 24

  defp sample(nodes) do
    titles = Enum.map(nodes, & &1.title)
    n = length(titles)

    if n <= @dots do
      titles
    else
      step = n / @dots
      Enum.map(0..(@dots - 1), fn i -> Enum.at(titles, trunc(i * step)) end)
    end
  end
end
