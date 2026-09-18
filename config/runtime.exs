import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/marginalia start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :marginalia, MarginaliaWeb.Endpoint, server: true
end

config :marginalia, MarginaliaWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :marginalia, MarginaliaWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        # Gettext translations
        ~r"priv/gettext/.*\.po$"E,
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/marginalia_web/router\.ex$"E,
        ~r"lib/marginalia_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

# The model provider powers both the manuscript analysis passes and the
# editorial chat. DeepSeek by default for this first version; set
# LLM_PROVIDER=openai to switch. Read in every environment so dev can talk to
# the real API with a local .env.
config :marginalia, :llm_provider, System.get_env("LLM_PROVIDER", "deepseek")

# Only this account may switch backends. Admin is about the app; this is about
# who pays for the tokens, so it is its own setting rather than a second
# meaning bolted onto is_admin.
config :marginalia, :owner_email, System.get_env("OWNER_EMAIL", "bobbbygrayson@gmail.com")

# Never in test. This file runs in every environment and runs *after*
# config/test.exs, so a developer with DEEPSEEK_API_KEY exported had a
# test suite that would read a draft against the real paid API — slowly,
# flakily, and on their card. Tests get no key at all, and the endpoint
# they would call is a dead address anyway; see config/test.exs.
if config_env() != :test do
  config :marginalia, :deepseek_api_key, System.get_env("DEEPSEEK_API_KEY")
  config :marginalia, :openai_api_key, System.get_env("OPENAI_API_KEY")
end
# Optional overrides; each provider has a sensible default model.
config :marginalia, :llm_model, System.get_env("LLM_MODEL")
config :marginalia, :llm_fast_model, System.get_env("LLM_FAST_MODEL")

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :marginalia, Marginalia.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :marginalia, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :marginalia, MarginaliaWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :marginalia, MarginaliaWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :marginalia, MarginaliaWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
