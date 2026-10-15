# Tests for the patch reader

`Marginalia.Diffs` has no tests of its own in the Elixir suite (spec section
4.11 describes it); these pin every rule that section states.

    let { sysJoin } = import("sys/src");

    let patch(): String {
      sysJoin([
        "diff --git a/lib/a.ex b/lib/a.ex",
        "index 1234567..89abcde 100644",
        "--- a/lib/a.ex",
        "+++ b/lib/a.ex",
        "@@ -1,3 +1,4 @@ defmodule A do  ",
        " line one",
        "-line two",
        "+line two changed",
        "+line three",
        " line four",
        "",
        "\\ No newline at end of file",
        "diff --git a/lib/b.ex b/lib/b.ex",
        "new file mode 100644",
        "--- /dev/null",
        "+++ b/lib/b.ex",
        "@@ -0,0 +1,2 @@",
        "+def b do",
        "+  :ok",
        "@@ -10 +11 @@ def c",
        "-old",
        "+  new indented",
      ], "\n")
    }

    test("every hunk comes back in order with its path and heading") { test =>
      let hunks = diffsParse(patch());
      expectInt(test, hunks.length, 3);
      expectText(test, hunks[0].path, "lib/a.ex");
      expectText(test, hunks[0].heading, "defmodule A do");
      expectText(test, hunks[1].path, "lib/b.ex");
      expectText(test, hunks[1].heading, "");
      expectText(test, hunks[2].path, "lib/b.ex");
      expectText(test, hunks[2].heading, "def c");
    }

    test("a hunk keeps the lines that start with a space, a plus or a minus") { test =>
      let hunks = diffsParse(patch());
      expectText(test, sysJoin(hunks[0].lines, "|"), " line one|-line two|+line two changed|+line three| line four");
      expectText(test, sysJoin(hunks[1].lines, "|"), "+def b do|+  :ok");
    }

    test("header lines before the first hunk are not part of it") { test =>
      let hunks = diffsParse(patch());
      for (let l of hunks[0].lines) {
        expectFalse(test, hasText(l, "a/lib/a.ex"), "no --- line");
        expectFalse(test, hasText(l, "index"), "no index line");
      }
    }

    test("the files are unique and in order of first appearance") { test =>
      expectText(test, sysJoin(diffsFiles(patch()), ","), "lib/a.ex,lib/b.ex");
      expectInt(test, diffsFiles("").length, 0);
    }

    test("added is the plus lines without their plus") { test =>
      let hunks = diffsParse(patch());
      expectText(test, diffsAdded(hunks[0]), "line two changed\nline three");
      expectText(test, diffsAdded(hunks[1]), "def b do\n  :ok");
      expectText(test, diffsAdded(hunks[2]), "  new indented");
    }

    test("sample is additions and context, with no removals and no outer newlines") { test =>
      let hunks = diffsParse(patch());
      expectText(test, diffsSample(hunks[0]), "line one\nline two changed\nline three\nline four");
      expectText(test, diffsSample(hunks[2]), "  new indented");
      let blanks = diffsParse("diff --git a/x b/x\n@@ -1,3 +1,3 @@\n+\n+\n+code\n+\n");
      expectText(test, diffsSample(blanks[0]), "code");
    }

    test("find returns the first hunk whose added lines hold the quote") { test =>
      let found = diffsFind(patch(), "line two changed");
      expectText(test, if (found != null) { found.path } else { "none" }, "lib/a.ex");
      let b = diffsFind(patch(), "def b do\n  :ok");
      expectText(test, if (b != null) { b.path } else { "none" }, "lib/b.ex");
    }

    test("find forgives re-indentation and wrapping but not invention") { test =>
      let found = diffsFind(patch(), "def   b do :ok");
      expectText(test, if (found != null) { found.path } else { "none" }, "lib/b.ex");
      let spaced = diffsFind(patch(), "new\nindented");
      expectText(test, if (spaced != null) { spaced.heading } else { "none" }, "def c");
      expectTrue(test, diffsFind(patch(), "line two") != null, "a prefix of a line is in it");
      expectTrue(test, diffsFind(patch(), "line four") == null, "context is not added");
      expectTrue(test, diffsFind(patch(), "line two before") == null, "invention");
      expectTrue(test, diffsFind(patch(), "old") == null, "a removed line is not added");
    }

    test("a blank quote is never found") { test =>
      expectTrue(test, diffsFind(patch(), "") == null, "empty");
      expectTrue(test, diffsFind(patch(), "  \n ") == null, "whitespace");
    }

    test("the path is the b side of the diff line, and a rename follows the new name") { test =>
      let p = "diff --git a/old/name.txt b/new/name.txt\nsimilarity index 90%\nrename from old/name.txt\nrename to new/name.txt\n@@ -1 +1 @@\n-a\n+b\n";
      let hunks = diffsParse(p);
      expectInt(test, hunks.length, 1);
      expectText(test, hunks[0].path, "new/name.txt");
    }

    test("a path with spaces, and one with ' b/' inside, follow the lazy match") { test =>
      let spaced = diffsParse("diff --git a/my file.txt b/my file.txt\n@@ -1 +1 @@\n+x\n");
      expectText(test, spaced[0].path, "my file.txt");
      let tricky = diffsParse("diff --git a/a b/c b/a b/c\n@@ -1 +1 @@\n+x\n");
      expectText(test, tricky[0].path, "c b/a b/c");
    }

    test("hunk headers need both ranges and the closing marker") { test =>
      let ok = diffsParse("diff --git a/x b/x\n@@ -1 +1 @@\n+a\n@@ -3,4 +5,6 @@ fn()\n+b\n");
      expectInt(test, ok.length, 2);
      expectText(test, ok[1].heading, "fn()");
      expectInt(test, diffsParse("diff --git a/x b/x\n@@ -1,2 +1,2\n+a\n").length, 0);
      expectInt(test, diffsParse("diff --git a/x b/x\n@@ -a +1 @@\n+a\n").length, 0);
      expectInt(test, diffsParse("diff --git a/x b/x\n@@ -1, +1 @@\n+a\n").length, 0);
      expectInt(test, diffsParse("diff --git a/x b/x\n@@ 1 +1 @@\n+a\n").length, 0);
      expectInt(test, diffsParse("diff --git a/x b/x\n@@ -1 1 @@\n+a\n").length, 0);
    }

    test("a hunk with no file line has an empty path, and a bare file line has no hunks") { test =>
      let loose = diffsParse("@@ -1 +1 @@\n+a\n");
      expectInt(test, loose.length, 1);
      expectText(test, loose[0].path, "");
      expectInt(test, diffsParse("diff --git a/x b/x\n").length, 0);
      expectInt(test, diffsParse("").length, 0);
      expectInt(test, diffsParse("just some text\nnot a patch").length, 0);
    }

    test("a minus-minus line inside a hunk is kept, as the Elixir kept it") { test =>
      let hunks = diffsParse("diff --git a/x b/x\n@@ -1,2 +1,1 @@\n--- a removed line that starts with dashes\n+kept\n");
      expectInt(test, hunks[0].lines.length, 2);
    }

    test("a file line closes the hunk before it") { test =>
      let hunks = diffsParse("diff --git a/x b/x\n@@ -1 +1 @@\n+a\ndiff --git a/y b/y\n+not in a hunk\n@@ -1 +1 @@\n+b\n");
      expectInt(test, hunks.length, 2);
      expectText(test, sysJoin(hunks[0].lines, "|"), "+a");
      expectText(test, hunks[1].path, "y");
      expectText(test, sysJoin(hunks[1].lines, "|"), "+b");
    }
