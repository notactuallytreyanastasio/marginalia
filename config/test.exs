import Config

config :marginalia, Marginalia.Mailer, adapter: Swoosh.Adapters.Test


# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :marginalia, Marginalia.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "marginalia_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :marginalia, MarginaliaWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "AKqvFbo2lMp617G1LI7gGx+lBln2iNO1/tQA6l7T8ESehaFGPbp7MiZKs6oH5M+S",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# No key, and nowhere to send it. config/runtime.exs skips the keys in
# test, and this makes the suite hermetic even if something sets one:
# 127.0.0.1:1 refuses instantly rather than reaching the internet.
config :marginalia, :deepseek_api_key, nil
config :marginalia, :openai_api_key, nil

config :marginalia, :llm_endpoints, %{
  deepseek_api_key: "http://127.0.0.1:1/chat/completions",
  openai_api_key: "http://127.0.0.1:1/v1/chat/completions"
}

# No backing off from a port that is closed on purpose: the retries took
# seconds each and outlived the test that started them.
config :marginalia, :llm_backoff_ms, 0
