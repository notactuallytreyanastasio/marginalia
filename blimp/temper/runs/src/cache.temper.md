# Cache: answers that are the same for every visitor

`Marginalia.Cache` held terms in an ETS table owned by a GenServer, with a
five-minute TTL as the backstop for forgotten invalidations. A forked child
per request has no process to hold a table, so the cache is a table:

`cache(key TEXT PRIMARY KEY, value TEXT, expires_at TEXT)`

`db` owns the schema and this table is not in it, so it is created lazily:
every function here begins with `CREATE TABLE IF NOT EXISTS`, which on an
existing table reads the schema and writes nothing. The value is text; a
caller that caches a list serialises it (JSON) and parses it on the way out,
since nothing survives between requests in memory.

Expiry is compared in SQL against `strftime('%Y-%m-%d %H:%M:%S', 'now')`, so
the same clock writes and reads it, and `ttlSeconds` of 0 is already expired:
`cachePut(db, k, v, 0)` followed by `cacheGet` answers null.

    let { Db } = import("db/src");

The Elixir default, 5 minutes.

    export let cacheDefaultTtl(): Int { 300 }

    let cacheEnsure(db: Db): Void throws Bubble {
      db.script("CREATE TABLE IF NOT EXISTS cache (key TEXT PRIMARY KEY, value TEXT, expires_at TEXT)");
    }

`Cache.peek/2`: the value if there is a fresh entry, else null. A cached
empty string is a value, not a miss. Never computes anything.

    export let cacheGet(db: Db, key: String): String? throws Bubble {
      cacheEnsure(db);
      let row = db.one(
        "SELECT value FROM cache WHERE key = $1 AND expires_at > strftime('%Y-%m-%d %H:%M:%S', 'now')",
        [key],
      );
      if (row == null) { null } else { row.strOrNull("value") }
    }

Store `value` for `ttlSeconds`, replacing any entry.

    export let cachePut(db: Db, key: String, value: String, ttlSeconds: Int): Void throws Bubble {
      cacheEnsure(db);
      db.exec(
        "INSERT INTO cache (key, value, expires_at) VALUES ($1, $2, strftime('%Y-%m-%d %H:%M:%S', 'now', '+' || $3 || ' seconds')) ON CONFLICT(key) DO UPDATE SET value = $2, expires_at = strftime('%Y-%m-%d %H:%M:%S', 'now', '+' || $3 || ' seconds')",
        [key, value, ttlSeconds.toString()],
      );
    }

`Cache.invalidate/1`: throw one away. Called from every path that can change
the answer.

    export let cacheInvalidate(db: Db, key: String): Void throws Bubble {
      cacheEnsure(db);
      db.exec("DELETE FROM cache WHERE key = $1", [key]);
    }

`Cache.invalidate_all/0`.

    export let cacheInvalidateAll(db: Db): Void throws Bubble {
      cacheEnsure(db);
      db.exec("DELETE FROM cache", []);
    }
