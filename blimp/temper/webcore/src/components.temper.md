# Core components

Ports of `MarginaliaWeb.CoreComponents`, with the same attributes and the same
class strings. A Phoenix function component took assigns and slots; these take
the assigns as arguments and a slot as a `List<AnyValue>` tree. `rest` (the
global attributes) is a string already built with `attr(...)`, appended
verbatim after the named attributes, so the caller escapes it. Names start with
`c` because every export shares one namespace.


    let { attr, h, hv, htext, hraw, classes, hjoin } = import("html/src");
    let { JsonTextProducer, NullInterchangeContext } = import("std/json");

## icon/1

Phoenix rendered `<span class="hero-x-mark size-5"></span>`, and the committed
`app.css` already carries the `.hero-*` mask classes for the seven icons the app
uses (`information-circle`, `exclamation-circle`, `x-mark`, `arrow-path`,
`computer-desktop-micro`, `sun-micro`, `moon-micro`). So `cIcon` emits exactly
that span and costs nothing. `cIconSvg` is the same icon as an inline
`<svg>`, with the path data from `deps/heroicons/optimized`, for a place that
cannot lean on the stylesheet (an email, a standalone page).

    export let cIconClass(name: String, cls: String): List<AnyValue> {
      if (!wcStartsWith(name, "hero-")) {
        console.log("cIcon: name must start with hero-: ${name}");
        panic()
      }
      h("span", attr("class", "${name} ${cls}"), [])
    }

    export let cIcon(name: String): List<AnyValue> {
      cIconClass(name, "size-4")
    }

    let wcOutlineOpen(): String {
      "<svg xmlns=\"http://www.w3.org/2000/svg\" fill=\"none\" viewBox=\"0 0 24 24\" stroke-width=\"1.5\" stroke=\"currentColor\" aria-hidden=\"true\" data-slot=\"icon\""
    }

    let wcMicroOpen(): String {
      "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 16 16\" fill=\"currentColor\" aria-hidden=\"true\" data-slot=\"icon\""
    }

    let wcOutlinePath(d: String): String {
      "<path stroke-linecap=\"round\" stroke-linejoin=\"round\" d=\"${d}\"/></svg>"
    }

    let wcIconOpen(name: String): String {
      if (name == "hero-information-circle" || name == "hero-exclamation-circle" || name == "hero-x-mark" || name == "hero-arrow-path") {
        wcOutlineOpen()
      } else if (name == "hero-computer-desktop-micro" || name == "hero-sun-micro" || name == "hero-moon-micro") {
        wcMicroOpen()
      } else {
        console.log("cIconSvg: unknown icon ${name}");
        panic()
      }
    }

    let wcIconBody(name: String): String {
      if (name == "hero-information-circle") {
        wcOutlinePath("m11.25 11.25.041-.02a.75.75 0 0 1 1.063.852l-.708 2.836a.75.75 0 0 0 1.063.853l.041-.021M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Zm-9-3.75h.008v.008H12V8.25Z")
      } else if (name == "hero-exclamation-circle") {
        wcOutlinePath("M12 9v3.75m9-.75a9 9 0 1 1-18 0 9 9 0 0 1 18 0Zm-9 3.75h.008v.008H12v-.008Z")
      } else if (name == "hero-x-mark") {
        wcOutlinePath("M6 18 18 6M6 6l12 12")
      } else if (name == "hero-arrow-path") {
        wcOutlinePath("M16.023 9.348h4.992v-.001M2.985 19.644v-4.992m0 0h4.992m-4.993 0 3.181 3.183a8.25 8.25 0 0 0 13.803-3.7M4.031 9.865a8.25 8.25 0 0 1 13.803-3.7l3.181 3.182m0-4.991v4.99")
      } else if (name == "hero-computer-desktop-micro") {
        "<path fill-rule=\"evenodd\" d=\"M2 4.25A2.25 2.25 0 0 1 4.25 2h7.5A2.25 2.25 0 0 1 14 4.25v5.5A2.25 2.25 0 0 1 11.75 12h-1.312c.1.128.21.248.328.36a.75.75 0 0 1 .234.545v.345a.75.75 0 0 1-.75.75h-4.5a.75.75 0 0 1-.75-.75v-.345a.75.75 0 0 1 .234-.545c.118-.111.228-.232.328-.36H4.25A2.25 2.25 0 0 1 2 9.75v-5.5Zm2.25-.75a.75.75 0 0 0-.75.75v4.5c0 .414.336.75.75.75h7.5a.75.75 0 0 0 .75-.75v-4.5a.75.75 0 0 0-.75-.75h-7.5Z\" clip-rule=\"evenodd\"/></svg>"
      } else if (name == "hero-sun-micro") {
        "<path d=\"M8 1a.75.75 0 0 1 .75.75v1.5a.75.75 0 0 1-1.5 0v-1.5A.75.75 0 0 1 8 1ZM10.5 8a2.5 2.5 0 1 1-5 0 2.5 2.5 0 0 1 5 0ZM12.95 4.11a.75.75 0 1 0-1.06-1.06l-1.062 1.06a.75.75 0 0 0 1.061 1.062l1.06-1.061ZM15 8a.75.75 0 0 1-.75.75h-1.5a.75.75 0 0 1 0-1.5h1.5A.75.75 0 0 1 15 8ZM11.89 12.95a.75.75 0 0 0 1.06-1.06l-1.06-1.062a.75.75 0 0 0-1.062 1.061l1.061 1.06ZM8 12a.75.75 0 0 1 .75.75v1.5a.75.75 0 0 1-1.5 0v-1.5A.75.75 0 0 1 8 12ZM5.172 11.89a.75.75 0 0 0-1.061-1.062L3.05 11.89a.75.75 0 1 0 1.06 1.06l1.06-1.06ZM4 8a.75.75 0 0 1-.75.75h-1.5a.75.75 0 0 1 0-1.5h1.5A.75.75 0 0 1 4 8ZM4.11 5.172A.75.75 0 0 0 5.173 4.11L4.11 3.05a.75.75 0 1 0-1.06 1.06l1.06 1.06Z\"/></svg>"
      } else {
        "<path d=\"M14.438 10.148c.19-.425-.321-.787-.748-.601A5.5 5.5 0 0 1 6.453 2.31c.186-.427-.176-.938-.6-.748a6.501 6.501 0 1 0 8.585 8.586Z\"/></svg>"
      }
    }

    export let cIconSvg(name: String, cls: String): List<AnyValue> {
      hraw("${wcIconOpen(name)}${attr("class", cls)}>${wcIconBody(name)}")
    }

