# Persisted conversations

`Marginalia.Chat`: a writer's thinking about their own draft is the thing
worth keeping, so conversations survive reloads and the model is sent what was
already said, its own replies included.

Functions take the `Db` first. Ids are `Int`; a conversation is addressed by
its id where the Elixir took an id, by the record where it took the struct.
`{:ok, convo} | {:error, changeset}` becomes `ChatConversationResult`.

    let { Db, DbRow } = import("db/src");
    let { User, accountsIsOwner } = import("accounts/src");
    let { FieldError } = import("core/src");
    let { Work } = import("works/src");
    let { sysUtcNow, sysUtf8Downcase, sysGraphemeLength, sysGraphemeTake, sysJoin } = import("sys/src");

## Constants

What is rehydrated into the page, what is actually sent to the model (resent
every turn, so a direct multiplier on cost), and how many questions one
account may ask, ever.

    export let chatUiLimit(): Int { 60 }
    export let chatContextLimit(): Int { 20 }
    export let chatMessageLimit(): Int { 100 }

## Query parameters

    class ChatArgs {
      private var items: ListBuilder<String?> = new ListBuilder<String?>();
      public s(v: String?): ChatArgs { items.add(v); this }
      public n(v: Int): ChatArgs { items.add(v.toString()); this }
      public no(v: Int?): ChatArgs {
        if (v != null) { items.add(v.toString()); } else { items.add(null); }
        this
      }
      public build(): List<String?> { items.toList() }
    }

    let chatArgs(): ChatArgs { new ChatArgs() }

## Results and validation

A write the changeset may refuse comes back with the errors that stopped it.

    export class ChatConversationResult(
      public conversation: Conversation?,
      public errors: List<FieldError>,
    ) {}

    let chatIn(xs: List<String>, x: String): Boolean {
      var i = 0;
      while (i < xs.length) {
        if (xs[i] == x) { return true; }
        i += 1;
      }
      false
    }

`Conversation.changeset`: `work_id` is required (`can't be blank`), the
mode must be one of the editor's modes and the anchor kind one of
`work block span` (`is invalid`). `null` mode or kind means "not given", and
the column defaults apply.

    export let chatAnchorKinds(): List<String> { ["work", "block", "span"] }

    export let chatConversationErrors(
      workId: Int?, mode: String?, anchorKind: String?,
    ): List<FieldError> {
      let errors = new ListBuilder<FieldError>();
      if (anchorKind != null) {
        if (!chatIn(chatAnchorKinds(), anchorKind)) {
          errors.add(new FieldError("anchor_kind", "is invalid"));
        }
      }
      if (workId == null) { errors.add(new FieldError("work_id", "can't be blank")); }
      if (mode != null) {
        if (!chatIn(editorModeNames(), mode)) {
          errors.add(new FieldError("mode", "is invalid"));
        }
      }
      errors.toList()
    }

    let chatFailed(errors: List<FieldError>): ChatConversationResult {
      new ChatConversationResult(null, errors)
    }

    let chatConversationNamed(db: Db, id: Int): Conversation throws Bubble {
      let row = db.one(
        "SELECT ${chatConversationColumns} FROM conversations WHERE id = $1",
        chatArgs().n(id).build(),
      );
      if (row != null) { Conversation.fromRow(row) } else { bubble() }
    }

    let chatConversationsOf(rows: List<DbRow>): List<Conversation> throws Bubble {
      let out = new ListBuilder<Conversation>();
      for (let row of rows) { out.add(Conversation.fromRow(row)); }
      out.toList()
    }

## Whole-draft conversations

The newest whole-draft conversation, or null.

    export let chatLatestConversation(db: Db, workId: Int): Conversation? throws Bubble {
      let row = db.one(
        "SELECT ${chatConversationColumns} FROM conversations WHERE work_id = $1 AND anchor_kind = 'work' ORDER BY id DESC LIMIT 1",
        chatArgs().n(workId).build(),
      );
      if (row == null) { null } else { Conversation.fromRow(row) }
    }

    export let chatGetOrCreateConversation(db: Db, workId: Int): ChatConversationResult throws Bubble {
      let latest = chatLatestConversation(db, workId);
      if (latest != null) {
        new ChatConversationResult(latest, [])
      } else {
        chatCreateConversation(db, workId, null)
      }
    }

