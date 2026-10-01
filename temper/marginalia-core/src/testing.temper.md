# What the tests share

Every check in these tests runs inside a helper that takes the `test`.
That matters. The Temper frontend evaluates any expression whose inputs
are all known while compiling, on every backend, through as many pure
calls as it takes: `assert(!isWrapped(repeated("word ", 30)))` comes out
as `assert(true)`, and tests the compiler's interpreter instead of the
generated code. A function that takes the `test` is not evaluated
early, so a check inside one runs the generated code. Calls to
`@connected` functions are never evaluated early either.

    let repeated(word: String, n: Int): String {
      let sb = new StringBuilder();
      for (var i = 0; i < n; i += 1) { sb.append(word); }
      sb.toString()
    }

    let includes(s: String, part: String): Boolean {
      s.split(part).length > 1
    }

    let expectText(test: Test, got: String, want: String): Void {
      assert(got == want) { "got:\n${got}\nwant:\n${want}" }
    }
