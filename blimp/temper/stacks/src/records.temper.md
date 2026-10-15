# The records

`Stacks.Step` and `Stacks.Story`, field for field, with a `fromRow` each and
a `<name>Columns` SELECT list. The JSON columns are decoded into typed
classes: `excerpts` into `StackExcerpt`, `movements` into `StoryMovement`.
The array columns (`requires`, `dropped`, `deep_dropped`, `uncovered`) are
JSON text in SQLite and read as `List<Int>` / `List<String>`; a NULL one is
`[]`, as the Ecto defaults were.

    let { DbRow } = import("db/src");
    let { Work } = import("works/src");
    let {
      JsonSyntaxTree, JsonObject, JsonArray, JsonString, JsonTextProducer, parseJson,
    } = import("std/json");

## Excerpt

`{"caption", "text"}`: a passage of the document, shown with a caption.

    export class StackExcerpt(public caption: String, public text: String) {}

    let stacksStringOf(t: JsonSyntaxTree?): String {
      if (t is JsonString) { t.content } else { "" }
    }

    let stacksExcerptsOf(text: String?): List<StackExcerpt> throws Bubble {
      let out = new ListBuilder<StackExcerpt>();
      if (text != null) {
        let tree = parseJson(text);
        if (tree is JsonArray) {
          for (let item of tree.elements) {
            if (item is JsonObject) {
              out.add(new StackExcerpt(
                stacksStringOf(item.propertyValueOrNull("caption")),
                stacksStringOf(item.propertyValueOrNull("text")),
              ));
            }
          }
        }
      }
      out.toList()
    }

    let stacksExcerptsJson(xs: List<StackExcerpt>): String throws Bubble {
      let p = new JsonTextProducer();
      p.startArray();
      for (let x of xs) {
        p.startObject();
        p.objectKey("caption");
        p.stringValue(x.caption);
        p.objectKey("text");
        p.stringValue(x.text);
        p.endObject();
      }
      p.endArray();
      p.toJsonString()
    }

## Step

One document of a stack, read forwards. `capability` and `lesson` are
`String?` because Ecto's `cast` stores the empty string as NULL, and a step
whose model answer was empty has none. `work` is the preloaded work, set by
the list and get functions; `fromRow` leaves it `null`.

    export class StackStep(
      public id: Int,
      public folderId: Int,
      public workId: Int,
      public ordinal: Int,
      public capability: String?,
      public requires: List<Int>,
      public lesson: String?,
      public pitfall: String?,
      public pitfallQuote: String?,
      public excerpts: List<StackExcerpt>,
      public fingerprint: String?,
      public dropped: List<String>,
      public mechanism: String?,
      public watchFor: String?,
      public revisedBy: Int?,
      public revision: String?,
      public revisionQuote: String?,
      public deepDropped: List<String>,
      public deepenedAt: String?,
      public insertedAt: String,
      public updatedAt: String,
    ) {
      public var work: Work? = null;

      public static fromRow(row: DbRow): StackStep throws Bubble {
        new StackStep(
          row.int("id"),
          row.int("folder_id"),
          row.int("work_id"),
          row.int("ordinal"),
          row.strOrNull("capability"),
          row.intList("requires"),
          row.strOrNull("lesson"),
          row.strOrNull("pitfall"),
          row.strOrNull("pitfall_quote"),
          stacksExcerptsOf(row.strOrNull("excerpts")),
          row.strOrNull("fingerprint"),
          row.strList("dropped"),
          row.strOrNull("mechanism"),
          row.strOrNull("watch_for"),
          row.intOrNull("revised_by"),
          row.strOrNull("revision"),
          row.strOrNull("revision_quote"),
          row.strList("deep_dropped"),
          row.strOrNull("deepened_at"),
          row.str("inserted_at"),
          row.str("updated_at"),
        )
      }
    }

    export let stacksStepColumns = "id, folder_id, work_id, ordinal, capability, requires, lesson, pitfall, pitfall_quote, excerpts, fingerprint, dropped, mechanism, watch_for, revised_by, revision, revision_quote, deep_dropped, deepened_at, inserted_at, updated_at";

