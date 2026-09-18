defmodule Marginalia.ImportTest do
  @moduledoc """
  Reading a draft off the web: what gets refused, and what survives the
  trip from HTML to markdown.
  """
  use ExUnit.Case, async: true

  alias Marginalia.Import

  describe "what may be fetched" do
    test "plain http and https to a public host" do
      assert {:ok, _} = Import.allowed("https://darioamodei.com/post/we-must-pace-the-frontier")
      assert {:ok, _} = Import.allowed("http://example.com/essay")
    end

    test "nothing that is not http" do
      for url <- [
            "file:///etc/passwd",
            "ftp://example.com/x",
            "gopher://example.com",
            "javascript:alert(1)",
            "data:text/html,hi"
          ] do
        assert {:error, :bad_scheme} = Import.allowed(url), "allowed #{url}"
      end
    end

    test "nothing on this machine or this network" do
      # the server makes the request, from inside the network, with whatever
      # the network trusts — so this is the boundary that matters
      for url <- [
            "http://localhost:4000/admin",
            "http://127.0.0.1/",
            "http://0.0.0.0/",
            "http://10.0.0.5/",
            "http://192.168.1.1/",
            "http://172.16.4.4/",
            "http://169.254.169.254/latest/meta-data/",
            "http://[::1]/",
            "http://something.local/",
            "http://box.internal/"
          ] do
        assert {:error, :private_address} = Import.allowed(url), "allowed #{url}"
      end
    end

    test "a hostname that resolves to loopback is still refused" do
      # the check cannot stop at the spelling of the host
      assert {:error, :private_address} = Import.allowed("http://localhost.localdomain/")
    end

    test "rubbish is refused rather than crashing" do
      assert {:error, _} = Import.allowed("not a url")
      assert {:error, _} = Import.allowed("https://")
      assert {:error, :bad_url} = Import.allowed(nil)
    end
  end

  describe "turning a page into a draft" do
    @html """
    <html><head><title>Site name — An Essay</title>
    <meta property="og:title" content="An Essay About Pacing" /></head>
    <body>
      <nav><a href="/">Home</a><a href="/about">About</a></nav>
      <article>
        <h1>An Essay About Pacing</h1>
        <p>The <strong>first</strong> paragraph, with an <em>aside</em> and
           a <a href="https://example.com/x">link</a>.</p>
        <h2>Why Pace?</h2>
        <p>A second paragraph that is long enough to count for something at all.</p>
        <ul><li>One thing</li><li>Another thing</li></ul>
        <ol><li>First</li><li>Second</li></ol>
        <blockquote><p>Something someone said.</p></blockquote>
        <pre><code>defmodule A do
        end</code></pre>
        <p>A closing paragraph, also of a reasonable length for a test fixture,
           carrying enough words that the importer treats the page as an article
           rather than as a stub with nothing on it worth reading.</p>
        <p>One more paragraph so the fixture clears the floor the importer puts
           under a page before it will accept it as a draft at all, which exists
           so that a navigation-only page does not arrive as an empty manuscript.</p>
      </article>
      <footer><p>Subscribe to our newsletter for more!</p></footer>
      <script>console.log('tracking')</script>
    </body></html>
    """

    defp imported, do: Import.fetch("https://example.com/essay", body: @html)

    test "the title comes from the page, not the tab" do
      assert {:ok, %{title: "An Essay About Pacing"}} = imported()
    end

    test "structure survives, because the segmenter cuts on headings" do
      {:ok, %{markdown: md}} = imported()

      assert md =~ "# An Essay About Pacing"
      assert md =~ "## Why Pace?"
      assert md =~ "- One thing"
      assert md =~ "1. First"
      assert md =~ "> Something someone said."
      assert md =~ "```"
    end

    test "inline markup survives" do
      {:ok, %{markdown: md}} = imported()

      assert md =~ "**first**"
      assert md =~ "*aside*"
      assert md =~ "[link](https://example.com/x)"
    end

    test "emphasis never wraps its own whitespace" do
      # `**text **` is not valid CommonMark and renders as four literal
      # asterisks — this is the bug my own hand conversion shipped
      {:ok, %{markdown: md}} =
        Import.fetch("https://example.com/e",
          body: """
          <article><h1>T</h1>
          <p><strong>Verifiability. </strong>Embedded evaluators can check things.</p>
          #{String.duplicate("<p>Padding sentence for length.</p>", 20)}
          </article>
          """
        )

      assert md =~ "**Verifiability.** Embedded"

      # the property that actually matters: `**text **` is not valid
      # CommonMark and comes out as four literal asterisks on the page.
      # `** ` on its own is fine — every closing delimiter is followed by
      # one — so the test has to render it rather than grep for it.
      {:safe, html} = Marginalia.Markdown.to_html(md)
      refute Regex.replace(~r/<[^>]+>/, html, "") =~ "*"
      assert html =~ "<strong>Verifiability.</strong>"
    end

    test "the furniture is left behind" do
      {:ok, %{markdown: md}} = imported()

      refute md =~ "Subscribe to our newsletter"
      refute md =~ "console.log"
      refute md =~ "Home"
    end

    test "a page with no article in it is refused rather than imported empty" do
      assert {:error, :too_little_text} =
               Import.fetch("https://example.com/x",
                 body: "<html><body><nav>Home</nav></body></html>"
               )
    end

    test "the source url comes back, so the draft can say where it is from" do
      assert {:ok, %{url: "https://example.com/essay"}} = imported()
    end

    test "a refused address never reaches the fetch" do
      assert {:error, :private_address} =
               Import.fetch("http://169.254.169.254/latest/meta-data/", body: @html)
    end
  end
end
