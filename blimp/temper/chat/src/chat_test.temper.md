# Tests for persisted conversations

Ported from `chat_modes_test`, `quota_test`, the many-threads half of
`drawer_test` and the thread functions of `inline_thread_test` in
`notes/tests.md`, plus the rules the notes state for `Marginalia.Chat`.

    let { FieldError } = import("core/src");
    let { workParams, worksDeleteWork } = import("works/src");
    let { accountsOwnerEmail } = import("accounts/src");
    let { sysGraphemeLength } = import("sys/src");

    let firstError(errors: List<FieldError>): String {
      if (errors.length == 0) { "<none>" } else { "${errors[0].field} ${errors[0].message}" }
    }

    let setup(db: Db): Work throws Bubble {
      let me = makeUser(db, "a@example.com");
      makeWork(db, me, "W", "${repeated("word ", 400)}")
    }

## The modes

    test("there are three modes and read is the default") { test =>
      expectText(test, sysJoin(editorModeNames(), ","), "read,provoke,bounce");
      expectText(test, editorDefaultMode(), "read");
    }

    test("each mode has its own opener and stance") { test =>
      for (let m of editorModes()) {
        expectTrue(test, m.opener != "", "opener of ${m.id}");
        expectHas(test, m.stance, "MODE:");
      }
      expectTrue(test, editorMode("read").stance != editorMode("provoke").stance, "different");
      expectTrue(test, editorMode("provoke").stance != editorMode("bounce").stance, "different");
    }

The stances must not quietly license their way around the shared prompt's
refusal: `write (the|a|their) (next |new )?(scene|paragraph|sentence|line) for`.

    let licenses(text: String): Boolean {
      let low = text;
      var found = false;
      for (let det of ["the", "a", "their"]) {
        for (let adj of ["", "next ", "new "]) {
          for (let noun of ["scene", "paragraph", "sentence", "line"]) {
            if (hasText(low, "write ${det} ${adj}${noun} for")) { found = true; }
          }
        }
      }
      found
    }

    test("every mode still refuses to write the writer's prose") { test =>
      for (let m of editorModes()) {
        expectFalse(test, licenses(m.stance), "${m.id} licenses writing");
      }
      expectHas(test, editorMode("provoke").stance, "never write prose");
      expectHas(test, editorMode("bounce").stance, "not writing it for them");
    }

    test("an unknown mode falls back rather than crashing") { test =>
      expectText(test, editorMode("nonsense").id, "read");
      expectText(test, editorMode(null).id, "read");
      expectText(test, editorOpener("bounce"), "Tell me the idea. I'll hold it against the draft you actually wrote and tell you where it bends.");
      expectText(test, editorOpener(null), "I've read the whole draft. Ask me what's there — or what isn't.");
    }

    test("a conversation remembers the stance it was held in") { test =>
      let db = dbOpen(":memory:");
      let work = setup(db);
      let convo = newConvo(db, work, null);
      expectText(test, convo.mode, "read");
      let changed = chatSetMode(db, convo, "bounce").conversation;
      expectText(test, if (changed != null) { changed.mode } else { "<none>" }, "bounce");
      let latest = chatLatestConversation(db, work.id);
      expectText(test, if (latest != null) { latest.mode } else { "<none>" }, "bounce");
    }

    test("switching stance keeps the history") { test =>
      let db = dbOpen(":memory:");
      let work = setup(db);
      let convo = newConvo(db, work, null);
      chatAppend(db, convo.id, "user", "first question");
      let changed = chatSetMode(db, convo, "provoke").conversation;
      let history = chatHistory(db, convo.id);
      expectInt(test, history.length, 1);
      expectText(test, history[0].content, "first question");
      expectText(test, history[0].role, "user");
      expectText(test, if (changed != null) { changed.mode } else { "<none>" }, "provoke");
    }

    test("a junk mode cannot be stored on a conversation") { test =>
      let db = dbOpen(":memory:");
      let work = setup(db);
      let convo = newConvo(db, work, null);
      let r = chatSetMode(db, convo, "hacker");
      expectTrue(test, r.conversation == null, "refused");
      expectText(test, firstError(r.errors), "mode is invalid");
      let again = chatLatestConversation(db, work.id);
      expectText(test, if (again != null) { again.mode } else { "<none>" }, "read");
    }

    test("creating a conversation in a junk mode stores nothing") { test =>
      let db = dbOpen(":memory:");
      let work = setup(db);
      let r = chatCreateConversation(db, work.id, "hacker");
      expectText(test, firstError(r.errors), "mode is invalid");
      expectInt(test, rowCount(db, "SELECT count(*) AS n FROM conversations"), 0);
    }

    test("a conversation row still has to belong to a draft") { test =>
      let errors = chatConversationErrors(null, null, null);
      expectText(test, firstError(errors), "work_id can't be blank");
      expectInt(test, chatConversationErrors(1, "read", "work").length, 0);
      expectText(test, firstError(chatConversationErrors(1, "read", "section")), "anchor_kind is invalid");
      expectText(test, firstError(chatConversationErrors(1, "nope", null)), "mode is invalid");
    }

