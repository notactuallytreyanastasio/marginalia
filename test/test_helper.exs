# Tests tagged :network reach the real GitHub API. They are the only way to
# know things like "an empty Authorization header is a 401, and no header is
# a 200", which is a fact about GitHub and not about this code — but they are
# also rate limited, and `deploy.sh` runs the suite before every deploy. So
# they are opt-in: `mix test --include network`.
ExUnit.start(exclude: [:network])
Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, :manual)
