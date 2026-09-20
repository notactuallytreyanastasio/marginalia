defmodule MarginaliaWeb.ErrorHTML do
  @moduledoc """
  What a visitor gets when the address was wrong or something broke.

  The generated default renders the status name as plain text: a white page
  reading "Not Found", with no layout, no styling and no way back to
  anything. It is the page nobody writes and a stranger following a stale
  link is fairly likely to see first.

  Deliberately self-contained rather than the app layout. An error page that
  depends on the machinery which just failed is an error page that fails too,
  so this carries its own markup and its own styles and needs no session, no
  socket and no assigns beyond the two it is given.
  """
  use MarginaliaWeb, :html

  def render("404.html", _assigns) do
    page(%{
      heading: "Nothing at that address",
      body:
        "The link may be old, or the draft may have been taken down. " <>
          "Nothing is lost by following a wrong address."
    })
  end

  def render("500.html", _assigns) do
    page(%{
      heading: "Something broke",
      body:
        "That is this end, not yours, and it has been logged. Trying again in " <>
          "a moment is worth doing — most of what breaks here is transient."
    })
  end

  # Anything else keeps the generated behaviour: the status name, plainly.
  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)

  defp page(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="robots" content="noindex" />
        <title>{@heading} · Marginalia</title>
        <style>
          :root{color-scheme:light dark}
          body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;
            background:#fbfaf7;color:#1c1a17;
            font-family:"Iowan Old Style","Palatino Linotype",Palatino,Georgia,serif}
          main{max-width:32rem;padding:2rem 1.5rem}
          h1{font-size:1.5rem;font-weight:600;margin:0 0 .6rem;letter-spacing:-.01em}
          p{margin:0 0 1.2rem;line-height:1.65;color:#6b665e}
          nav{display:flex;gap:1rem;flex-wrap:wrap;font-size:.85rem;
            font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif}
          a{color:#8a3324;text-decoration:none;border-bottom:1px solid #e0dbd2;padding-bottom:1px}
          a:hover{border-bottom-color:#8a3324}
          @media (prefers-color-scheme:dark){
            body{background:#16150f;color:#e9e4d9}
            p{color:#a49e91}
            a{color:#e0a48a;border-bottom-color:#2e2b24}
          }
        </style>
      </head>
      <body>
        <main>
          <h1>{@heading}</h1>
          <p>{@body}</p>
          <nav>
            <a href="/">Marginalia</a>
            <a href="/cases">Cases</a>
            <a href="/drafts">Drafts</a>
            <a href="/reading">Readings</a>
          </nav>
        </main>
      </body>
    </html>
    """
  end
end