## Whole-draft conversations

    test("get or create returns the same conversation until a new one is made") { test =>
      let db = dbOpen(":memory:");
      let work = setup(db);
      let a = makeConvo(db, work);
      let b = makeConvo(db, work);
      expectInt(test, a.id, b.id);
      let c = newConvo(db, work, "bounce");
      expectTrue(test, c.id != a.id, "a new one");
      expectInt(test, makeConvo(db, work).id, c.id);
      expectText(test, a.anchorKind, "work");
    }

    test("the list is newest first, whole-draft only, at most thirty") { test =>
      let db = dbOpen(":memory:");
      let work = setup(db);
      let section = firstSection(db, work);
      thread(db, work, section, "s1p1", null);
      var i = 0;
      while (i < 32) {
        newConvo(db, work, null);
        i += 1;
      }
      let list = chatListConversations(db, work.id);
      expectInt(test, list.length, 30);
      expectTrue(test, list[0].id > list[1].id, "newest first");
      for (let c of list) { expectText(test, c.anchorKind, "work"); }
      expectInt(test, chatListOpenConversations(db, work.id).length, 30);
    }

    test("pinned threads stay out of the drawer's strip") { test =>
      let db = dbOpen(":memory:");
      let work = setup(db);
      let section = firstSection(db, work);
      thread(db, work, section, "s1p2", null);
      expectInt(test, chatListConversations(db, work.id).length, 0);
      expectInt(test, chatConversationSummaries(db, work.id).length, 0);
      expectTrue(test, chatLatestConversation(db, work.id) == null, "no whole-draft conversation");
    }

    test("a thread from another draft cannot be reached by id") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let work = makeWork(db, me, "W", repeated("w ", 300));
      let other = makeWork(db, me, "Other", repeated("w ", 300));
      let theirs = makeConvo(db, other);
      expectTrue(test, chatGetConversation(db, work.id, theirs.id) == null, "not reachable");
      expectTrue(test, chatGetConversation(db, other.id, theirs.id) != null, "reachable at home");
    }

    test("a new thread starts empty and the old one stays on the strip") { test =>
      let db = dbOpen(":memory:");
      let work = setup(db);
      let first = makeConvo(db, work);
      chatAppend(db, first.id, "user", "the first question I asked");
      let fresh = newConvo(db, work, null);
      expectInt(test, chatHistory(db, fresh.id).length, 0);
      expectInt(test, chatListConversations(db, work.id).length, 2);
      let strip = chatConversationSummaries(db, work.id);
      expectText(test, strip[0].title, "New thread");
      expectText(test, strip[1].title, "the first question I asked");
    }

    test("deleting the thread you are in lands you in another") { test =>
      let db = dbOpen(":memory:");
      let work = setup(db);
      let a = makeConvo(db, work);
      let newest = newConvo(db, work, null);
      expectInt(test, chatListConversations(db, work.id).length, 2);
      expectInt(test, chatListConversations(db, work.id)[0].id, newest.id);
      expectTrue(test, chatDeleteConversation(db, newest), "deleted");
      let left = chatListConversations(db, work.id);
      expectInt(test, left.length, 1);
      expectInt(test, left[0].id, a.id);
      expectInt(test, makeConvo(db, work).id, a.id);
    }

    test("deleting a conversation takes its messages with it") { test =>
      let db = dbOpen(":memory:");
      let work = setup(db);
      let a = makeConvo(db, work);
      askMany(db, a, 3);
      expectInt(test, rowCount(db, "SELECT count(*) AS n FROM messages"), 3);
      chatDeleteConversation(db, a);
      expectInt(test, rowCount(db, "SELECT count(*) AS n FROM messages"), 0);
    }

