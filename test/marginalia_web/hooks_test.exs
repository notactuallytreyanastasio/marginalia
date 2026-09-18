defmodule MarginaliaWeb.HooksTest do
  @moduledoc """
  Every colocated hook a template asks for exists.

  `phx-hook=".Composer"` was on the chat's form and no `.Composer` hook
  was ever written. LiveView throws `unknown hook` on the client, the
  binding for that element never attaches, and the chat opened, accepted
  typing and sent nothing.

  Nothing server-side could catch it: `Phoenix.LiveViewTest` renders the
  markup and never runs a hook, so the whole suite was green while the
  feature was dead. This is the cheap structural check that would have —
  the names have to match, and a typo or a deletion fails here.
  """
  use ExUnit.Case, async: true

  @dir "lib/marginalia_web"

  defp files do
    Path.wildcard("#{@dir}/**/*.ex")
  end

  test "every colocated hook referenced by a template is defined in the same module" do
    missing =
      for path <- files(),
          source = File.read!(path),
          [_, name] <- Regex.scan(~r/phx-hook="\.([A-Za-z0-9_]+)"/, source),
          not String.contains?(source, ~s(ColocatedHook} name=".#{name}")),
          do: {Path.relative_to_cwd(path), name}

    assert missing == [],
           "referenced but never defined:\n" <>
             Enum.map_join(missing, "\n", fn {f, n} -> "  #{f}: phx-hook=\".#{n}\"" end)
  end

  test "every colocated hook that is defined is actually used" do
    unused =
      for path <- files(),
          source = File.read!(path),
          [_, name] <- Regex.scan(~r/ColocatedHook\} name="\.([A-Za-z0-9_]+)"/, source),
          not String.contains?(source, ~s(phx-hook=".#{name}")),
          do: {Path.relative_to_cwd(path), name}

    assert unused == [],
           "defined and never referenced:\n" <>
             Enum.map_join(unused, "\n", fn {f, n} -> "  #{f}: .#{n}" end)
  end

  # LiveView's own hook API, plus what a hook is handed.
  @builtin ~w(
    mounted beforeUpdate updated destroyed disconnected reconnected
    pushEvent pushEventTo handleEvent upload uploadTo js
  )

  # Second time in two days that a JavaScript feature died in silence:
  # first a hook that was never written, then a method deleted while its
  # caller stayed. Both looked like "the button does nothing", both
  # passed every test, because LiveViewTest renders markup and never
  # runs a hook.
  test "every this.method() a hook calls is defined in that hook" do
    missing =
      for path <- files(),
          {name, body} <- hooks(File.read!(path)),
          called <- calls(body),
          called not in @builtin,
          not defines?(body, called),
          do: {Path.relative_to_cwd(path), name, called}

    assert missing == [],
           "called but never defined:\n" <>
             Enum.map_join(missing, "\n", fn {f, h, m} -> "  #{f}: .#{h} calls this.#{m}()" end)
  end

  # each colocated hook's name and its body
  defp hooks(source) do
    ~r/ColocatedHook\} name="\.([A-Za-z0-9_]+)">(.*?)<\/script>/s
    |> Regex.scan(source)
    |> Enum.map(fn [_, name, body] -> {name, body} end)
  end

  defp calls(body) do
    ~r/this\.([A-Za-z_][A-Za-z0-9_]*)\s*\(/
    |> Regex.scan(body)
    |> Enum.map(fn [_, m] -> m end)
    |> Enum.uniq()
  end

  # either a method shorthand, or a function assigned onto `this`
  defp defines?(body, name) do
    Regex.match?(~r/(^|[\s,{])#{name}\s*\([^)]*\)\s*\{/, body) or
      Regex.match?(~r/this\.#{name}\s*=/, body)
  end

  # A hook reaching for an element that is not there fails the same
  # silent way: `querySelector` returns null, the next line throws or
  # quietly does nothing, and the markup and the tests both look fine.
  # `.fl-mid` went missing from my own reading of the page for an hour
  # on exactly this.
  test "every element a hook reaches for exists in the markup" do
    haystack =
      files()
      |> Enum.map_join("\n", fn path ->
        source = File.read!(path)

        # The templates, with hook bodies stripped — or a selector would
        # satisfy itself. Plus the class names a hook *writes*: the graph
        # hook builds its own `<g class="gnode">` and then selects it,
        # which is legitimate and invisible to a template-only search.
        String.replace(source, ~r/ColocatedHook\}.*?<\/script>/s, "") <> "\n" <> written(source) <> "\n" <> applied(source)
      end)

    missing =
      for path <- files(),
          {hook, body} <- hooks(File.read!(path)),
          token <- tokens(body),
          not present?(haystack, bare(token)),
          do: {Path.relative_to_cwd(path), hook, token}

    assert missing == [],
           "selectors that match nothing in any template:\n" <>
             Enum.map_join(missing, "\n", fn {f, h, t} -> "  #{f}: .#{h} looks for #{t}" end)
  end

  # Classes a hook puts on at runtime rather than rendering: the graph
  # hook marks its selected node with `classList.add("sel")` and then
  # selects `.gnode.sel`. Nothing in any template says "sel", and that
  # is correct.
  defp applied(source) do
    # `add` and `toggle` put a class on something; `remove` and
    # `contains` only ask about one, and counting those let a selector
    # satisfy itself — `classList.contains("fl-mid")` kept this test
    # green while the element it names had been renamed away.
    adds =
      ~r/classList\.(?:add|toggle)\(\s*["']([A-Za-z0-9_-]+)["']/
      |> Regex.scan(source)
      |> Enum.map_join(" ", fn [_, c] -> c end)

    # `el.className = "fl-card k-" + kind` is the other way a hook names
    # something it builds. The static part is the name; whatever gets
    # interpolated after it is not this test's business.
    assigns =
      ~r/className\s*=\s*[`"']([^`"'$]*)/
      |> Regex.scan(source)
      |> Enum.map_join(" ", fn [_, c] -> c end)

    adds <> " " <> assigns
  end

  # class and id values inside markup a hook builds as a string
  defp written(source) do
    ~r/(?:class|id)=\\?["'][^"'<>]{0,120}\\?["']/
    |> Regex.scan(source)
    |> List.flatten()
    |> Enum.join(" ")
  end

  # The class, id and data-attribute names a hook's selectors name.
  #
  # An interpolated id — `#blk-other-${ref}` — is only half a name, and
  # the halves either side of the `${}` are not selectors at all: without
  # stripping them this flags `.dataset` and `.peerRef` as missing
  # elements. Anything built at runtime is out of scope here; what this
  # checks is the static names.
  defp tokens(body) do
    ~r/(?:querySelector|querySelectorAll|closest|matches)\(\s*[`"']([^`"']+)[`"']/
    |> Regex.scan(body)
    |> Enum.map(fn [_, sel] -> sel end)
    |> Enum.reject(&String.contains?(&1, "${"))
    |> Enum.flat_map(&Regex.scan(~r/[.#][A-Za-z0-9_-]+|\[data-[a-z-]+\]/, &1))
    |> List.flatten()
    |> Enum.uniq()
  end

  # A whole name, not a substring: renaming `fl-mid` to `fl-middle` left
  # the old token still "found" inside the new one, so the first version
  # of this test passed against exactly the bug it was written for.
  defp present?(haystack, name) do
    Regex.match?(~r/(?<![A-Za-z0-9_-])#{Regex.escape(name)}(?![A-Za-z0-9_-])/, haystack)
  end

  defp bare("." <> name), do: name
  defp bare("#" <> name), do: name
  defp bare("[" <> rest), do: String.trim_trailing(rest, "]")

  test "the chat's composer is among them" do
    source = File.read!("#{@dir}/components/link_chat.ex")

    assert source =~ ~s(phx-hook=".Composer")
    assert source =~ ~s(ColocatedHook} name=".Composer")
  end
end