A new whole-draft conversation, in `mode` or the default one. An unknown
mode is an error and nothing is stored.

    export let chatCreateConversation(db: Db, workId: Int, mode: String?): ChatConversationResult throws Bubble {
      let chosen = if (mode != null) { mode } else { editorDefaultMode() };
      let errors = chatConversationErrors(workId, chosen, null);
      if (errors.length > 0) { return chatFailed(errors); }
      let id = db.insert(
        "INSERT INTO conversations (work_id, mode, anchor_kind) VALUES ($1, $2, 'work')",
        chatArgs().n(workId).s(chosen).build(),
      );
      new ChatConversationResult(chatConversationNamed(db, id), [])
    }

Switch the stance of an existing conversation. It keeps its history.

    export let chatSetMode(db: Db, c: Conversation, mode: String): ChatConversationResult throws Bubble {
      let errors = chatConversationErrors(c.workId, mode, null);
      if (errors.length > 0) { return chatFailed(errors); }
      db.exec(
        "UPDATE conversations SET mode = $1, updated_at = $2 WHERE id = $3",
        chatArgs().s(mode).s(sysUtcNow()).n(c.id).build(),
      );
      new ChatConversationResult(chatConversationNamed(db, c.id), [])
    }

Whole-draft conversations only, newest first, at most 30: the ones the
drawer's strip lists. (`list_open_conversations` is the same query.)

    export let chatListConversations(db: Db, workId: Int): List<Conversation> throws Bubble {
      chatConversationsOf(db.query(
        "SELECT ${chatConversationColumns} FROM conversations WHERE work_id = $1 AND anchor_kind = 'work' ORDER BY id DESC LIMIT 30",
        chatArgs().n(workId).build(),
      ))
    }

    export let chatListOpenConversations(db: Db, workId: Int): List<Conversation> throws Bubble {
      chatListConversations(db, workId)
    }

A conversation of this work, or null: a thread of another draft is not
reachable by guessing its id.

    export let chatGetConversation(db: Db, workId: Int, id: Int): Conversation? throws Bubble {
      let row = db.one(
        "SELECT ${chatConversationColumns} FROM conversations WHERE id = $1 AND work_id = $2",
        chatArgs().n(id).n(workId).build(),
      );
      if (row == null) { null } else { Conversation.fromRow(row) }
    }

    export let chatDeleteConversation(db: Db, c: Conversation): Boolean throws Bubble {
      db.exec("DELETE FROM conversations WHERE id = $1", chatArgs().n(c.id).build()) > 0
    }

## Picking one from a list

A thread with no name is named after the question that started it: that is
what the writer remembers it by. No question yet is `New thread`. Whitespace
collapses; past 52 graphemes the title is the first 51 and an ellipsis.

    export class ChatSummary(
      public id: Int,
      public mode: String,
      public messages: Int,
      public title: String,
      public at: String,
    ) {}

    export let chatSummarise(text: String?): String {
      if (text != null) {
        let flat = sysJoin(chatSplitSpaces(text), " ");
        if (sysGraphemeLength(flat) > 52) {
          let cut = sysGraphemeTake(flat, 51);
          "${cut}…"
        } else {
          flat
        }
      } else {
        "New thread"
      }
    }

