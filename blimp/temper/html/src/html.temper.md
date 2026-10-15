# HTML

Escaping and a cheap tree builder. A page is a tree of plain nested lists with
string leaves, joined by one native call at the end. The tree is lists and not a
class because Blimp's native `flat` and `join` see lists only; a Temper class is
an actor they cannot look inside. Appending to a builder one piece at a time
copies everything on every call, so nothing here does it.

    @connected export let htmlFlatJoin(parts: List<AnyValue>): String;
    @connected export let htmlNowMs(): Int;

    let replaceAll(s: String, from: String, to: String): String {
      s.split(from).join(to) { (p): String => p }
    }

All five characters, `&` first.

    export let esc(s: String): String {
      replaceAll(replaceAll(replaceAll(replaceAll(replaceAll(s, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"), "\"", "&quot;"), "'", "&#39;")
    }

    export let attr(name: String, value: String?): String {
      if (value == null) { "" } else { " ${name}=\"${esc(value)}\"" }
    }

    export let hraw(s: String): List<AnyValue> { [s] }

    export let htext(s: String): List<AnyValue> { [esc(s)] }

    export let hv(tag: String, attrs: String): List<AnyValue> { ["<", tag, attrs, ">"] }

    export let h(tag: String, attrs: String, children: List<AnyValue>): List<AnyValue> {
      ["<", tag, attrs, ">", children, "</", tag, ">"]
    }

    export let hjoin(x: List<AnyValue>): String { htmlFlatJoin(x) }

    export let classes(xs: List<String?>): String {
      let kept = xs.filter { (x: String?): Boolean => x != null && !x.isEmpty };
      kept.join(" ") { (x: String?): String => x ?? "" }
    }
