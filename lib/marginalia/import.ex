defmodule Marginalia.Import do
  @moduledoc """
  Reading a draft off the web.

  Paste and file upload cover the case where the writer has the text. A lot
  of what people want to relate is published — an essay they are answering,
  the post that started the argument — and retyping it is not a thing anyone
  will do. This fetches the page and turns it into the markdown the rest of
  the product works on.

  ## What it keeps

  Headings, paragraphs, lists, blockquotes, links, emphasis and code. The
  headings matter more than they look: the segmenter cuts a draft into
  sections on `#`–`###`, so losing them would turn a structured essay into
  one undifferentiated block and every downstream pass would be worse.

  Everything else goes. Navigation, footers, share buttons and cookie
  banners are not the article, and a beat anchored to "Subscribe to our
  newsletter" is a beat that makes the whole map look stupid.

  ## The fetch is the dangerous part

  The URL comes from whoever is using the site, and the server is the one
  that makes the request — from inside the network, with whatever the
  network trusts. So this refuses anything that is not plain http(s) to a
  public host: no `file:`, no `localhost`, no link-local address, no
  private range, and no redirect that lands on one either. That check is
  the reason this module is worth reading before it is worth extending.
  """

  require Logger

  @max_bytes 4_000_000
  @timeout 20_000

  # the block elements worth keeping, and what each becomes
  @keep ~w(h1 h2 h3 h4 h5 h6 p ul ol blockquote pre)

  # wrappers that are never the article
  @strip ~w(script style nav header footer aside form noscript svg iframe button
            figure figcaption template)

  @doc """
  Fetch `url` and return `{:ok, %{title: _, markdown: _, url: _}}`.

  `{:error, reason}` covers a refused address, a bad response, and a page
  with too little prose in it to be a draft.
  """
  def fetch(url, opts \\ []) do
    with {:ok, uri} <- allowed(url),
         {:ok, html} <- get(uri, opts),
         {:ok, doc} <- parse(html) do
      title = title(doc)
      # the title becomes the draft's one h1, so the article's own copy of
      # it would be a second heading saying the same thing
      markdown = doc |> article() |> to_markdown() |> drop_leading_title(title)

      cond do
        String.length(markdown) < 400 ->
          {:error, :too_little_text}

        true ->
          {:ok, %{title: title, markdown: heading(title) <> markdown, url: URI.to_string(uri)}}
      end
    end
  end

  # --------------------------------------------------------------- the guard

  @doc """
  Whether this address may be fetched at all.

  Public by design: it is the security boundary of this module, and a
  boundary with no test on it is a wish.
  """
  def allowed(url) when is_binary(url) do
    uri = URI.parse(String.trim(url))

    cond do
      uri.scheme not in ["http", "https"] -> {:error, :bad_scheme}
      is_nil(uri.host) or uri.host == "" -> {:error, :no_host}
      private?(uri.host) -> {:error, :private_address}
      true -> {:ok, uri}
    end
  end

  def allowed(_), do: {:error, :bad_url}

  defp private?(host) do
    host = String.downcase(host) |> String.trim_trailing(".")

    cond do
      host in ["localhost", "0.0.0.0", "broadcasthost"] -> true
      String.ends_with?(host, [".localhost", ".local", ".internal"]) -> true
      # an address literal we can judge directly
      match?({:ok, _}, :inet.parse_address(to_charlist(host))) -> private_ip?(host)
      # a name: resolve it, because "evil.example.com" can point at 127.0.0.1
      true -> resolves_private?(host)
    end
  end

  defp private_ip?(host) do
    case :inet.parse_address(to_charlist(host)) do
      {:ok, addr} -> reserved?(addr)
      _ -> true
    end
  end

  defp resolves_private?(host) do
    case :inet.getaddrs(to_charlist(host), :inet) do
      {:ok, addrs} -> Enum.any?(addrs, &reserved?/1)
      # a name that will not resolve is not worth trying anyway
      _ -> true
    end
  end

  defp reserved?({127, _, _, _}), do: true
  defp reserved?({10, _, _, _}), do: true
  defp reserved?({192, 168, _, _}), do: true
  defp reserved?({169, 254, _, _}), do: true
  defp reserved?({172, b, _, _}) when b >= 16 and b <= 31, do: true
  defp reserved?({0, _, _, _}), do: true
  defp reserved?({100, b, _, _}) when b >= 64 and b <= 127, do: true
  defp reserved?({a, _, _, _}) when a >= 224, do: true
  defp reserved?({_, _, _, _}), do: false
  # IPv6: loopback, link-local and unique-local
  defp reserved?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp reserved?({a, _, _, _, _, _, _, _}) when a >= 0xFC00 and a <= 0xFDFF, do: true
  defp reserved?({a, _, _, _, _, _, _, _}) when a >= 0xFE80 and a <= 0xFEBF, do: true
  defp reserved?({_, _, _, _, _, _, _, _}), do: false
  defp reserved?(_), do: true

  # --------------------------------------------------------------- the fetch

  defp get(uri, opts) do
    case Keyword.get(opts, :body) do
      # tests hand the HTML straight in rather than standing up a server
      body when is_binary(body) ->
        {:ok, body}

      nil ->
        request(uri)
    end
  end

  defp request(uri) do
    Req.get(URI.to_string(uri),
      receive_timeout: @timeout,
      max_redirects: 3,
      redirect_log_level: false,
      max_retries: 1,
      headers: [
        {"user-agent", "Marginalia/1.0 (+https://marginalia.bobbby.online)"},
        {"accept", "text/html,application/xhtml+xml"}
      ]
    )
    |> case do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        if byte_size(body) > @max_bytes, do: {:error, :too_big}, else: {:ok, body}

      {:ok, %{status: status}} ->
        {:error, {:http, status}}

      {:error, reason} ->
        Logger.warning("marginalia: fetch failed for #{uri.host}: #{inspect(reason)}")
        {:error, :unreachable}
    end
  end

  defp parse(html) do
    case Floki.parse_document(html) do
      {:ok, doc} -> {:ok, doc}
      _ -> {:error, :unparseable}
    end
  end

  # ------------------------------------------------------------ the article

  # The article's own h1 first: og:title and <title> carry the site's name
  # and the author's, and "Dario Amodei — We Must Pace the Frontier" is a
  # worse draft title than "We Must Pace the Frontier".
  defp title(doc) do
    [
      doc |> Floki.find("article h1") |> Enum.take(1) |> Floki.text(sep: " ") |> List.wrap(),
      doc |> Floki.find("h1") |> Enum.take(1) |> Floki.text(sep: " ") |> List.wrap(),
      Floki.attribute(doc, "meta[property='og:title']", "content"),
      doc |> Floki.find("title") |> Floki.text() |> List.wrap()
    ]
    |> Enum.flat_map(& &1)
    |> Enum.map(&clean/1)
    |> Enum.find("Untitled", &(&1 != ""))
    |> String.slice(0, 200)
  end

  # The body of the piece: whichever candidate container holds the most
  # prose. Picking `<article>` outright is wrong often enough — plenty of
  # sites wrap comments or a "related posts" list in one too.
  defp article(doc) do
    doc = Floki.filter_out(doc, Enum.join(@strip, ", "))

    ["article", "main", "[role=main]", ".post", ".entry-content", "body"]
    |> Enum.flat_map(&Floki.find(doc, &1))
    |> Enum.map(&{&1, &1 |> Floki.text() |> String.length()})
    |> Enum.max_by(fn {_node, len} -> len end, fn -> {doc, 0} end)
    |> elem(0)
  end

  defp to_markdown(node) do
    node
    |> blocks()
    |> Enum.map(&block/1)
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n\n")
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> Kernel.<>("\n")
  end

  # Block elements in document order, without descending into one we have
  # already taken — otherwise a <p> inside a <blockquote> arrives twice.
  defp blocks(node) do
    node
    |> Floki.children()
    |> Enum.flat_map(fn
      {tag, _attrs, _children} = el when is_binary(tag) ->
        if tag in @keep, do: [el], else: blocks(el)

      _ ->
        []
    end)
  end

  defp block({tag, _, _} = el) when tag in ~w(h1 h2 h3 h4 h5 h6) do
    level = tag |> String.last() |> String.to_integer()
    text = inline(el)
    if text == "", do: nil, else: String.duplicate("#", level) <> " " <> text
  end

  defp block({"p", _, _} = el), do: presence(inline(el))

  defp block({"blockquote", _, _} = el) do
    case presence(inline(el)) do
      nil -> nil
      text -> text |> String.split("\n") |> Enum.map_join("\n", &("> " <> &1))
    end
  end

  defp block({"pre", _, _} = el) do
    case presence(el |> Floki.text() |> String.trim()) do
      nil -> nil
      code -> "```\n" <> code <> "\n```"
    end
  end

  defp block({tag, _, _} = el) when tag in ~w(ul ol) do
    el
    |> Floki.find("li")
    |> Enum.map(&inline/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {text, i} ->
      if tag == "ol", do: "#{i}. #{text}", else: "- #{text}"
    end)
    |> presence()
  end

  defp block(_), do: nil

  # Inline markup, kept: emphasis and links carry meaning, and a quote
  # anchored to a sentence should look like the sentence does on the page.
  defp inline(node) do
    node
    |> Floki.children()
    |> Enum.map_join(&render/1)
    |> clean()
  end

  defp render(text) when is_binary(text), do: text

  defp render({tag, _, _} = el) when tag in ~w(strong b), do: wrap(el, "**")
  defp render({tag, _, _} = el) when tag in ~w(em i), do: wrap(el, "*")
  defp render({"code", _, _} = el), do: wrap(el, "`")
  defp render({"br", _, _}), do: " "

  defp render({"a", attrs, _} = el) do
    text = inline(el)
    href = attrs |> Enum.into(%{}) |> Map.get("href", "")

    cond do
      text == "" -> ""
      href == "" or String.starts_with?(href, "#") -> text
      true -> "[#{text}](#{href})"
    end
  end

  # a footnote marker is a link to nowhere useful once the page is gone
  defp render({"sup", _, _}), do: ""
  defp render({_tag, _, _} = el), do: inline(el)
  defp render(_), do: ""

  # Emphasis must not wrap its own whitespace: `**text **` is not valid
  # CommonMark — the closing run is not right-flanking — and renders as four
  # literal asterisks. The space belongs outside the delimiters.
  defp wrap(el, mark) do
    raw = el |> Floki.children() |> Enum.map_join(&render/1) |> squash()

    case String.trim(raw) do
      "" ->
        ""

      text ->
        lead = if String.starts_with?(raw, " "), do: " ", else: ""
        trail = if String.ends_with?(raw, " "), do: " ", else: ""
        lead <> mark <> text <> mark <> trail
    end
  end

  # Normalising and trimming are different jobs. `wrap/2` has to know
  # whether the emphasis ended with a space, and it cannot if the space has
  # already been trimmed off — that was how "now. </strong>We intend" came
  # out as "now.**We intend", with the two words run together.
  defp squash(text) do
    text
    |> to_string()
    |> String.replace(~r/[\x{00a0}\x{200b}\t ]+/u, " ")
    |> String.replace(~r/\s*\n\s*/u, " ")
  end

  defp clean(text), do: text |> squash() |> String.trim()

  defp presence(""), do: nil
  defp presence(text), do: text

  defp drop_leading_title(markdown, title) do
    case String.split(markdown, "\n\n", parts: 2) do
      ["# " <> first, rest] ->
        if similar?(first, title), do: rest, else: markdown

      _ ->
        markdown
    end
  end

  defp similar?(a, b) do
    strip = fn t -> t |> String.downcase() |> String.replace(~r/[^\p{L}\p{N}]/u, "") end
    x = strip.(a)
    y = strip.(b)
    x != "" and (String.contains?(y, x) or String.contains?(x, y))
  end

  defp heading(""), do: ""
  defp heading(title), do: "# " <> title <> "\n\n"
end
