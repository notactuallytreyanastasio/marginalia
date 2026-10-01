# marginalia-core

Marginalia's text logic, written once in Temper: the paragraph diff that
lines up two versions of a draft, and the word diff inside each edited
paragraph. Generated into Elixir by `bin/temper-gen`; the Elixir side is
`Marginalia.Diff` and `Marginalia.Rewrite.diff/2`, which call into it.

    export let name = "marginalia-core";
