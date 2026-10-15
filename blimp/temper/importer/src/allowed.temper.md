# What may be fetched

`Marginalia.Import.allowed/1`: the security boundary of the page importer. The
URL comes from whoever is using the site, and the server is the one that makes
the request, from inside the network, with whatever the network trusts. So this
refuses anything that is not plain http(s) to a public host: no `file:`, no
`localhost`, no link-local address, no private range. A boundary with no test on
it is a wish; the tests are in `importer_test.temper.md`.

There is one thing the Elixir did that this cannot: resolve a name. `inet:getaddrs`
turned `evil.example.com` into the address it points at and refused it when that
was `127.0.0.1`, or when it did not resolve at all. The interpreter has no
resolver, so a name is judged by its spelling: the loopback and internal names
below, and the suffixes `.local`, `.internal`, `.localhost`, `.localdomain`,
`.lan` and `.home.arpa`. A public-looking name that points at a private address
gets through. So does a redirect that lands on one: the redirect target is not
re-checked, here or in the Elixir.

## The address

`uri` is the address as it will be fetched: the scheme lower-cased, the rest as
typed (trimmed). `host` is the host without brackets or port, lower-cased.

    export class ImporterAllowed(
      public uri: String?,
      public host: String?,
      public error: ImporterError?,
    ) {}

    let importerRefuse(kind: String): ImporterAllowed {
      new ImporterAllowed(null, null, importerError(kind))
    }

## Taking a URL apart

RFC 3986's `^(([^:/?#]+):)?(//([^/?#]*))?`: a scheme, then an authority.

    class ImporterParts(public scheme: String?, public host: String?, public rest: String) {}

    let importerIsDelimiter(cp: Int): Boolean { cp == 47 || cp == 63 || cp == 35 }

    let importerHostOf(authority: String): String {
      let parts = authority.split("@");
      let hostPort = parts[parts.length - 1];
      let cps = importerCps(hostPort);
      if (cps.length > 0 && cps[0] == 91) {
        var close = 1;
        while (close < cps.length && cps[close] != 93) { close += 1; }
        return importerSlice(cps, 1, close);
      }
      importerLower(hostPort.split(":")[0])
    }

    let importerSplitUri(text: String): ImporterParts {
      let cps = importerCps(text);
      var colon = -1;
      var i = 0;
      var scanning = true;
      while (scanning && i < cps.length) {
        let c = cps[i];
        if (c == 58) {
          colon = i;
          scanning = false;
        } else if (importerIsDelimiter(c)) {
          scanning = false;
        } else {
          i += 1;
        }
      }
      let scheme = if (colon > 0) { importerLower(importerSlice(cps, 0, colon)) } else { null };
      let after = if (colon > 0) { colon + 1 } else { 0 };
      if (after + 1 < cps.length && cps[after] == 47 && cps[after + 1] == 47) {
        var end = after + 2;
        while (end < cps.length && !importerIsDelimiter(cps[end])) { end += 1; }
        new ImporterParts(scheme, importerHostOf(importerSlice(cps, after + 2, end)), "")
      } else {
        new ImporterParts(scheme, null, "")
      }
    }

## Reserved addresses

IPv4: `127.*`, `10.*`, `192.168.*`, `169.254.*`, `172.16-31.*`, `0.*`,
`100.64-127.*` (carrier-grade NAT), and a first octet of 224 or more.

    let importerReserved4(a: Int, b: Int): Boolean {
      a == 127 || a == 10 || (a == 192 && b == 168) || (a == 169 && b == 254) ||
        (a == 172 && b >= 16 && b <= 31) || a == 0 || (a == 100 && b >= 64 && b <= 127) || a >= 224
    }