## Naming a thread

    test("a thread is named after the question that started it") { test =>
      let db = dbOpen(":memory:");
      let work = setup(db);
      let a = makeConvo(db, work);
      chatAppend(db, a.id, "user", "why does the prologue exist");
      let summaries = chatConversationSummaries(db, work.id);
      expectInt(test, summaries.length, 1);
      expectText(test, summaries[0].title, "why does the prologue exist");
      expectInt(test, summaries[0].messages, 1);
      expectText(test, summaries[0].mode, "read");
    }

    test("the first question names it, not the first message") { test =>
      let db = dbOpen(":memory:");
      let work = setup(db);
      let a = makeConvo(db, work);
      chatAppend(db, a.id, "assistant", "an answer first");
      chatAppend(db, a.id, "user", "the real question");
      chatAppend(db, a.id, "user", "a later one");
      let s = chatConversationSummaries(db, work.id)[0];
      expectText(test, s.title, "the real question");
      expectInt(test, s.messages, 3);
    }

    test("a long title is cut at 51 graphemes with an ellipsis, whitespace collapsed") { test =>
      expectText(test, chatSummarise(null), "New thread");
      expectText(test, chatSummarise("  a   b\n\tc  "), "a b c");
      let fifty2 = repeated("x", 52);
      expectText(test, chatSummarise(fifty2), fifty2);
      let fifty3 = repeated("x", 53);
      expectText(test, chatSummarise(fifty3), "${repeated("x", 51)}…");
    }

## Turns

    test("append refuses a role the model never plays and a missing conversation") { test =>
      let db = dbOpen(":memory:");
      let work = setup(db);
      let a = makeConvo(db, work);
      expectTrue(test, chatAppend(db, a.id, "system", "nope") == null, "system refused");
      expectTrue(test, chatAppend(db, a.id, "tool", "nope") == null, "tool refused");
      expectTrue(test, chatAppend(db, 99999, "user", "nowhere") == null, "no such conversation");
      expectTrue(test, chatAppend(db, a.id, "user", "") == null, "empty refused");
      expectInt(test, rowCount(db, "SELECT count(*) AS n FROM messages"), 0);
      let m = chatAppend(db, a.id, "assistant", "fine");
      expectText(test, if (m != null) { m.content } else { "<none>" }, "fine");
    }

    test("history is chronological and capped at sixty") { test =>
      let db = dbOpen(":memory:");
      let work = setup(db);
      let a = makeConvo(db, work);
      askMany(db, a, 65);
      let h = chatHistory(db, a.id);
      expectInt(test, h.length, 60);
      expectText(test, h[0].content, "question 6");
      expectText(test, h[59].content, "question 65");
      expectInt(test, chatHistoryLimit(db, a.id, 2).length, 2);
      expectText(test, chatHistoryLimit(db, a.id, 2)[0].content, "question 64");
    }

    test("the context window is the last twenty") { test =>
      let db = dbOpen(":memory:");
      let work = setup(db);
      let a = makeConvo(db, work);
      askMany(db, a, 30);
      let w = chatContextWindow(chatHistory(db, a.id));
      expectInt(test, w.length, 20);
      expectText(test, w[0].content, "question 11");
      expectInt(test, chatContextWindow([new ChatTurn("user", "x")]).length, 1);
      expectInt(test, chatMessages(db, a.id).length, 30);
      expectText(test, chatMessages(db, a.id)[0].role, "user");
    }