Split on runs of whitespace, dropping empties: `String.replace(~r/\s+/, " ")`
then trim. The Elixir `\s` is ASCII whitespace.

    let chatIsSpace(c: Int): Boolean { c == 32 || (c >= 9 && c <= 13) }

    let chatSplitSpaces(text: String): List<String> {
      let out = new ListBuilder<String>();
      var start = String.begin;
      var inWord = false;
      var i = String.begin;
      while (text.hasIndex(i)) {
        let space = chatIsSpace(text[i]);
        if (!space && !inWord) { start = i; inWord = true; }
        if (space && inWord) { out.add(text.slice(start, i)); inWord = false; }
        i = text.next(i);
      }
      if (inWord) { out.add(text.slice(start, text.end)); }
      out.toList()
    }

    export let chatConversationSummaries(db: Db, workId: Int): List<ChatSummary> throws Bubble {
      let out = new ListBuilder<ChatSummary>();
      for (let c of chatListConversations(db, workId)) {
        let countRow = db.one(
          "SELECT count(*) AS n FROM messages WHERE conversation_id = $1",
          chatArgs().n(c.id).build(),
        );
        let count = if (countRow != null) { countRow.int("n") } else { 0 };
        let firstRow = db.one(
          "SELECT content FROM messages WHERE conversation_id = $1 AND role = 'user' ORDER BY id ASC LIMIT 1",
          chatArgs().n(c.id).build(),
        );
        let first: String? = if (firstRow != null) { firstRow.strOrNull("content") } else { null };
        let named = c.title;
        let title = if (named != null) { named } else { chatSummarise(first) };
        out.add(new ChatSummary(c.id, c.mode, count, title, c.insertedAt));
      }
      out.toList()
    }

## Turns

    export class ChatTurn(public role: String, public content: String) {}

The last `limit` messages, oldest first.

    export let chatHistoryLimit(db: Db, conversationId: Int, limit: Int): List<ChatTurn> throws Bubble {
      let rows = db.query(
        "SELECT role, content FROM messages WHERE conversation_id = $1 ORDER BY id DESC LIMIT $2",
        chatArgs().n(conversationId).n(limit).build(),
      );
      let out = new ListBuilder<ChatTurn>();
      var i = rows.length - 1;
      while (i >= 0) {
        out.add(new ChatTurn(rows[i].str("role"), rows[i].str("content")));
        i -= 1;
      }
      out.toList()
    }

    export let chatHistory(db: Db, conversationId: Int): List<ChatTurn> throws Bubble {
      chatHistoryLimit(db, conversationId, chatUiLimit())
    }

The last 20 turns: what is actually sent.

    export let chatContextWindow(history: List<ChatTurn>): List<ChatTurn> {
      let keep = chatContextLimit();
      if (history.length <= keep) { return history; }
      let out = new ListBuilder<ChatTurn>();
      var i = history.length - keep;
      while (i < history.length) {
        out.add(history[i]);
        i += 1;
      }
      out.toList()
    }

Every message of a conversation, oldest first.

    export let chatMessages(db: Db, conversationId: Int): List<Message> throws Bubble {
      let out = new ListBuilder<Message>();
      for (let row of db.query(
        "SELECT ${chatMessageColumns} FROM messages WHERE conversation_id = $1 ORDER BY id ASC",
        chatArgs().n(conversationId).build(),
      )) {
        out.add(Message.fromRow(row));
      }
      out.toList()
    }

Append a turn. It never raises: a chat that 500s on a write is worse than one
that forgets. A role other than `user` or `assistant`, empty content, or a
failed insert writes nothing and answers null.

    export let chatAppend(db: Db, conversationId: Int, role: String, content: String): Message? {
      if (role != "user" && role != "assistant") { return null; }
      if (content == "") { return null; }
      do {
        let id = db.insert(
          "INSERT INTO messages (conversation_id, role, content) VALUES ($1, $2, $3)",
          chatArgs().n(conversationId).s(role).s(content).build(),
        );
        let row = db.one(
          "SELECT ${chatMessageColumns} FROM messages WHERE id = $1",
          chatArgs().n(id).build(),
        );
        if (row != null) { Message.fromRow(row) } else { null }
      } orelse null
    }

## Searching what was said

