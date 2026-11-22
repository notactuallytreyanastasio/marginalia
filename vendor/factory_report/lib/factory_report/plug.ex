defmodule FactoryReport.Plug do
  @moduledoc """
  Serves the report: `GET /report` (or `GET /` of wherever it is mounted)
  answers 200 `application/json`; anything else answers 404.

  The listener `FactoryReport` starts uses this plug. To serve the report
  from your own endpoint instead, start the reporter with `port: false` and
  forward to the plug from a scope the public proxy does not route:

      forward "/internal/factory-report", FactoryReport.Plug

  ## Options

    * `:token` - overrides the token given to `FactoryReport`. When a token
      is in force the request must carry `authorization: Bearer <token>`,
      otherwise the answer is 401. `nil` or `""` here means no token.
  """

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{method: "GET", path_info: path} = conn, opts) when path in [[], ["report"]] do
    if authorized?(conn, token(opts)) do
      case report() do
        {:ok, body} ->
          conn
          |> put_resp_header("content-type", "application/json")
          |> put_resp_header("cache-control", "no-store")
          |> send_resp(200, body)

        :error ->
          text(conn, 503, "factory_report is not running")
      end
    else
      conn
      |> put_resp_header("www-authenticate", "Bearer")
      |> text(401, "unauthorized")
    end
    |> halt()
  end

  def call(conn, _opts), do: conn |> text(404, "not found") |> halt()

  defp report do
    if FactoryReport.meta(:app) do
      {:ok, Jason.encode_to_iodata!(FactoryReport.report())}
    else
      :error
    end
  end

  defp token(opts) do
    case Keyword.fetch(opts, :token) do
      {:ok, token} when is_binary(token) and token != "" -> token
      {:ok, _} -> nil
      :error -> FactoryReport.meta(:token)
    end
  end

  defp authorized?(_conn, nil), do: true

  defp authorized?(conn, token) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> given] -> Plug.Crypto.secure_compare(given, token)
      _ -> false
    end
  end

  defp text(conn, status, body) do
    conn
    |> put_resp_header("content-type", "text/plain; charset=utf-8")
    |> send_resp(status, body)
  end
end
