# Small text helpers

## Slugs

`mint_slug(name)` without the uniqueness suffix: lower-case, every run of
characters outside `a-z0-9` becomes one `-`, leading and trailing `-` go, the
first 60 characters are kept, and nothing left means `"stack"`. Lower-casing
here is ASCII only; every other character is replaced by `-` anyway, so the only
difference from Elixir's `String.downcase` is a non-ASCII capital that lower-cases
into ASCII (the Kelvin sign, U+212A, becomes `k` in Elixir and a dash here).

`slugPlain` is `Cases.slug(name)`: the same without the 60-character cap and
without the `"stack"` fallback (it can return the empty string).

    let slugBase(s: String): String {
      let parts = new ListBuilder<String>();
      var pendingDash = false;
      var i = String.begin;
      while (s.hasIndex(i)) {
        let c = s[i];
        let lower = if (c >= 65 && c <= 90) { c + 32 } else { c };
        if ((lower >= 97 && lower <= 122) || (lower >= 48 && lower <= 57)) {
          if (pendingDash && parts.length > 0) { parts.add("-"); }
          pendingDash = false;
          parts.add(cpStr(lower));
        } else {
          pendingDash = true;
        }
        i = s.next(i);
      }
      joinStr(parts.toList(), "")
    }

    export let slugPlain(s: String): String { slugBase(s) }

The trim happens before the cut, as in Elixir, so a cut that lands just after a
dash keeps that dash.

    export let slug(s: String): String {
      let base = takeChars(slugBase(s), 60);
      if (base.isEmpty) { "stack" } else { base }
    }

## Words

A word is a maximal run of characters that are not ASCII whitespace (tab,
newline, vertical tab, form feed, carriage return, space):
`length(String.split(text, ~r/\s+/, trim: true))`. Everything else, a bare `#`
included, is a word.

    let wordsOf(s: String): List<String> {
      let flat = replaceAll(replaceAll(replaceAll(replaceAll(replaceAll(s, "\n", " "), "\t", " "), "\r", " "),
        cpStr(11), " "), cpStr(12), " ");
      flat.split(" ").filter { (w): Boolean => !w.isEmpty }
    }

    export let wordCount(s: String): Int { wordsOf(s).length }

The first `n` words, joined with the spacing they had, and `…` after them when
there were more. `n <= 0` gives just the ellipsis for a non-empty text. Text of `n`
words or fewer comes back unchanged.

    export let truncateWords(s: String, n: Int): String {
      let words = wordsOf(s);
      if (words.length <= n) { return s; }
      if (n <= 0) { return "…"; }
      var i = String.begin;
      var seen = 0;
      var inWord = false;
      var cut = s.end;
      var found = false;
      while (!found && s.hasIndex(i)) {
        let c = s[i];
        if (isSpaceCp(c)) {
          if (inWord) {
            seen += 1;
            inWord = false;
            if (seen == n) { cut = i; found = true; }
          }
        } else {
          inWord = true;
        }
        i = s.next(i);
      }
      "${s.slice(String.begin, cut)}…"
    }