## error

The private `error/1` of the input component: one message under a field.

    export let cError(message: String): List<AnyValue> {
      h("p", attr("class", "mt-1.5 flex gap-2 items-center text-sm text-error"), [
        cIconClass("hero-exclamation-circle", "size-5"),
        htext(message),
      ])
    }

    let wcErrors(errors: List<String>): List<AnyValue> {
      errors.map { (m: String): List<AnyValue> => cError(m) }
    }

## translate_error

The Elixir looked the message up in gettext (domain `errors`) and filled
`%{name}` placeholders from the options. There is no catalog and no second
locale, so this is the placeholder part only: each `%{key}` in `msg` becomes
`opts[key]`. (`count` is just another key.)

    export let cTranslateError(msg: String, opts: Map<String, String>): String {
      var out = msg;
      let ks = opts.keys();
      for (var i = 0; i < ks.length; ++i) {
        let k = ks.getOr(i, "");
        out = out.split("%{${k}}").join(opts.getOr(k, "")) { (p: String): String => p };
      }
      out
    }

    export let cTranslateErrors(errors: List<Pair<String, String>>, field: String): List<String> {
      let out = new ListBuilder<String>();
      for (var i = 0; i < errors.length; ++i) {
        let e = errors.getOr(i, new Pair("", ""));
        if (e.key == field) { out.add(e.value); }
      }
      out.toList()
    }

## button/1

