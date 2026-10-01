# Elixir for the @connected declarations in sentences.temper.md. bin/temper-gen
# copies this into the generated library, where the declarations call
# TemperConnected.<name>.
#
# Temper's core strings have no Unicode character data, and the sentence
# rules came from regexes with the `u` flag, where \s, \d and \p{Lu} are
# Unicode classes. Each predicate asks PCRE the same question with the same
# flag, so a code point is classed exactly as the regexes it replaces classed it.
defmodule TemperConnected do
  def isUnicodeSpace(cp), do: Regex.match?(~r/\A\s\z/u, <<cp::utf8>>)
  def isUnicodeUpper(cp), do: Regex.match?(~r/\A\p{Lu}\z/u, <<cp::utf8>>)
  def isUnicodeDigit(cp), do: Regex.match?(~r/\A\d\z/u, <<cp::utf8>>)
end
