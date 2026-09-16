defmodule Marginalia.LLM do
  @moduledoc """
  The one model client. Everything that talks to a model goes through here.

  The blog this was extracted from hand-rolls `Req.post` against the same
  endpoint in three separate modules, each with its own error tuples and its
  own idea of what a failure is. That is the specific mistake this module
  exists to avoid.

  Callers may pass `:provider` to override the deploy default. Only admins can
  reach that path — see `Marginalia.Accounts.provider_for/1`; a normal user has
  no way to choose a backend and always gets the configured one.

  Two things it is opinionated about:

  * `finish_reason: "length"` is a **failure**, not a success. A truncated JSON
    body parses as garbage or, worse, as a plausible-but-short answer, and
    treating it as success is how silently-wrong analysis gets stored.
  * `{:error, :invalid_json}` is distinct from `{:error, :rate_limited}`, so a
    malformed reply is not retried three times as if it were congestion.
  """

  require Logger

  @max_attempts 3

  # High-effort reasoning over a long section is genuinely slow — measured at
  # well over a minute — and a timeout here throws away work that was going to
  # succeed.
  @default_timeout 300_000

  # DeepSeek speaks the OpenAI chat-completions dialect, but not identically:
  # different host, different model names, and it wants `max_tokens` where
  # OpenAI now wants `max_completion_tokens`. Provider is therefore config,
  # not a hardcoded URL, so switching back is one env var.
  # Model ids are the ones the providers' own /models endpoints return, checked
  # rather than guessed.
  #
  # `deepseek-chat` is NOT merely an alias for `deepseek-flash`: it selects the
  # same model with thinking OFF, while the bare id turns reasoning ON.
  #
  # We want it on, and high. The reading pass is the one that has to be right:
  # everything downstream — the graph, the chat — reasons over its output
  # rather than over the manuscript, so a cheap shallow read poisons all of it.
  #
  # The catch is that `max_tokens` covers reasoning *and* content, and DeepSeek
  # spends the reasoning first. A real section measured at ~10k reasoning
  # tokens against a caller asking for 1,400, so every call came back
  # `finish_reason: "length"`. `reasoning_headroom` is therefore added to
  # whatever the caller asks for: callers keep saying how much *answer* they
  # want, and thinking never eats it.
  @providers %{
    deepseek: %{
      label: "DeepSeek Flash",
      endpoint: "https://api.deepseek.com/chat/completions",
      key: :deepseek_api_key,
      model: "deepseek-flash",
      fast_model: "deepseek-flash",
      max_tokens_field: "max_tokens",
      default_body: %{"reasoning_effort" => "low"},
      reasoning_headroom: 24_000
    },
    openai: %{
      label: "Sol 5",
      endpoint: "https://api.openai.com/v1/chat/completions",
      key: :openai_api_key,
      model: "gpt-5.6-sol",
      fast_model: "gpt-5.4-nano",
      max_tokens_field: "max_completion_tokens",
      default_body: %{"reasoning_effort" => "low"},
      reasoning_headroom: 24_000
    }
  }

  @type result :: {:ok, map()} | {:error, term()}

  @doc """
  A single chat completion.

  Options: `:model`, `:messages`, `:tools`, `:temperature`,
  `:json` (force a JSON object reply), `:max_tokens`, `:timeout`.
  """
  @spec chat(keyword()) :: result()
  def chat(opts) do
    prov = resolve(opts[:provider])

    with {:ok, key} <- api_key(prov) do
      body =
        prov.default_body
        |> Map.merge(%{
          "model" => opts[:model] || model_for(prov),
          "messages" => Keyword.fetch!(opts, :messages)
        })
        |> put_effort(opts[:effort])
        |> maybe_put("tools", opts[:tools])
        |> maybe_put("tool_choice", opts[:tool_choice] || if(opts[:tools], do: "auto"))
        |> maybe_put("temperature", opts[:temperature])
        |> maybe_put(prov.max_tokens_field, budget(prov, opts[:max_tokens]))
        |> maybe_put("response_format", if(opts[:json], do: %{"type" => "json_object"}))

      request(body, prov, key, opts[:timeout] || @default_timeout, 1)
    end
  end

  @doc """
  A chat completion whose reply must be a JSON object, decoded for you.

  Returns `{:error, :invalid_json}` rather than a half-parsed map, so callers
  can decide between retrying and discarding.
  """
  @spec json(keyword()) :: result()
  def json(opts) do
    with {:ok, %{"content" => content}} <- chat(Keyword.put(opts, :json, true)) do
      case Jason.decode(content || "") do
        {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
        _ -> {:error, :invalid_json}
      end
    end
  end

  # DeepSeek prices a cached prefix token at a fraction of a fresh one, so
  # knowing the hit rate is the difference between guessing at the bill and
  # reading it. Logged at info, and emitted as telemetry for anything that
  # wants to add it up.
  defp report_usage(%{"usage" => usage}, prov) when is_map(usage) do
    hit = usage["prompt_cache_hit_tokens"] || 0
    miss = usage["prompt_cache_miss_tokens"] || 0
    prompt = usage["prompt_tokens"] || hit + miss
    completion = usage["completion_tokens"] || 0
    reasoning = get_in(usage, ["completion_tokens_details", "reasoning_tokens"]) || 0

    if prompt > 0 do
      Logger.info(
        "marginalia llm: prompt=#{prompt} cached=#{hit} (#{round(hit / prompt * 100)}%) " <>
          "completion=#{completion} reasoning=#{reasoning}"
      )
    end

    :telemetry.execute(
      [:marginalia, :llm, :usage],
      %{prompt: prompt, cached: hit, completion: completion, reasoning: reasoning},
      %{provider: prov.label}
    )

    :ok
  end

  defp report_usage(_body, _prov), do: :ok

  @doc """
  One forced call to one tool, returning its arguments.

  Structure asked for in prose is structure the model may or may not give
  you; a tool schema is checked by the provider before the reply comes back.
  Use this instead of `json/1` wherever the shape matters more than the
  prose — a missing field here is a bug in the schema, not a parse failure at
  three in the morning.
  """
  @spec call_tool(keyword()) :: {:ok, map()} | {:error, term()}
  def call_tool(opts) do
    tool = Keyword.fetch!(opts, :tool)
    name = tool["function"]["name"]

    # DeepSeek refuses a forced tool_choice while reasoning is on
    # ("Thinking mode does not support this tool_choice"), so the choice is
    # forced only when thinking is off. With one tool on the table and a
    # prompt that asks for it, "auto" gets called anyway — and `:no_tool_call`
    # below is the honest failure if it does not.
    choice =
      if opts[:effort] in [:none, "none"] do
        %{"type" => "function", "function" => %{"name" => name}}
      else
        "auto"
      end

    opts =
      opts
      |> Keyword.drop([:tool])
      |> Keyword.put(:tools, [tool])
      |> Keyword.put(:tool_choice, choice)

    case chat(opts) do
      {:ok, %{"tool_calls" => [%{"function" => %{"arguments" => args}} | _]}} ->
        case Jason.decode(args || "{}") do
          {:ok, m} when is_map(m) -> {:ok, m}
          _ -> {:error, :invalid_json}
        end

      {:ok, _no_call} ->
        {:error, :no_tool_call}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp request(body, prov, key, timeout, attempt) do
    case Req.post(prov.endpoint,
           headers: [{"authorization", "Bearer #{key}"}],
           json: body,
           receive_timeout: timeout
         ) do
      {:ok, %{status: 200, body: %{"choices" => [choice | _]} = resp}} ->
        report_usage(resp, prov)
        interpret(choice, body, prov, key, timeout, attempt)

      {:ok, %{status: status}} when status in [429, 500, 502, 503, 504] ->
        retry_or_fail({:error, :rate_limited}, body, prov, key, timeout, attempt)

      {:ok, %{status: status, body: resp}} ->
        {:error, {:http, status, inspect(resp) |> String.slice(0, 300)}}

      {:error, reason} ->
        retry_or_fail({:error, {:transport, inspect(reason)}}, body, prov, key, timeout, attempt)
    end
  end

  # A truncated completion is a failure. Retrying it unchanged would truncate
  # again, so this one does not retry — the caller has to ask for less.
  defp interpret(%{"finish_reason" => "length"}, _body, _prov, _key, _timeout, _attempt),
    do: {:error, :truncated}

  defp interpret(%{"message" => message}, _body, _prov, _key, _timeout, _attempt),
    do: {:ok, message}

  defp interpret(other, _body, _prov, _key, _timeout, _attempt),
    do: {:error, {:unexpected, inspect(other) |> String.slice(0, 200)}}

  defp retry_or_fail(error, _body, _prov, _key, _timeout, attempt) when attempt >= @max_attempts,
    do: error

  defp retry_or_fail(_error, body, prov, key, timeout, attempt) do
    # jittered backoff: 0.5s, 1.5s, with noise so concurrent section reads
    # don't all come back at the same instant
    sleep = trunc(:math.pow(2, attempt) * 250) + :rand.uniform(400)
    Process.sleep(sleep)
    request(body, prov, key, timeout, attempt + 1)
  end

  # Reasoning tokens are billed as output and are never cached, so effort is
  # the one dial that changes the bill more than anything else. It is set per
  # call rather than per deploy: the passes that reason over the whole draft
  # earn it, and the per-section pass — which runs once per section and is
  # therefore most of the calls — does not.
  defp put_effort(body, nil), do: body
  defp put_effort(body, effort) when effort in [:low, :high, :none, "low", "high", "none"],
    do: Map.put(body, "reasoning_effort", to_string(effort))

  defp put_effort(body, _other), do: body

  defp maybe_put(map, _k, nil), do: map
  defp maybe_put(map, k, v), do: Map.put(map, k, v)

  # The caller's number is how much answer it wants; the headroom is what the
  # model needs to think first. Keeping them separate is what lets `:truncated`
  # still mean "the answer was cut off" rather than "it thought too hard".
  defp budget(_prov, nil), do: nil
  defp budget(prov, asked), do: asked + Map.get(prov, :reasoning_headroom, 0)

  @doc "Which provider is active: :deepseek or :openai."
  def provider_name do
    case Application.get_env(:marginalia, :llm_provider, "deepseek") do
      "openai" -> :openai
      :openai -> :openai
      _ -> :deepseek
    end
  end

  defp provider, do: Map.fetch!(@providers, provider_name())

  @doc "Provider names this deploy knows how to talk to."
  def available, do: Map.keys(@providers)

  @doc """
  The backends offered in the switcher: `{name, label, model}`, each with a key
  configured. A provider with no key is left out rather than offered and then
  failing on the first call.
  """
  def choices do
    @providers
    |> Enum.filter(fn {_name, prov} -> match?({:ok, _}, api_key(prov)) end)
    |> Enum.map(fn {name, prov} -> %{name: name, label: prov.label, model: prov.model} end)
    |> Enum.sort_by(& &1.label)
  end

  @doc """
  The default effort for a provider. Individual calls override it with
  `:effort` — see `Marginalia.Analysis` for which passes ask for more.
  """
  def reasoning_effort(provider \\ nil), do: resolve(provider).default_body["reasoning_effort"]

  @doc "Tokens reserved for reasoning, on top of whatever the caller asked for."
  def reasoning_headroom(provider \\ nil), do: Map.get(resolve(provider), :reasoning_headroom, 0)

  @doc "The max_tokens actually sent for a caller asking for `asked`."
  def token_budget(provider, asked), do: budget(resolve(provider), asked)

  @doc "The human name for a provider, for anything a person reads."
  def label(provider \\ nil), do: resolve(provider).label

  # An unknown or nil override falls back to the deploy default rather than
  # erroring, so a stale value on a user row can never wedge their account.
  defp resolve(nil), do: provider()
  defp resolve(name) when is_binary(name), do: resolve(safe_atom(name))
  defp resolve(name) when is_atom(name), do: Map.get(@providers, name, provider())

  defp safe_atom("openai"), do: :openai
  defp safe_atom("deepseek"), do: :deepseek
  defp safe_atom(_), do: nil

  @doc "The model used for the big reasoning calls (spine, chat)."
  def default_model(provider \\ nil),
    do: Application.get_env(:marginalia, :llm_model) || resolve(provider).model

  @doc "The cheap model used for the per-section passes, of which there are many."
  def fast_model(provider \\ nil),
    do: Application.get_env(:marginalia, :llm_fast_model) || resolve(provider).fast_model

  defp model_for(prov), do: Application.get_env(:marginalia, :llm_model) || prov.model

  @doc "Whether a key is configured for the given (or default) provider."
  def configured?(provider \\ nil), do: match?({:ok, _}, api_key(resolve(provider)))

  defp api_key(prov) do
    case Application.get_env(:marginalia, prov.key) do
      key when is_binary(key) and key != "" -> {:ok, key}
      _ -> {:error, :no_api_key}
    end
  end
end