## Searching what was said

    test("terms are lower-cased words of three letters or more") { test =>
      expectText(test, sysJoin(chatTerms("The Prologue, it's: a 12th-hour fix!"), "|"), "the|prologue|it's|12th|hour|fix");
      expectInt(test, chatTerms("a an of").length, 0);
      expectInt(test, chatTerms(null).length, 0);
    }

    test("search finds earlier talk in either voice") { test =>
      let db = dbOpen(":memory:");
      let work = setup(db);
      let c = makeConvo(db, work);
      chatAppend(db, c.id, "user", "I am worried the prologue is doing nothing");
      chatAppend(db, c.id, "assistant", "The prologue introduces nobody who returns");
      chatAppend(db, c.id, "user", "unrelated");
      let hits = chatSearch(db, work.id, "prologue");
      expectInt(test, hits.length, 2);
      expectText(test, hits[0].who, "assistant");
      expectText(test, hits[1].who, "user");
    }

    test("search ranks by how many terms a message holds, newer first among equals") { test =>
      let db = dbOpen(":memory:");
      let work = setup(db);
      let c = makeConvo(db, work);
      chatAppend(db, c.id, "user", "kettle only");
      chatAppend(db, c.id, "user", "kettle and window together");
      chatAppend(db, c.id, "user", "window only");
      let hits = chatSearch(db, work.id, "kettle window");
      expectInt(test, hits.length, 3);
      expectText(test, hits[0].said, "kettle and window together");
      expectText(test, hits[1].said, "window only");
      expectText(test, hits[2].said, "kettle only");
    }

    test("search is empty without usable terms and scoped to the draft") { test =>
      let db = dbOpen(":memory:");
      let me = makeUser(db, "a@example.com");
      let work = makeWork(db, me, "W", repeated("w ", 300));
      let other = makeWork(db, me, "Other", repeated("w ", 300));
      chatAppend(db, makeConvo(db, other).id, "user", "the kettle");
      expectInt(test, chatSearch(db, work.id, "").length, 0);
      expectInt(test, chatSearch(db, work.id, "to be").length, 0);
      expectInt(test, chatSearch(db, work.id, "kettle").length, 0);
      expectInt(test, chatSearch(db, other.id, "kettle").length, 1);
    }

    test("search quotes the first 600 characters and stops at eight") { test =>
      let db = dbOpen(":memory:");
      let work = setup(db);
      let c = makeConvo(db, work);
      chatAppend(db, c.id, "user", "kettle ${repeated("x", 700)}");
      expectInt(test, sysGraphemeLength(chatSearch(db, work.id, "kettle")[0].said), 600);
      var i = 0;
      while (i < 10) {
        chatAppend(db, c.id, "user", "kettle number ${i.toString()}");
        i += 1;
      }
      expectInt(test, chatSearch(db, work.id, "kettle").length, 8);
      expectInt(test, chatSearchLimit(db, work.id, "kettle", 3).length, 3);
    }