`class` defaults to `["btn", "mg-btn ghost"]`, or `["btn", "mg-btn"]` for
`variant = "primary"`. With `href` it is an `<a>` (`navigate` and `patch` were
live-navigation variants of `href`: pass the path as `href`), else a
`<button>`. `rest` is the other attributes, already escaped.

    export let cButton(
      href: String?,
      variant: String?,
      cls: String?,
      rest: String,
      inner: List<AnyValue>,
    ): List<AnyValue> {
      let variantClass = if (variant == "primary") { "mg-btn" } else { "mg-btn ghost" };
      let klass = if (cls != null) { cls } else { "btn ${variantClass}" };
      if (href != null) {
        h("a", "${attr("class", klass)}${attr("href", href)}${rest}", [inner])
      } else {
        h("button", "${attr("class", klass)}${rest}", [inner])
      }
    }

## input/1

The assigns of `input/1`, with the Phoenix defaults. Make one with
`cInputSpec(name)`, set what differs, pass it to `cInput`.

* `kind` is the `type` (`text`, `textarea`, `select`, `checkbox`, `hidden`,
  `email`, `password`, ...).
* `value` is the current value; `values` the selected ones of a `multiple`
  select; `options` is `(label, value)` pairs.
* `checked` is the checkbox flag; when `checkedSet` is false it follows the
  value (`value == "true"`), as `normalize_value("checkbox", ...)` did.
* `errors` are already-translated messages, to be shown only if the caller
  decided the field was used (`used_input?`).
* `cls` replaces the default input class; `rest` is extra raw attributes;
  `disabled` and `form` feed the checkbox's hidden twin as in the HEEx.

<!-- -->

    export class CInputSpec(public name: String) {
      public var kind: String = "text";
      public var id: String? = null;
      public var label: String? = null;
      public var value: String? = null;
      public var values: List<String> = [];
      public var errors: List<String> = [];
      public var checked: Boolean = false;
      public var checkedSet: Boolean = false;
      public var prompt: String? = null;
      public var options: List<Pair<String, String>> = [];
      public var multiple: Boolean = false;
      public var cls: String? = null;
      public var rest: String = "";
      public var disabled: Boolean = false;
      public var form: String? = null;
    }

    export let cInputSpec(name: String): CInputSpec {
      new CInputSpec(name)
    }

    let wcErrorBorder(errors: List<String>): String? {
      if (errors.length > 0) { "border-[var(--mg-accent)]" } else { null }
    }

`normalize_value("textarea", v)`: a leading newline is doubled, because the
browser drops the first one.

    let wcTextareaValue(v: String?): String {
      if (v != null) {
        if (wcStartsWith(v, "\n")) { "\n${v}" } else { v }
      } else { "" }
    }

    let wcOption(label: String, value: String, selected: Boolean): List<AnyValue> {
      h("option", "${attr("value", value)}${if (selected) { " selected" } else { "" }}", htext(label))
    }

    let wcIsSelected(spec: CInputSpec, value: String): Boolean {
      if (spec.multiple) {
        var found = false;
        for (var i = 0; i < spec.values.length; ++i) {
          if (spec.values.getOr(i, "") == value) { found = true; }
        }
        found
      } else {
        let v = spec.value;
        v != null && v == value
      }
    }

    export let cInput(spec: CInputSpec): List<AnyValue> {
      let id = spec.id;
      let label = spec.label;
      let labelSpan: List<AnyValue> = if (label != null) {
        h("span", attr("class", "mg-label block mb-1.5"), htext(label))
      } else { [] };
      if (spec.kind == "hidden") {
        return hv("input", "${attr("type", "hidden")}${attr("id", id)}${attr("name", spec.name)}${attr("value", spec.value)}${spec.rest}");
      }
      if (spec.kind == "checkbox") {
        let isChecked = if (spec.checkedSet) { spec.checked } else {
          let v = spec.value;
          v != null && v == "true"
        };
        let klass = wcOr(spec.cls, "checkbox checkbox-sm");
        return h("div", attr("class", "mg-field"), [
          h("label", attr("for", id), [
            hv("input", "${attr("type", "hidden")}${attr("name", spec.name)}${attr("value", "false")}${if (spec.disabled) { " disabled" } else { "" }}${attr("form", spec.form)}"),
            h("span", attr("class", "label"), [
              hv("input", "${attr("type", "checkbox")}${attr("id", id)}${attr("name", spec.name)}${attr("value", "true")}${if (isChecked) { " checked" } else { "" }}${attr("class", klass)}${spec.rest}"),
              htext(wcOr(label, "")),
            ]),
          ]),
          wcErrors(spec.errors),
        ]);
      }
      if (spec.kind == "select") {
        let klass = classes([wcOr(spec.cls, "mg-select"), wcErrorBorder(spec.errors)]);
        let promptOpt: List<AnyValue> = if (spec.prompt != null) { wcOption(wcOr(spec.prompt, ""), "", false) } else { [] };
        let opts = spec.options.map { (o: Pair<String, String>): List<AnyValue> =>
          wcOption(o.key, o.value, wcIsSelected(spec, o.value))
        };
        return h("div", attr("class", "mg-field"), [
          h("label", attr("for", id), [
            labelSpan,
            h("select", "${attr("id", id)}${attr("name", spec.name)}${attr("class", klass)}${if (spec.multiple) { " multiple" } else { "" }}${spec.rest}", [promptOpt, opts]),
          ]),
          wcErrors(spec.errors),
        ]);
      }
      if (spec.kind == "textarea") {
        let klass = classes([wcOr(spec.cls, "mg-textarea"), wcErrorBorder(spec.errors)]);
        return h("div", attr("class", "mg-field"), [
          h("label", attr("for", id), [
            labelSpan,
            h("textarea", "${attr("id", id)}${attr("name", spec.name)}${attr("class", klass)}${spec.rest}", htext(wcTextareaValue(spec.value))),
          ]),
          wcErrors(spec.errors),
        ]);
      }
      let klass = classes([wcOr(spec.cls, "mg-input"), wcErrorBorder(spec.errors)]);
      h("div", attr("class", "mg-field"), [
        h("label", attr("for", id), [
          labelSpan,
          hv("input", "${attr("type", spec.kind)}${attr("name", spec.name)}${attr("id", id)}${attr("value", spec.value)}${attr("class", klass)}${spec.rest}"),
        ]),
        wcErrors(spec.errors),
      ])
    }