A dotted quad: four decimal numbers of one to three digits with no leading
zero, each at most 255. Null otherwise.

    let importerOrMinus(n: Int?): Int { if (n != null) { n } else { -1 } }

    let importerParseV4(host: String): List<Int> {
      let parts = host.split(".");
      if (parts.length != 4) { return []; }
      let out = new ListBuilder<Int>();
      var i = 0;
      while (i < 4) {
        let p = parts[i];
        let n = importerCpCount(p);
        if (n < 1 || n > 3) { return []; }
        let cps = importerCps(p);
        var j = 0;
        while (j < n) {
          if (!importerIsDigit(cps[j])) { return []; }
          j += 1;
        }
        if (n > 1 && cps[0] == 48) { return []; }
        let v = importerOrMinus(importerParseInt(p));
        if (v < 0 || v > 255) { return []; }
        out.add(v);
        i += 1;
      }
      out.toList()
    }

A host made only of the pieces `inet_aton` reads as numbers: decimal runs and
`0x` hex runs, one to four of them. `2130706433`, `0x7f.1`, `127.1` and
`0177.0.0.1` are all 127.0.0.1 to a resolver and none of them is a dotted quad;
they are refused rather than worked out.

    let importerIsHexDigit(cp: Int): Boolean {
      importerIsDigit(cp) || (cp >= 65 && cp <= 70) || (cp >= 97 && cp <= 102)
    }

    let importerNumericLabel(label: String): Boolean {
      let cps = importerCps(label);
      if (cps.length == 0) { return false; }
      var allDigits = true;
      var i = 0;
      while (i < cps.length) {
        if (!importerIsDigit(cps[i])) { allDigits = false; }
        i += 1;
      }
      if (allDigits) { return true; }
      if (cps.length >= 3 && cps[0] == 48 && (cps[1] == 120 || cps[1] == 88)) {
        var j = 2;
        while (j < cps.length) {
          if (!importerIsHexDigit(cps[j])) { return false; }
          j += 1;
        }
        return true;
      }
      false
    }

    let importerNumericHost(host: String): Boolean {
      let labels = host.split(".");
      if (labels.length > 4) { return false; }
      var i = 0;
      while (i < labels.length) {
        if (!importerNumericLabel(labels[i])) { return false; }
        i += 1;
      }
      true
    }

IPv6 as eight groups. `::` stands for the zeros in the middle, and the last
two groups may be written as a dotted quad. Null when it is not an address.

    let importerHexValue(label: String): Int {
      let cps = importerCps(label);
      if (cps.length < 1 || cps.length > 4) { return -1; }
      var n = 0;
      var i = 0;
      while (i < cps.length) {
        let c = cps[i];
        var d = -1;
        if (c >= 48 && c <= 57) { d = c - 48; }
        if (c >= 65 && c <= 70) { d = c - 55; }
        if (c >= 97 && c <= 102) { d = c - 87; }
        if (d < 0) { return -1; }
        n = n * 16 + d;
        i += 1;
      }
      n
    }

    class ImporterGroups(public ok: Boolean, public groups: List<Int>) {}

    let importerBadGroups(): ImporterGroups { new ImporterGroups(false, []) }

    let importerV6Groups(side: String, last: Boolean): ImporterGroups {
      if (side.isEmpty) { return new ImporterGroups(true, []); }
      let labels = side.split(":");
      let out = new ListBuilder<Int>();
      var i = 0;
      while (i < labels.length) {
        let label = labels[i];
        if (last && i == labels.length - 1 && importerContains(label, ".")) {
          let q = importerParseV4(label);
          if (q.length != 4) { return importerBadGroups(); }
          out.add(q[0] * 256 + q[1]);
          out.add(q[2] * 256 + q[3]);
        } else {
          let v = importerHexValue(label);
          if (v < 0) { return importerBadGroups(); }
          out.add(v);
        }
        i += 1;
      }
      new ImporterGroups(true, out.toList())
    }

