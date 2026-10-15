# Blocks

A draft's blocks: what blank lines separate, except that a fenced code
block is one block however many blank lines it holds. This is
`Marginalia.Reading.split/1`; everything that reads or anchors into a
draft works on these blocks.

    export let blocks(body: String): List<String> {
      let out = new ListBuilder<String>();
      let current = new ListBuilder<String>();
      var fence: String? = null;
      let lines = body.split("\n");
      for (var k = 0; k < lines.length; ++k) {
        let line = lines[k];
        let open = fence;
        if (open != null) {
          current.add(line);
          // inside a fence, only its own closer ends it
          if (startsWith(trimLeading(line), open)) {
            flushBlock(current, out);
            fence = null;
          }
        } else {
          let opener = fenceOpener(line);
          if (opener != null) {
            // a fence starts a block of its own
            flushBlock(current, out);
            current.add(line);
            fence = opener;
          } else if (trim(line).isEmpty) {
            flushBlock(current, out);
          } else {
            current.add(line);
          }
        }
      }
      flushBlock(current, out);
      let kept = new ListBuilder<String>();
      let all = out.toList();
      for (var k = 0; k < all.length; ++k) {
        let block = trimTrailing(all[k]);
        if (!trim(block).isEmpty) { kept.add(block); }
      }
      kept.toList()
    }

    let flushBlock(current: ListBuilder<String>, out: ListBuilder<String>): Void {
      if (!current.isEmpty) {
        out.add(joinWith(current.toList(), "\n"));
        current.clear();
      }
    }

The fence a line opens: `^\s*(`{3,}|~{3,})`, ASCII space, the whole run.

    let fenceOpener(line: String): String? {
      var i = String.begin;
      while (line.hasIndex(i) && isRegexSpace(line[i])) { i = line.next(i); }
      if (!line.hasIndex(i)) { return null; }
      let mark = line[i];
      if (mark != 96 && mark != 126) { return null; }
      let start = i;
      var count = 0;
      while (line.hasIndex(i) && line[i] == mark) {
        count += 1;
        i = line.next(i);
      }
      if (count >= 3) { line.slice(start, i) } else { null }
    }
