# What the tests share

Every check runs inside a helper that takes the `test`. The Temper frontend
evaluates any expression whose inputs are all known while compiling, so a bare
`assert(esc("<") == "&lt;")` becomes `assert(true)` and tests the compiler's
interpreter instead of the generated code. A function that takes the `test` is
not evaluated early.

    let expectText(test: Test, got: String, want: String): Void {
      if (got != want) { console.log("MISMATCH\nGOT:  ${got.split("\n").join("\\n") { (p): String => p }}\nWANT: ${want.split("\n").join("\\n") { (p): String => p }}"); }
      assert(got == want) { "got:\n${got}\nwant:\n${want}" }
    }

    let expectInt(test: Test, got: Int, want: Int): Void {
      assert(got == want) { "got: ${got} want: ${want}" }
    }

    let expectTrue(test: Test, got: Boolean, why: String): Void {
      assert(got) { why }
    }
