defmodule MarginaliaWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use MarginaliaWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @tagline "Someone who has actually read the whole thing"
  # "It never writes a word of your book" stood here until rewrites shipped.
  # A description that contradicts the product is worse than a duller one.
  @og_alt "Marginalia, a reader for drafts. A note in the margin reads: your opening promises a book about grief, chapter nine is the best thing here, and it belongs to a different one."
  @pitch "Upload a draft. It reads end to end, maps what's on the page, and argues with you in the margin — a thread on any paragraph, anchored to your own sentences."

  attr :page_title, :string, default: nil
  attr :page_description, :string, default: nil
  attr :page_robots, :string, default: nil
  attr :page_image, :string, default: nil
  attr :page_image_alt, :string, default: nil
  attr :page_url, :string, default: nil

  @doc """
  The title, the description, and what a link to this looks like pasted
  somewhere else.

  Both layouts call this rather than carrying their own copy: the two heads
  were already identical and had drifted apart once, which is how the app
  shipped for a while telling the world it was a Phoenix Framework site.

  The card image is the product's own arrangement — a line of the draft, a
  dotted leader, a note in the margin that argues with it — because the thing
  being sold is the reading, and a screenshot of a chat window sells a chat
  window. Its source is `priv/og/og.html`, rendered to
  `priv/static/images/og.png` at 2400x1260 (the 1.91:1 every card wants, at
  2x so it stays sharp).

  A page that is its own thing can say so: `page_image` and `page_url`
  override the site card and the canonical link. The url mattered more than
  it looks — every page was declaring `og:url` as the site root, so a link
  to any particular case unfurled as a link to the front door and, worse,
  told the scrapers they were the same page.
  """
  def head_meta(assigns) do
    assigns =
      assign(assigns,
        tagline: @tagline,
        title: assigns.page_title || @tagline,
        description: assigns.page_description || @pitch,
        image: absolute(assigns.page_image || ~p"/images/og.png"),
        image_alt: assigns.page_image_alt || @og_alt,
        canonical: absolute(assigns.page_url || ~p"/")
      )

    ~H"""
    <.live_title default={@tagline} suffix=" · Marginalia" phx-no-format>{@page_title}</.live_title>

    <meta :if={@page_robots} name="robots" content={@page_robots} />
    <meta name="description" content={@description} />
    <meta property="og:type" content="website" />
    <meta property="og:site_name" content="Marginalia" />
    <meta property="og:title" content={@title} />
    <meta property="og:description" content={@description} />
    <meta property="og:url" content={@canonical} />
    <link rel="canonical" href={@canonical} />
    <meta property="og:image" content={@image} />
    <meta property="og:image:width" content="2400" />
    <meta property="og:image:height" content="1260" />
    <meta property="og:image:alt" content={@image_alt} />
    <meta name="twitter:card" content="summary_large_image" />
    <meta name="twitter:title" content={@title} />
    <meta name="twitter:description" content={@description} />
    <meta name="twitter:image" content={@image} />
    <meta name="theme-color" content="#fbfaf7" />
    """
  end

  # `url/1` is a macro over a verified route and cannot take a path worked
  # out at runtime, which is what a per-page card image or canonical link
  # is. Already-absolute values pass through, so a page can point its card
  # at something hosted elsewhere.
  defp absolute("http" <> _ = url), do: url
  defp absolute(path), do: MarginaliaWeb.Endpoint.url() <> path

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :bleed, :boolean,
    default: false,
    doc: "drop the page padding — for views that manage their own full-height layout"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="mg-bar">
      <a href="/" class="mg-brand">Marginalia <span>a reader for drafts</span></a>
      <nav>
        <%!-- Cases is outside the branches: the collections are published
              deliberately and are readable by anyone, so hiding the way to
              them behind a login was hiding the only public thing here. --%>
        <.link navigate={~p"/cases"}>Cases</.link>

        <%!-- The scope exists for a signed-out visitor too, with no user
              in it. Testing the scope alone read as "logged in" and then
              dereferenced nil — which nothing hit only because every page
              using this layout minted a guest on arrival. --%>
        <%= cond do %>
          <% @current_scope && @current_scope.user && @current_scope.user.is_guest -> %>
            <.link navigate={~p"/works"}>Drafts</.link>
            <.link navigate={~p"/works/new"}>New draft</.link>
            <span class="text-[var(--mg-dim)] opacity-70">guest</span>
            <.link navigate={~p"/users/register"} class="mg-btn sm">Keep my drafts</.link>
          <% @current_scope && @current_scope.user -> %>
            <.link navigate={~p"/works"}>Drafts</.link>
            <%!-- a link belongs to two drafts and shows under both, so it
                  needs a place of its own to be listed --%>
            <.link navigate={~p"/links"}>Linked</.link>
            <.link navigate={~p"/cuts"}>Cuts</.link>
            <.link navigate={~p"/stacks"}>Methods</.link>
            <.link navigate={~p"/works/new"}>New draft</.link>
            <.link navigate={~p"/users/settings"}>{@current_scope.user.email}</.link>
            <.link href={~p"/users/log-out"} method="delete">Log out</.link>
          <% true -> %>
            <.link navigate={~p"/users/log-in"}>Log in</.link>
        <% end %>
      </nav>
    </header>

    <!--
      The generated layout pinned every page inside max-w-2xl, which is right
      for a settings form and wrong for a manuscript beside a chat panel: the
      work page was being squeezed into 640px and wrapping one word per line.
      Pages set their own width now; this only supplies the gutters.
    -->
    <main class={if @bleed, do: "", else: "px-4 py-8 sm:px-6 lg:px-8"}>
      <div class="space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
