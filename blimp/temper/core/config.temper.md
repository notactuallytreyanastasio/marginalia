# core

Marginalia's text logic, written once in Temper: the paragraph diff that
lines up two versions of a draft, the word diff inside each edited
paragraph, sentence reflow, PDF page reflow and the segmenter. It runs on
the Blimp backend; the nine `@connected` functions that need Unicode data
are answered in `src/_connected.blimp`.

    export let name = "core";
