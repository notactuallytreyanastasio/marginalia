defmodule MarginaliaWeb.PlayLive do
  @moduledoc """
  Loose Leaf: a marble, a tilting sheet of squared paper, a ring to reach.

  The server's whole part in this is to deliver the stage. The game runs in
  the browser, under `assets/js/game`, and is split the way the rest of that
  directory explains: a core of pure functions (physics, rules, levels, the
  scene to draw) and a shell around it that owns the canvas, the clock and the
  player's thumb. The `LooseLeafGame` hook is that shell's entry point.

  Everything inside the stage is `phx-update="ignore"`: the hook writes the
  HUD many times a second, and a patch from here would only undo it. The
  markup below is therefore the *initial* state — what a visitor sees before
  the script arrives, or if WebGL never does.
  """
  use MarginaliaWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Loose Leaf",
       page_description:
         "Tilt the page, roll the marble to the ring. A small 3D game for a thumb and a phone."
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="loose-leaf"
      class="ll-stage"
      phx-hook="LooseLeafGame"
      phx-update="ignore"
      data-phase="title"
    >
      <canvas id="loose-leaf-canvas" class="ll-canvas" data-ll="canvas"></canvas>

      <header id="loose-leaf-hud" class="ll-hud">
        <.link
          id="loose-leaf-exit"
          href={~p"/"}
          class="ll-chip ll-exit"
          aria-label="Back to Marginalia"
        >
          <.icon name="hero-arrow-left" class="size-4" />
        </.link>
        <span class="ll-chip ll-level" data-ll="level">1 · First Page</span>
        <span class="ll-chip ll-gems">
          <span class="ll-gem" aria-hidden="true"></span>
          <span data-ll="gems">0/0</span>
        </span>
        <span class="ll-chip ll-time" data-ll="time">60.0</span>
        <button
          id="loose-leaf-mute"
          type="button"
          class="ll-chip ll-mute"
          data-ll="mute"
          aria-label="Mute sound"
          aria-pressed="false"
        >
          <.icon name="hero-speaker-wave" class="size-4 ll-on" />
          <.icon name="hero-speaker-x-mark" class="size-4 ll-off" />
        </button>
      </header>

      <p id="loose-leaf-banner" class="ll-banner" data-ll="banner" aria-live="polite"></p>

      <section id="loose-leaf-card" class="ll-card">
        <h1 data-ll="card-title">Loose Leaf</h1>
        <p data-ll="card-body">
          Roll the marble to the ring before the clock runs out. Drag anywhere to tilt the page.
        </p>
        <button id="loose-leaf-action" type="button" class="ll-button" data-ll="action">
          Play
        </button>
      </section>

      <p id="loose-leaf-unsupported" class="ll-card ll-unsupported">
        This needs WebGL, and this browser will not give it one.
      </p>

      <div class="ll-stick" data-ll="stick" aria-hidden="true"><span></span></div>
    </div>
    """
  end
end