An unsaved step, as the Elixir tests build `%Step{ordinal: n, capability: ...}`:
for the validators, which read only the ordinal, the capability, the lesson
and the pitfall.

    export let stacksSketch(ordinal: Int, capability: String?, lesson: String?, pitfall: String?): StackStep {
      new StackStep(
        0, 0, 0, ordinal, capability, [], lesson, pitfall, null, [], null, [],
        null, null, null, null, null, [], null, "", "",
      )
    }

## Story

One movement of the telling: `{"heading", "prose", "steps", "turn"}`. A stored
movement without a `turn` (or with a null one) has the empty turn.

    export class StoryMovement(
      public heading: String,
      public prose: String,
      public steps: List<Int>,
      public turn: String,
    ) {}

    let stacksIntsOf(t: JsonSyntaxTree?): List<Int> {
      let out = new ListBuilder<Int>();
      if (t is JsonArray) {
        for (let x of t.elements) {
          let n = stacksAsInt(x);
          if (n != null) { out.add(n); }
        }
      }
      out.toList()
    }

    let stacksMovementsOf(text: String?): List<StoryMovement> throws Bubble {
      let out = new ListBuilder<StoryMovement>();
      if (text != null) {
        let tree = parseJson(text);
        if (tree is JsonArray) {
          for (let item of tree.elements) {
            if (item is JsonObject) {
              out.add(new StoryMovement(
                stacksStringOf(item.propertyValueOrNull("heading")),
                stacksStringOf(item.propertyValueOrNull("prose")),
                stacksIntsOf(item.propertyValueOrNull("steps")),
                stacksStringOf(item.propertyValueOrNull("turn")),
              ));
            }
          }
        }
      }
      out.toList()
    }

    export let stacksMovementsJson(xs: List<StoryMovement>): String throws Bubble {
      let p = new JsonTextProducer();
      p.startArray();
      for (let m of xs) {
        p.startObject();
        p.objectKey("heading");
        p.stringValue(m.heading);
        p.objectKey("prose");
        p.stringValue(m.prose);
        p.objectKey("steps");
        p.startArray();
        for (let n of m.steps) { p.int32Value(n); }
        p.endArray();
        p.objectKey("turn");
        p.stringValue(m.turn);
        p.endObject();
      }
      p.endArray();
      p.toJsonString()
    }

The longform telling of a stack. `uncovered` is the steps no part carries;
`dropped` is what the validator threw out and why, and the page renders it.

    export class StackStory(
      public id: Int,
      public folderId: Int,
      public title: String?,
      public opening: String?,
      public movements: List<StoryMovement>,
      public closing: String?,
      public uncovered: List<Int>,
      public dropped: List<String>,
      public fingerprint: String?,
      public insertedAt: String,
      public updatedAt: String,
    ) {
      public static fromRow(row: DbRow): StackStory throws Bubble {
        new StackStory(
          row.int("id"),
          row.int("folder_id"),
          row.strOrNull("title"),
          row.strOrNull("opening"),
          stacksMovementsOf(row.strOrNull("movements")),
          row.strOrNull("closing"),
          row.intList("uncovered"),
          row.strList("dropped"),
          row.strOrNull("fingerprint"),
          row.str("inserted_at"),
          row.str("updated_at"),
        )
      }

      /** Whether every step of the stack found a place in the telling. */
      public isComplete(): Boolean { uncovered.length == 0 }
    }

    export let stacksStoryColumns = "id, folder_id, title, opening, movements, closing, uncovered, dropped, fingerprint, inserted_at, updated_at";

An unsaved story, as `%Story{uncovered: [3]}` is in the tests.

    export let stacksSketchStory(uncovered: List<Int>): StackStory {
      new StackStory(0, 0, null, null, [], null, uncovered, [], null, "", "")
    }
