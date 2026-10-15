# Router

A route is a method, a pattern and a name. A pattern is `/`-separated
segments; a segment starting with `:` captures that path segment under that
name (`/works/:id/graph.json`). Literal segments match exactly.

    export class Route(public method: String, public pattern: String, public name: String) {}

    export class Match(public route: Route, public params: Map<String, String>) {}

The first route that matches wins, in list order, as Phoenix does. So the
caller lists `/stacks/new` before `/stacks/:id`, or `new` is captured as an
id. A trailing slash is not significant (`/works/` is `/works`); the root `/`
is the one path that is only a slash. A captured segment is never empty, and
is not decoded again: the path arrives decoded from `httpParse`.

    let segmentsOf(path: String): List<String> {
      let parts = path.split("/");
      let out = new ListBuilder<String>();
      for (var k = 0; k < parts.length; ++k) {
        let p = parts.getOr(k, "");
        if (p != "") { out.add(p); }
      }
      out.toList()
    }

A path with an empty segment in the middle (`/a//b`) is treated as `/a/b`; it
does not need to be rejected for routing, and a double slash cannot reach a
route that would treat it differently.

    let matchOne(route: Route, method: String, path: String): Match? {
      if (route.method != method) { return null; }
      let want = segmentsOf(route.pattern);
      let have = segmentsOf(path);
      if (want.length != have.length) { return null; }
      let params = new MapBuilder<String, String>();
      for (var k = 0; k < want.length; ++k) {
        let w = want.getOr(k, "");
        let h = have.getOr(k, "");
        if (startsWith(w, ":")) {
          params.set(splitOnce(w, ":").tail, h);
        } else if (w != h) {
          return null;
        }
      }
      new Match(route, params.toMap())
    }

    export let routeMatch(routes: List<Route>, method: String, path: String): Match? {
      for (var k = 0; k < routes.length; ++k) {
        let route = routes.getOr(k, new Route("", "", ""));
        let m = matchOne(route, method, path);
        if (m != null) { return m; }
      }
      null
    }