A text input with a label and errors: the common case in one call.

    export let cTextInput(name: String, id: String, label: String?, kind: String, value: String?, errors: List<String>): List<AnyValue> {
      let spec = cInputSpec(name);
      spec.kind = kind;
      spec.id = id;
      spec.label = label;
      spec.value = value;
      spec.errors = errors;
      cInput(spec)
    }

## header/1

`subtitle` and `actions` are slots; an empty list is an absent slot.

    export let cHeader(inner: List<AnyValue>, subtitle: List<AnyValue>, actions: List<AnyValue>): List<AnyValue> {
      let hasActions = hjoin(actions) != "";
      let hasSubtitle = hjoin(subtitle) != "";
      let sub: List<AnyValue> = if (hasSubtitle) {
        h("p", attr("class", "text-sm text-base-content/70"), [subtitle])
      } else { [] };
      h("header", attr("class", classes([if (hasActions) { "flex items-center justify-between gap-6" } else { null }, "pb-4"])), [
        h("div", "", [
          h("h1", attr("class", "text-lg font-semibold leading-8"), [inner]),
          sub,
        ]),
        h("div", attr("class", "flex-none"), [actions]),
      ])
    }

## table/1

`labels` are the column headings. A row is a `CRow`: its `id` (the `row_id`
function's result), `cells` (one tree per column), `actions` (one tree per
action slot; the actions column exists when `hasActions`), and `click` (the
`row_click` value, a `phx-click` event name). There are no streams: the page
re-renders the whole table.

    export class CRow(
      public id: String?,
      public cells: List<List<AnyValue>>,
      public actions: List<List<AnyValue>>,
      public click: String?,
    ) {}

    export let cTable(id: String, labels: List<String>, rows: List<CRow>, hasActions: Boolean): List<AnyValue> {
      let heads = labels.map { (l: String): List<AnyValue> => h("th", "", htext(l)) };
      let actionHead: List<AnyValue> = if (hasActions) {
        h("th", "", h("span", attr("class", "sr-only"), htext("Actions")))
      } else { [] };
      let body = rows.map { (r: CRow): List<AnyValue> =>
        let tds = r.cells.map { (c: List<AnyValue>): List<AnyValue> =>
          let click = r.click;
          h("td", "${if (click != null) { attr("phx-click", click) } else { "" }}${if (click != null) { attr("class", "hover:cursor-pointer") } else { "" }}", [c])
        };
        let actionCell: List<AnyValue> = if (hasActions) {
          h("td", attr("class", "w-0 font-semibold"), h("div", attr("class", "flex gap-4"), [r.actions]))
        } else { [] };
        h("tr", attr("id", r.id), [tds, actionCell])
      };
      h("table", attr("class", "table table-zebra"), [
        h("thead", "", h("tr", "", [heads, actionHead])),
        h("tbody", attr("id", id), [body]),
      ])
    }