## The quota

    test("a fresh account has the full allowance") { test =>
      let db = dbOpen(":memory:");
      let me = userOf(makeUser(db, "a@example.com"));
      let q = chatRemaining(db, me);
      expectFalse(test, q.unlimited, "not unlimited");
      expectInt(test, q.left, chatMessageLimit());
      expectInt(test, chatMessageLimit(), 100);
      expectTrue(test, chatAllowed(db, me), "allowed");
    }

    test("only the writer's own questions count against it") { test =>
      let db = dbOpen(":memory:");
      let scope = makeUser(db, "a@example.com");
      let work = makeWork(db, scope, "W", repeated("w ", 300));
      let convo = makeConvo(db, work);
      askMany(db, convo, 3);
      chatAppend(db, convo.id, "assistant", "an answer, which is not a question");
      let me = userOf(scope);
      expectInt(test, chatMessagesSent(db, me.id), 3);
      expectInt(test, chatRemaining(db, me).left, chatMessageLimit() - 3);
    }

    test("it runs out, and does not go negative") { test =>
      let db = dbOpen(":memory:");
      let scope = makeUser(db, "a@example.com");
      let work = makeWork(db, scope, "W", repeated("w ", 300));
      askMany(db, makeConvo(db, work), chatMessageLimit() + 5);
      let me = userOf(scope);
      expectInt(test, chatRemaining(db, me).left, 0);
      expectFalse(test, chatAllowed(db, me), "no longer allowed");
    }

    test("questions across every draft count together") { test =>
      let db = dbOpen(":memory:");
      let scope = makeUser(db, "a@example.com");
      let work = makeWork(db, scope, "W", repeated("w ", 300));
      let other = makeWork(db, scope, "Other", repeated("w ", 300));
      askMany(db, makeConvo(db, work), 4);
      askMany(db, makeConvo(db, other), 6);
      expectInt(test, chatMessagesSent(db, userOf(scope).id), 10);
    }

    test("one account's questions do not count against another's") { test =>
      let db = dbOpen(":memory:");
      let scope = makeUser(db, "a@example.com");
      let work = makeWork(db, scope, "W", repeated("w ", 300));
      askMany(db, makeConvo(db, work), 5);
      let stranger = userOf(makeUser(db, "b@example.com"));
      expectInt(test, chatRemaining(db, stranger).left, chatMessageLimit());
    }

    test("deleting a draft gives the questions back") { test =>
      let db = dbOpen(":memory:");
      let scope = makeUser(db, "a@example.com");
      let work = makeWork(db, scope, "W", repeated("w ", 300));
      askMany(db, makeConvo(db, work), 7);
      let me = userOf(scope);
      expectInt(test, chatMessagesSent(db, me.id), 7);
      worksDeleteWork(db, work);
      expectInt(test, chatMessagesSent(db, me.id), 0);
    }

    test("the owner of the deploy is not capped") { test =>
      let db = dbOpen(":memory:");
      let scope = makeUser(db, accountsOwnerEmail());
      let work = makeWork(db, scope, "O", repeated("w ", 300));
      askMany(db, makeConvo(db, work), chatMessageLimit() + 1);
      let owner = userOf(scope);
      expectTrue(test, chatRemaining(db, owner).unlimited, "unlimited");
      expectTrue(test, chatAllowed(db, owner), "allowed");
    }

