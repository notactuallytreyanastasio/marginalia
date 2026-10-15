# Versions: PubSub as a counter

Phoenix.PubSub told a LiveView that something changed. There is no process to
tell here, so a writer bumps a counter in `versions(topic, n)` and a page that
is waiting polls the sum of the topics it cares about; when the sum differs
from the one it rendered with, it re-fetches. A payload is never carried: the
Elixir receivers re-read the database on every message anyway.

    let { Db } = import("db/src");

## The topics

The topic strings are the Elixir PubSub topics, so the port can be read
against the original. A caller that needs a topic builds it with the helpers
below instead of spelling the string.

- `work:<id>`: a work's read (status changes, section statuses, node counts,
  synthesis, weave, decision graph building and events). Bumped by
  `Analysis` and `DecisionGraph` wherever the Elixir broadcast on
  `Analysis.topic/1`.
- `link:<id>`: a link pair's progress (`start`, `reading`, `asking`,
  `checking`, `done`, `failed`).
- `run:<key>`: a run's `started`, `progress`, `done`, `crashed`. The Elixir
  topic was `run:` plus `inspect(key)` (`run:{:work, 5}`); the key is now a
  string such as `work:5`, so the topic is `run:work:5`.

Topics for stacks and folders passes are `run:<key>` too, because those went
through `Runs`.

    export let versionsWorkTopic(workId: Int): String { "work:${workId.toString()}" }

    export let versionsLinkTopic(linkId: Int): String { "link:${linkId.toString()}" }

    export let versionsRunTopic(key: String): String { "run:${key}" }

## Bump, read, sum

`versionsBump` is an upsert, so the first bump of a topic creates its row with
n at one. It is one statement, so two processes bumping at once both count.

    export let versionsBump(db: Db, topic: String): Void throws Bubble {
      db.exec(
        "INSERT INTO versions (topic, n) VALUES ($1, 1) ON CONFLICT(topic) DO UPDATE SET n = n + 1",
        [topic],
      );
    }

A topic never bumped is 0.

    export let versionsOf(db: Db, topic: String): Int throws Bubble {
      let row = db.one("SELECT n FROM versions WHERE topic = $1", [topic]);
      if (row == null) { 0 } else { row.int("n") }
    }

The sum over several topics, which is what `GET /watch?topics=a,b` answers.
No topics, or none ever bumped, is 0. A sum only ever grows, so a change on
any topic changes it.

    export let versionsSum(db: Db, topics: List<String>): Int throws Bubble {
      if (topics.length == 0) { return 0; }
      let marks = new ListBuilder<String>();
      let params = new ListBuilder<String?>();
      var i = 0;
      while (i < topics.length) {
        marks.add("\$${(i + 1).toString()}");
        params.add(topics[i]);
        i += 1;
      }
      let list = marks.toList().join(",") { (m: String): String => m };
      let row = db.one("SELECT COALESCE(SUM(n), 0) AS total FROM versions WHERE topic IN (${list})", params.toList());
      if (row == null) { 0 } else { row.int("total") }
    }