## list/1

Each item is a `(title, content)` pair.

    export let cList(items: List<Pair<String, List<AnyValue>>>): List<AnyValue> {
      h("ul", attr("class", "list"), items.map { (it: Pair<String, List<AnyValue>>): List<AnyValue> =>
        h("li", attr("class", "list-row"),
          h("div", attr("class", "list-col-grow"), [
            h("div", attr("class", "font-bold"), htext(it.key)),
            h("div", "", [it.value]),
          ]))
      })
    }

## mutter/1

The wait indicator. The first line is rendered; the `Rotate` hook cycles the
rest in the browser. `phx-update="ignore"` keeps a morph from resetting the
text mid-rotation. The id is a hash of the lines, so the same lines give the
same id (Phoenix used `:erlang.phash2`; this is a different hash with the same
property). `lines` empty leaves only the dots. The Phoenix hook name was
`.Rotate`; `blimp.js` registers `Rotate`.

    let wcHashLines(lines: List<String>): Int {
      var acc = 7;
      for (var i = 0; i < lines.length; ++i) {
        let s = lines.getOr(i, "");
        var j = String.begin;
        while (s.hasIndex(j)) {
          acc = (acc * 31 + s[j]) % 1000000007;
          j = s.next(j);
        }
        acc = (acc * 31 + 10) % 1000000007;
      }
      acc
    }

    let wcLinesJson(lines: List<String>): String {
      let p = new JsonTextProducer(NullInterchangeContext.instance);
      p.startArray();
      for (var i = 0; i < lines.length; ++i) { p.stringValue(lines.getOr(i, "")); }
      p.endArray();
      p.toJsonString() orelse panic()
    }

    export let cMutter(lines: List<String>, label: String, cls: String?): List<AnyValue> {
      let first = lines.getOr(0, "");
      let span: List<AnyValue> = if (lines.length > 0) {
        h("span", "${attr("id", "mutter-${wcHashLines(lines).toString()}")}${attr("class", "mg-mutter")}${attr("phx-hook", "Rotate")}${attr("phx-update", "ignore")}${attr("data-lines", wcLinesJson(lines))}", htext(first))
      } else { [] };
      h("div", "${attr("class", classes(["mg-dots", cls]))}${attr("aria-label", label)}", [
        span,
        h("span", attr("class", "mg-dot"), []),
        h("span", "${attr("class", "mg-dot")}${attr("style", "animation-delay:.18s")}", []),
        h("span", "${attr("class", "mg-dot")}${attr("style", "animation-delay:.36s")}", []),
      ])
    }

## The theme toggle

`Layouts.theme_toggle`. No page renders it (the app layout does not include it,
and the public spec says nothing in the UI lets a visitor change theme), but it
is here for a page that wants it. `blimp.js` turns a click on `[data-phx-theme]`
into the `phx:set-theme` event the inline script in the head listens for.

    let wcThemeButton(theme: String, icon: String): List<AnyValue> {
      h("button", "${attr("class", "flex p-2 cursor-pointer w-1/3")}${attr("data-phx-theme", theme)}",
        cIconClass(icon, "size-4 opacity-75 hover:opacity-100"))
    }

    export let cThemeToggle(): List<AnyValue> {
      h("div", attr("class", "card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full"), [
        h("div", attr("class", "absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]"), []),
        wcThemeButton("system", "hero-computer-desktop-micro"),
        wcThemeButton("light", "hero-sun-micro"),
        wcThemeButton("dark", "hero-moon-micro"),
      ])
    }
