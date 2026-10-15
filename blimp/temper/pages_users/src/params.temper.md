# Form parameters

An event arrives as a JSON object. The client runtime posts a form as flat
keys (`"user[email]": "a@b"`, what `FormData` gives), a hand-written client or
a test may send Phoenix's nested shape (`"user": {"email": "a@b"}`). Both give
the same `Map` of field to value here.

Every top-level name in this library is shared by all of its files, so the
private helpers start with `pu`.

    let { JsonSyntaxTree, JsonObject, JsonString, JsonArray } = import("std/json");
    let { AccountsError, accountsErrorsOn } = import("accounts/src");

    let puStartsWith(s: String, prefix: String): Boolean {
      if (s == "" || prefix == "") { return false; }
      let parts = s.split(prefix);
      parts.length > 1 && parts.getOr(0, "x") == ""
    }

    let puContains(xs: List<String>, x: String): Boolean {
      var found = false;
      for (var i = 0; i < xs.length; ++i) {
        if (xs.getOr(i, "") == x) { found = true; }
      }
      found
    }

`user[email]` to `email`; anything else to the empty string.

    let puFieldOf(key: String): String {
      if (puStartsWith(key, "user[")) {
        key.split("user[").getOr(1, "").split("]").getOr(0, "")
      } else { "" }
    }

The fields of `user`: flat `user[x]` keys first, then the nested object, which
wins when both are present.

    export let pagesUsersParams(payload: JsonObject): Map<String, String> {
      let out = new MapBuilder<String, String>();
      let keys = payload.properties.keys();
      for (var i = 0; i < keys.length; ++i) {
        let k = keys.getOr(i, "");
        let field = puFieldOf(k);
        if (field != "") {
          let v = payload.propertyValueOrNull(k);
          if (v is JsonString) { out.set(field, v.content); }
        }
      }
      let nested = payload.propertyValueOrNull("user");
      if (nested is JsonObject) {
        let nks = nested.properties.keys();
        for (var j = 0; j < nks.length; ++j) {
          let k = nks.getOr(j, "");
          let v = nested.propertyValueOrNull(k);
          if (v is JsonString) { out.set(k, v.content); }
        }
      }
      out.toMap()
    }

The field the change event came from (`_target`), or the empty string.

    export let pagesUsersTarget(payload: JsonObject): String {
      let t = payload.propertyValueOrNull("_target");
      if (t is JsonArray) {
        let first = t.elements.getOr(0, t);
        if (first is JsonString) { puFieldOf(first.content) } else { "" }
      } else { "" }
    }

## Which fields have been used

LiveView shows an error under a field only once the visitor has used it. A
submit uses every field that was sent. A change uses the field that changed and
every field that already holds something, so typing an email does not scold
the empty password under it. (Phoenix kept a per-field flag in the socket; the
client here sends no such flag.)

    export let pagesUsersUsed(params: Map<String, String>, target: String, submit: Boolean): List<String> {
      let out = new ListBuilder<String>();
      let keys = params.keys();
      for (var i = 0; i < keys.length; ++i) {
        let k = keys.getOr(i, "");
        if (submit || params.getOr(k, "") != "" || k == target) { out.add(k); }
      }
      out.toList()
    }

The messages on `field`, if the field was used.

    export let pagesUsersShown(errors: List<AccountsError>, used: List<String>, field: String): List<String> {
      if (puContains(used, field)) { accountsErrorsOn(errors, field) } else { [] }
    }