Word-scored search across every conversation about this work. It backs
`recall_sessions`: the reader can find what it already said, including notes
the writer overruled. Terms are lower-cased, split on anything but `a-z`,
`0-9` and the apostrophe, and shorter than three characters dropped. The
candidates are the newest 400 messages; a message scores the number of terms
it contains; the best come first, newer first among equals.

    export class ChatHit(public who: String, public said: String, public at: String) {}

    export let chatTerms(query: String?): List<String> {
      let lower = sysUtf8Downcase(if (query != null) { query } else { "" });
      let out = new ListBuilder<String>();
      var start = String.begin;
      var inTerm = false;
      var length = 0;
      var i = String.begin;
      while (lower.hasIndex(i)) {
        let c = lower[i];
        let keep = (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 39;
        if (keep && !inTerm) { start = i; inTerm = true; length = 0; }
        if (keep) { length += 1; }
        if (!keep && inTerm) {
          if (length >= 3) { out.add(lower.slice(start, i)); }
          inTerm = false;
        }
        i = lower.next(i);
      }
      if (inTerm) {
        if (length >= 3) { out.add(lower.slice(start, lower.end)); }
      }
      out.toList()
    }

    class ChatScored(public hit: ChatHit, public score: Int, public order: Int) {}

    let chatContains(text: String, part: String): Boolean {
      text.split(part).length > 1
    }

    export let chatSearchLimit(db: Db, workId: Int, query: String?, limit: Int): List<ChatHit> throws Bubble {
      let terms = chatTerms(query);
      if (terms.length == 0) { return []; }
      let rows = db.query(
        "SELECT m.role AS role, m.content AS content, m.inserted_at AS at FROM messages m JOIN conversations c ON c.id = m.conversation_id WHERE c.work_id = $1 ORDER BY m.id DESC LIMIT 400",
        chatArgs().n(workId).build(),
      );
      let scored = new ListBuilder<ChatScored>();
      var k = 0;
      while (k < rows.length) {
        let content = rows[k].str("content");
        let text = sysUtf8Downcase(content);
        var score = 0;
        for (let t of terms) { if (chatContains(text, t)) { score += 1; } }
        if (score > 0) {
          let hit = new ChatHit(rows[k].str("role"), sysGraphemeTake(content, 600), rows[k].str("at"));
          scored.add(new ChatScored(hit, score, k));
        }
        k += 1;
      }
      let ranked = scored.toList().sorted { (a: ChatScored, b: ChatScored): Int =>
        if (a.score != b.score) { b.score - a.score } else { a.order - b.order }
      };
      let out = new ListBuilder<ChatHit>();
      var j = 0;
      while (j < ranked.length && j < limit) {
        out.add(ranked[j].hit);
        j += 1;
      }
      out.toList()
    }

    export let chatSearch(db: Db, workId: Int, query: String?): List<ChatHit> throws Bubble {
      chatSearchLimit(db, workId, query, 8)
    }

## The quota

Uploading needs no account, so anyone can spend the deploy's model credit. A
cap per account is the cheap version of a paywall.

Questions this account has asked, across every draft it owns. Counted from
the stored messages rather than a counter column, so it cannot drift and a
deleted draft gives the quota back.

    export let chatMessagesSent(db: Db, userId: Int): Int throws Bubble {
      let row = db.one(
        "SELECT count(*) AS n FROM messages m JOIN conversations c ON c.id = m.conversation_id JOIN works w ON w.id = c.work_id WHERE w.user_id = $1 AND m.role = 'user'",
        chatArgs().n(userId).build(),
      );
      if (row != null) { row.int("n") } else { 0 }
    }

`:unlimited` for the owner of the deploy is `unlimited` here; `left` is then 0
and means nothing.

    export class ChatQuota(public unlimited: Boolean, public left: Int) {}

    export let chatRemaining(db: Db, user: User): ChatQuota throws Bubble {
      if (accountsIsOwner(user)) {
        new ChatQuota(true, 0)
      } else {
        let left = chatMessageLimit() - chatMessagesSent(db, user.id);
        new ChatQuota(false, if (left > 0) { left } else { 0 })
      }
    }

Whether this account may ask another question.

    export let chatAllowed(db: Db, user: User): Boolean throws Bubble {
      let q = chatRemaining(db, user);
      q.unlimited || q.left != 0
    }

## Threads pinned to a place in the draft

The thread for one paragraph, creating it the first time. One thread per
place: clicking the same paragraph twice returns to the conversation already
there. A selection inside a paragraph that already has a thread joins it and
narrows what it is about (`quote` set, `anchorKind` `span`). Always succeeds
unless the mode or section is invalid.

    export let chatThreadForBlock(
      db: Db, workId: Int, sectionId: Int?, blockRef: String, quote: String?, mode: String?,
    ): ChatConversationResult throws Bubble {
      let existing = db.one(
        "SELECT ${chatConversationColumns} FROM conversations WHERE work_id = $1 AND block_ref = $2",
        chatArgs().n(workId).s(blockRef).build(),
      );
      if (existing != null) {
        let convo = Conversation.fromRow(existing);
        if (quote != null && quote != convo.quote) {
          db.exec(
            "UPDATE conversations SET quote = $1, anchor_kind = 'span', updated_at = $2 WHERE id = $3",
            chatArgs().s(quote).s(sysUtcNow()).n(convo.id).build(),
          );
          new ChatConversationResult(chatConversationNamed(db, convo.id), [])
        } else {
          new ChatConversationResult(convo, [])
        }
      } else {
        let chosen = if (mode != null) { mode } else { editorDefaultMode() };
        let kind = if (quote != null) { "span" } else { "block" };
        let errors = chatConversationErrors(workId, chosen, kind);
        if (errors.length > 0) {
          chatFailed(errors)
        } else {
          let id = db.insert(
            "INSERT INTO conversations (work_id, section_id, block_ref, anchor_kind, quote, mode) VALUES ($1, $2, $3, $4, $5, $6)",
            chatArgs().n(workId).no(sectionId).s(blockRef).s(kind).s(quote).s(chosen).build(),
          );
          new ChatConversationResult(chatConversationNamed(db, id), [])
        }
      }
    }

The same, in the default mode, for a draft.

    export let chatOpenThread(
      db: Db, work: Work, sectionId: Int?, blockRef: String, quote: String?,
    ): ChatConversationResult throws Bubble {
      chatThreadForBlock(db, work.id, sectionId, blockRef, quote, null)
    }

What the margin shows about one pinned thread.

    export class ChatThread(
      public blockRef: String,
      public id: Int,
      public messages: Int,
      public quote: String?,
      public resolved: Boolean,
      public mode: String,
    ) {}

Every pinned thread on this draft, keyed by the block it is pinned to.

    export let chatThreadsByBlock(db: Db, workId: Int): Map<String, ChatThread> throws Bubble {
      let out = new MapBuilder<String, ChatThread>();
      for (let row of chatThreadRows(db, workId)) {
        out.set(row.blockRef, row);
      }
      out.toMap()
    }

    export let chatThreadRows(db: Db, workId: Int): List<ChatThread> throws Bubble {
      let out = new ListBuilder<ChatThread>();
      for (let row of db.query(
        "SELECT c.id AS id, c.block_ref AS block_ref, c.quote AS quote, c.resolved_at AS resolved_at, c.mode AS mode, (SELECT count(*) FROM messages m WHERE m.conversation_id = c.id) AS n FROM conversations c WHERE c.work_id = $1 AND c.block_ref IS NOT NULL ORDER BY c.id ASC",
        chatArgs().n(workId).build(),
      )) {
        out.add(new ChatThread(
          row.str("block_ref"),
          row.int("id"),
          row.int("n"),
          row.strOrNull("quote"),
          row.strOrNull("resolved_at") != null,
          row.str("mode"),
        ));
      }
      out.toList()
    }

The thread pinned to one block, or null.

    export let chatThreadAt(db: Db, workId: Int, blockRef: String): ChatThread? throws Bubble {
      let rows = chatThreadRows(db, workId);
      var i = 0;
      while (i < rows.length) {
        if (rows[i].blockRef == blockRef) { return rows[i]; }
        i += 1;
      }
      null
    }

Mark a pinned thread settled, or reopen it.

    export let chatResolveThread(db: Db, c: Conversation, resolved: Boolean): ChatConversationResult throws Bubble {
      let at: String? = if (resolved) { sysUtcNow() } else { null };
      db.exec(
        "UPDATE conversations SET resolved_at = $1, updated_at = $2 WHERE id = $3",
        chatArgs().s(at).s(sysUtcNow()).n(c.id).build(),
      );
      new ChatConversationResult(chatConversationNamed(db, c.id), [])
    }

    export let chatResolve(db: Db, c: Conversation, resolved: Boolean): ChatConversationResult throws Bubble {
      chatResolveThread(db, c, resolved)
    }