Eight groups, or an empty list when `host` is not an address.

    let importerParseV6(host: String): List<Int> {
      let halves = host.split("::");
      if (halves.length > 2) { return []; }
      if (halves.length == 1) {
        let all = importerV6Groups(halves[0], true);
        if (all.ok && all.groups.length == 8) { return all.groups; }
        return [];
      }
      let left = importerV6Groups(halves[0], false);
      let right = importerV6Groups(halves[1], true);
      if (!left.ok || !right.ok) { return []; }
      if (left.groups.length + right.groups.length > 7) { return []; }
      let out = new ListBuilder<Int>();
      var i = 0;
      while (i < left.groups.length) { out.add(left.groups[i]); i += 1; }
      var zeros = 8 - left.groups.length - right.groups.length;
      while (zeros > 0) { out.add(0); zeros -= 1; }
      var j = 0;
      while (j < right.groups.length) { out.add(right.groups[j]); j += 1; }
      out.toList()
    }

Loopback, link-local and unique-local, as the Elixir had them; and the ones it
missed: the unspecified address, multicast, and the three ways of writing an
IPv4 address inside an IPv6 one (`::ffff:127.0.0.1`, `::127.0.0.1`,
`64:ff9b::127.0.0.1`, `2002:7f00:1::`), which it let through.

    let importerReserved6(g: List<Int>): Boolean {
      if (g[0] >= 0xFC00 && g[0] <= 0xFDFF) { return true; }
      if (g[0] >= 0xFE80 && g[0] <= 0xFEBF) { return true; }
      if (g[0] >= 0xFF00) { return true; }
      var zeros = true;
      var i = 0;
      while (i < 6) {
        if (g[i] != 0) { zeros = false; }
        i += 1;
      }
      if (zeros) { return true; }
      if (g[0] == 0 && g[1] == 0 && g[2] == 0 && g[3] == 0 && g[4] == 0 && g[5] == 0xFFFF) {
        return importerReserved4(g[6] / 256, g[6] % 256);
      }
      if (g[0] == 0x64 && g[1] == 0xFF9B && g[2] == 0 && g[3] == 0 && g[4] == 0 && g[5] == 0) {
        return importerReserved4(g[6] / 256, g[6] % 256);
      }
      if (g[0] == 0x2002) { return importerReserved4(g[1] / 256, g[1] % 256); }
      false
    }

## Names

    let importerHostNames = [
      "localhost", "0.0.0.0", "broadcasthost", "localhost.localdomain",
      "ip6-localhost", "ip6-loopback", "localhost4", "localhost6",
    ];

    let importerHostSuffixes = [".localhost", ".local", ".internal", ".localdomain", ".lan", ".home.arpa"];

    let importerPrivate(host: String): Boolean {
      var h = importerLower(host);
      while (importerEndsWith(h, ".")) { h = importerTake(h, importerGraphemes(h) - 1); }
      if (importerIsOneOf(h, importerHostNames)) { return true; }
      var i = 0;
      while (i < importerHostSuffixes.length) {
        if (importerEndsWith(h, importerHostSuffixes[i])) { return true; }
        i += 1;
      }
      if (importerContains(h, ":")) {
        let g = importerParseV6(h);
        if (g.length != 8) { return true; }
        return importerReserved6(g);
      }
      if (importerNumericHost(h)) {
        let q = importerParseV4(h);
        if (q.length != 4) { return true; }
        return importerReserved4(q[0], q[1]);
      }
      false
    }

## allowed

Non-string is `bad_url`. The scheme must be `http` or `https`, the host must
be there, and it must not be private. `{:ok, uri}` is `uri` set and `error`
null.

    export let importerAllowed(url: String?): ImporterAllowed {
      if (url != null) {
        importerAllowedText(url)
      } else {
        importerRefuse("bad_url")
      }
    }

    let importerAllowedText(url: String): ImporterAllowed {
      let text = importerTrim(url);
      let parts = importerSplitUri(text);
      let scheme = importerOrEmpty(parts.scheme);
      if (scheme != "http" && scheme != "https") { return importerRefuse("bad_scheme"); }
      let host = importerOrEmpty(parts.host);
      if (parts.host == null || host.isEmpty) { return importerRefuse("no_host"); }
      if (importerPrivate(host)) { return importerRefuse("private_address"); }
      let after = importerAfterFirst(text, ":");
      new ImporterAllowed("${scheme}:${importerOrEmpty(after)}", host, null)
    }
