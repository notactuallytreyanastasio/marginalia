# Reading a unified diff

`Marginalia.Diffs`: reading a unified diff well enough to quote code out of
it. A guide's code samples have to be real. A model asked for "the important
part of this change" will produce plausible code that appears nowhere in the
repository, so the model quotes a line and this finds it in the actual patch
and hands back the hunk around it.

What comes back drops the removed lines and strips the `+`: someone learning
the method wants the code that ended up there, not the edit that produced it.

    let { sysJoin } = import("sys/src");

## Hunks

`path` is the file named by the last `diff --git` line (its `b/` side),
`heading` is whatever follows the second `@@` (trimmed; usually the enclosing
function), `lines` are the hunk's lines with their first-column marker.

    export class DiffHunk(public path: String, public heading: String, public lines: List<String>) {}

    class DiffOpen {
      public var path: String = "";
      public var heading: String = "";
      public var lines: ListBuilder<String> = new ListBuilder<String>();
    }

## parse

Every hunk of a patch, in order. A line matching `diff --git a/<a> b/<b>`
closes the current hunk and sets the path to `<b>`; a line matching
`@@ -n[,n] +n[,n] @@<heading>` closes the current hunk and opens one; inside a
hunk any line whose first character is a space, `+` or `-` is kept. The
`--- a/x` and `+++ b/x` lines between `diff --git` and the first `@@` are
ignored because there is no hunk open yet; everything else is ignored.

    export let diffsParse(patch: String): List<DiffHunk> {
      let hunks = new ListBuilder<DiffHunk>();
      var current: DiffOpen? = null;
      var path = "";
      let all = patch.split("\n");
      var k = 0;
      while (k < all.length) {
        let line = all[k];
        k += 1;
        let file = diffsFilePath(line);
        let heading = diffsHunkHeading(line);
        let open = current;
        if (file != null) {
          diffsPush(hunks, open);
          current = null;
          path = file;
        } else if (heading != null) {
          diffsPush(hunks, open);
          let next = new DiffOpen();
          next.path = path;
          next.heading = worksTrim(heading);
          current = next;
        } else if (open != null) {
          if (!line.isEmpty) {
            let first = line[String.begin];
            if (first == 32 || first == 43 || first == 45) { open.lines.add(line); }
          }
        }
      }
      diffsPush(hunks, current);
      hunks.toList()
    }

    let diffsPush(hunks: ListBuilder<DiffHunk>, open: DiffOpen?): Void {
      if (open != null) {
        hunks.add(new DiffHunk(open.path, open.heading, open.lines.toList()));
      }
    }

`^diff --git a\/(?<a>.+?) b\/(?<b>.+)$`: the group `b`, or null. The lazy `a`
ends at the first ` b/` that leaves both sides non-empty.

    let diffsFilePath(line: String): String? {
      let prefix = "diff --git a/";
      if (!worksStartsWith(line, prefix)) { return null; }
      let rest = diffsDrop(line, 13);
      let parts = rest.split(" b/");
      var k = 1;
      while (k < parts.length) {
        let a = sysJoin(parts.slice(0, k), " b/");
        let b = sysJoin(parts.slice(k, parts.length), " b/");
        if (!a.isEmpty && !b.isEmpty) { return b; }
        k += 1;
      }
      null
    }

`^@@ -\d+(?:,\d+)? \+\d+(?:,\d+)? @@(?<heading>.*)$`: the text after the
closing `@@`, or null when the line is not a hunk header.

    let diffsHunkHeading(line: String): String? {
      if (!worksStartsWith(line, "@@ -")) { return null; }
      var i = diffsRange(line, line.next(line.next(line.next(line.next(String.begin)))));
      if (!line.hasIndex(i) || line[i] != 32) { return null; }
      i = line.next(i);
      if (!line.hasIndex(i) || line[i] != 43) { return null; }
      i = diffsRange(line, line.next(i));
      let tail = line.slice(i, line.end);
      if (!worksStartsWith(tail, " @@")) { return null; }
      diffsDrop(tail, 3)
    }

`\d+(?:,\d+)?` at `from`: the index after it, or the end of the line when the
digits did not start there (the caller's checks then fail on that index).

    let diffsRange(line: String, from: StringIndex): StringIndex {
      var i = diffsDigits(line, from);
      if (i == from) { return line.end; }
      if (line.hasIndex(i) && line[i] == 44) {
        let after = diffsDigits(line, line.next(i));
        if (after == line.next(i)) { return line.end; }
        i = after;
      }
      i
    }

    let diffsDrop(s: String, n: Int): String {
      worksSliceCp(s, n, worksCodePoints(s))
    }

    let diffsDigits(line: String, from: StringIndex): StringIndex {
      var i = from;
      while (line.hasIndex(i) && line[i] >= 48 && line[i] <= 57) { i = line.next(i); }
      i
    }

## What a hunk holds

The paths a patch touches, in order of first appearance.

    export let diffsFiles(patch: String): List<String> {
      let seen = new ListBuilder<String>();
      for (let h of diffsParse(patch)) {
        if (!worksIn(seen.toList(), h.path)) { seen.add(h.path); }
      }
      seen.toList()
    }

Only what this hunk added, for matching a quote against: the `+` lines with the
`+` removed, joined by newlines.

    export let diffsAdded(hunk: DiffHunk): String {
      let out = new ListBuilder<String>();
      for (let l of hunk.lines) {
        if (l[String.begin] == 43) { out.add(l.slice(l.next(String.begin), l.end)); }
      }
      sysJoin(out.toList(), "\n")
    }

The hunk as you would paste it into a document: additions with their marker
stripped, context kept so the excerpt stands on its own, removals dropped, and
no newline at either end.

    export let diffsSample(hunk: DiffHunk): String {
      let out = new ListBuilder<String>();
      for (let l of hunk.lines) {
        let first = l[String.begin];
        if (first == 43 || first == 32) { out.add(l.slice(l.next(String.begin), l.end)); }
      }
      diffsTrimNewlines(sysJoin(out.toList(), "\n"))
    }

    let diffsTrimNewlines(s: String): String {
      var b = String.begin;
      while (s.hasIndex(b) && s[b] == 10) { b = s.next(b); }
      var e = s.end;
      while (e > b && s[s.prev(e)] == 10) { e = s.prev(e); }
      s.slice(b, e)
    }

## find

The first hunk whose added lines contain `quote`, or null. Re-indentation is
forgiven and invention is not: the quote is found as it is, or with every run
of whitespace folded to one space on both sides, as `Cuts.locate/2` does. A
blank quote is never found.

    export let diffsFind(patch: String, quote: String): DiffHunk? {
      if (worksIsBlank(quote)) { return null; }
      let hunks = diffsParse(patch);
      var i = 0;
      while (i < hunks.length) {
        let added = diffsAdded(hunks[i]);
        if (worksContains(added, quote)) { return hunks[i]; }
        if (worksContains(worksCollapse(added), worksCollapse(quote))) { return hunks[i]; }
        i += 1;
      }
      null
    }