## Threads pinned to a place in the draft

    test("opening a thread creates one anchored to the block") { test =>
      let db = dbOpen(":memory:");
      let work = setup(db);
      let section = firstSection(db, work);
      let t = thread(db, work, section, "s1p2", null);
      expectText(test, t.anchorKind, "block");
      expectText(test, orEmpty(t.blockRef), "s1p2");
      expectText(test, t.mode, "read");
      expectTrue(test, t.quote == null, "no quote");
      expectInt(test, intOr(t.sectionId, -1), section.id);
    }

    test("coming back to the same paragraph returns to the same thread") { test =>
      let db = dbOpen(":memory:");
      let work = setup(db);
      let section = firstSection(db, work);
      let first = thread(db, work, section, "s1p2", null);
      let again = thread(db, work, section, "s1p2", null);
      expectInt(test, again.id, first.id);
      expectInt(test, chatThreadsByBlock(db, work.id).length, 1);
      expectInt(test, rowCount(db, "SELECT count(*) AS n FROM conversations"), 1);
    }

    test("a different paragraph gets its own thread") { test =>
      let db = dbOpen(":memory:");
      let work = setup(db);
      let section = firstSection(db, work);
      thread(db, work, section, "s1p1", null);
      thread(db, work, section, "s1p2", null);
      expectInt(test, chatThreadsByBlock(db, work.id).length, 2);
    }

    test("a selection pins the thread to the passage, not just the paragraph") { test =>
      let db = dbOpen(":memory:");
      let work = setup(db);
      let section = firstSection(db, work);
      let t = thread(db, work, section, "s1p2", "The kettle went cold on the counter");
      expectText(test, t.anchorKind, "span");
      let seen = chatThreadAt(db, work.id, "s1p2");
      expectText(test, if (seen != null) { orEmpty(seen.quote) } else { "<none>" }, "The kettle went cold on the counter");
    }

    test("a selection inside a paragraph that has a thread joins it and narrows it") { test =>
      let db = dbOpen(":memory:");
      let work = setup(db);
      let section = firstSection(db, work);
      let t = thread(db, work, section, "s1p2", null);
      expectText(test, t.anchorKind, "block");
      let narrowed = thread(db, work, section, "s1p2", "went cold");
      expectInt(test, narrowed.id, t.id);
      expectText(test, narrowed.anchorKind, "span");
      expectText(test, orEmpty(narrowed.quote), "went cold");
      let same = thread(db, work, section, "s1p2", "went cold");
      expectText(test, same.anchorKind, "span");
      let wider = thread(db, work, section, "s1p2", null);
      expectText(test, orEmpty(wider.quote), "went cold");
      expectText(test, orEmpty(thread(db, work, section, "s1p2", "a different bit").quote), "a different bit");
    }

    test("the tick carries the thread's message count") { test =>
      let db = dbOpen(":memory:");
      let work = setup(db);
      let section = firstSection(db, work);
      let t = thread(db, work, section, "s1p2", null);
      let before = chatThreadAt(db, work.id, "s1p2");
      expectInt(test, if (before != null) { before.messages } else { -1 }, 0);
      chatAppend(db, t.id, "user", "what is this doing");
      chatAppend(db, t.id, "assistant", "holding the room still");
      let after = chatThreadAt(db, work.id, "s1p2");
      expectInt(test, if (after != null) { after.messages } else { -1 }, 2);
      expectInt(test, if (after != null) { after.id } else { -1 }, t.id);
      expectText(test, if (after != null) { after.mode } else { "<none>" }, "read");
    }

    test("a thread can be settled and reopened") { test =>
      let db = dbOpen(":memory:");
      let work = setup(db);
      let section = firstSection(db, work);
      let t = thread(db, work, section, "s1p2", null);
      let settled = chatResolveThread(db, t, true).conversation;
      expectTrue(test, settled != null && settled.resolvedAt != null, "settled");
      let a = chatThreadAt(db, work.id, "s1p2");
      expectTrue(test, a != null && a.resolved, "resolved shows");
      let reopened = chatResolve(db, t, false).conversation;
      expectTrue(test, reopened != null && reopened.resolvedAt == null, "reopened");
      let b = chatThreadAt(db, work.id, "s1p2");
      expectTrue(test, b != null && !b.resolved, "not resolved");
    }

    test("a thread opened in a given mode keeps it") { test =>
      let db = dbOpen(":memory:");
      let work = setup(db);
      let section = firstSection(db, work);
      let r = chatThreadForBlock(db, work.id, section.id, "s1p1", null, "provoke");
      let c = r.conversation;
      expectText(test, if (c != null) { c.mode } else { "<none>" }, "provoke");
      let bad = chatThreadForBlock(db, work.id, section.id, "s1p9", null, "hacker");
      expectText(test, firstError(bad.errors), "mode is invalid");
      expectInt(test, chatThreadsByBlock(db, work.id).length, 1);
    }

    test("chatOpenThread is the default-mode form") { test =>
      let db = dbOpen(":memory:");
      let work = setup(db);
      let section = firstSection(db, work);
      let c = chatOpenThread(db, work, section.id, "s1p3", null).conversation;
      expectText(test, if (c != null) { orEmpty(c.blockRef) } else { "<none>" }, "s1p3");
    }

    test("two threads on one block ref cannot exist, even by hand") { test =>
      let db = dbOpen(":memory:");
      let work = setup(db);
      let section = firstSection(db, work);
      thread(db, work, section, "s1p2", null);
      let refused = do {
        db.exec("INSERT INTO conversations (work_id, block_ref, anchor_kind) VALUES ($1, 's1p2', 'block')", [work.id.toString()]);
        false
      } orelse true;
      expectTrue(test, refused, "unique (work_id, block_ref)");
    }
