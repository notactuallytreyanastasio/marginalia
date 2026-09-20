defmodule MarginaliaWeb.Router do
  use MarginaliaWeb, :router

  import MarginaliaWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MarginaliaWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  # The landing page is a full-bleed sheet with its own header, so it uses a
  # root layout without the scaffold's auth menu.
  pipeline :bare_browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MarginaliaWeb.Layouts, :bare}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Other scopes may use custom stacks.
  # scope "/api", MarginaliaWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:marginalia, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: MarginaliaWeb.Telemetry
    end
  end

  scope "/", MarginaliaWeb do
    pipe_through [:bare_browser]

    live_session :landing,
      on_mount: [{MarginaliaWeb.UserAuth, :mount_current_scope}] do
      live "/", LandingLive, :index
    end
  end

  # The cases are the public face of this and they are read-only, so they
  # get no guest account. Minting one on arrival meant every crawler and
  # every `curl` became a row in `users` — 762 of them to serve five
  # people who actually uploaded anything. The one thing these pages
  # remembered about a visitor was whether they had seen the tour, and
  # that is a fact about a browser, so it lives in one now.
  scope "/", MarginaliaWeb do
    pipe_through :browser

    live_session :cases,
      on_mount: [{MarginaliaWeb.UserAuth, :mount_current_scope}] do
      live "/cases", CaseLive.Index, :index
      live "/cases/:slug", CaseLive.Show, :show
      live "/cases/:slug/read", CaseLive.Read, :read
      live "/cases/:slug/read/:lead", CaseLive.Read, :read

      # A published stack, read by anybody. Addressed by slug, and served
      # only when the folder carries a published_at — the private pages at
      # /stacks stay owner-scoped and keep the buttons that spend money.
      live "/reading", ReadingLive.Index, :index
      live "/reading/:slug", ReadingLive.Story, :story
      live "/reading/:slug/:ordinal", ReadingLive.Step, :step
    end
  end

  ## Authentication routes

  # Reading a draft does not require an account. A visitor gets a guest user
  # created for them on the way in, so everything downstream stays scoped by
  # owner and no guest can reach another guest's work.
  scope "/", MarginaliaWeb do
    pipe_through [:browser, :ensure_user_or_guest]

    # Where the upload form lands when no live socket is driving it. The
    # form is `method="post"` with no JavaScript of its own, so a browser
    # whose websocket died submits it here; without this route Phoenix
    # raised NoRouteError and the writer got a 404 with their text gone.
    post "/works/new", WorkController, :create

    get "/works/:id/graph.json", GraphController, :json
    get "/works/:id/graph.dot", GraphController, :dot
    get "/works/:id/trace.json", GraphController, :trace

    live_session :allow_guest,
      on_mount: [{MarginaliaWeb.UserAuth, :allow_guest}] do
      live "/works", WorkLive.Index, :index
      live "/works/new", WorkLive.New, :new
      live "/works/:id", WorkLive.Show, :show
      live "/stacks", StackLive.Index, :index
      # `new` before `:id`, or the import page resolves as a folder called
      # "new" and redirects away. The router takes the first match, not the
      # most specific one.
      live "/stacks/new", StackLive.New, :new
      live "/stacks/:id", StackLive.Show, :show
      live "/stacks/:id/story", StackLive.Story, :story
      live "/stacks/:id/:ordinal", StackLive.Show, :step
      live "/cuts", CutLive.Index, :index
      live "/cuts/:id", CutLive.Show, :show
      live "/links", LinkLive.Index, :index
      # the split view is gone; /read stays an alias so links already sent
      # to people keep working
      live "/links/:id", LinkLive.Read, :show
      live "/links/:id/read", LinkLive.Read, :read
    end
  end

  # Account settings still need a real, logged-in account.
  scope "/", MarginaliaWeb do
    pipe_through [:browser, :require_real_account]

    live_session :require_authenticated_user,
      on_mount: [{MarginaliaWeb.UserAuth, :require_real_account}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", MarginaliaWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{MarginaliaWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
