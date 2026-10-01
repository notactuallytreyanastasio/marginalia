# Elixir for the @connected declarations in sentences.temper.md. bin/temper-gen
# copies this into the generated library, where the declarations call
# TemperConnected.<name>.
#
# Temper's core strings have no Unicode character data, and the sentence
# rules came from regexes with the `u` flag, where \s, \d and \p{Lu} are
# Unicode classes. Each predicate asks PCRE the same question with the same
# flag, so a code point is classed exactly as the regexes it replaces classed it.
defmodule TemperConnected do
  #
  # These run once per character, so ASCII, where every class is unambiguous,
  # is answered directly, and PCRE is asked only about the rest.
  def isUnicodeSpace(cp) when cp < 128, do: cp == 32 or (cp >= 9 and cp <= 13)
  def isUnicodeSpace(cp), do: Regex.match?(~r/\A\s\z/u, <<cp::utf8>>)
  def isUnicodeUpper(cp) when cp < 128, do: cp >= ?A and cp <= ?Z
  def isUnicodeUpper(cp), do: Regex.match?(~r/\A\p{Lu}\z/u, <<cp::utf8>>)
  def isUnicodeDigit(cp) when cp < 128, do: cp >= ?0 and cp <= ?9
  def isUnicodeDigit(cp), do: Regex.match?(~r/\A\d\z/u, <<cp::utf8>>)

  # for reflow.temper.md: \p{L} and \p{N}, case mapping, and String.length,
  # which counts graphemes, where Temper strings count code points
  def isUnicodeLetter(cp) when cp < 128, do: (cp >= ?a and cp <= ?z) or (cp >= ?A and cp <= ?Z)
  def isUnicodeLetter(cp), do: Regex.match?(~r/\A\p{L}\z/u, <<cp::utf8>>)
  def isUnicodeNumber(cp) when cp < 128, do: cp >= ?0 and cp <= ?9
  def isUnicodeNumber(cp), do: Regex.match?(~r/\A\p{N}\z/u, <<cp::utf8>>)
  def isUpcaseFixed(cp) when cp < 128, do: not (cp >= ?a and cp <= ?z)
  def isUpcaseFixed(cp), do: String.upcase(<<cp::utf8>>) == <<cp::utf8>>
  def downcase(s), do: String.downcase(s)
  def graphemeLength(s), do: String.length(s)

  # for segmenter.temper.md: titles are cut to a number of graphemes
  def graphemePrefix(s, n), do: String.slice(s, 0, n)
end
