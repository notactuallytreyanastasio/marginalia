# Tests for the index: paging, the filter, the webs and the folder tool

The fixtures and the request helpers are those of `pages_links_test`.

    let { dbOpen, Db } = import("db/src");
    let { Scope } = import("accounts/src");
    let { Work, GraphNode } = import("works/src");
    let { Folder, foldersCreateFolder, foldersMoveWork } = import("folders/src");
    let { linksGetOrCreate, linksSetStatus, linksAttrsSummary, LinkStats } = import("links/src");
    let { llmFake } = import("llm/src");

## Paging and the filter

Ten read drafts, every pair of them linked: forty-five `linked` pairs, more
than a page of them. The pairs are inserted with SQL (a model pass per pair
would be the point of a different test).

    let tMany(db: Db, s: Scope): List<Work> throws Bubble {
      let works = new ListBuilder<Work>();
      for (var i = 1; i <= 10; ++i) { works.add(tWork(db, s, "Draft ${i.toString()}", "read")); }
      let ws = works.toList();
      for (var i = 0; i < ws.length; ++i) {
        for (var j = i + 1; j < ws.length; ++j) {
          db.exec("INSERT INTO links (a_work_id, b_work_id, status) VALUES ($1, $2, 'linked')", [ws[i].id.toString(), ws[j].id.toString()]);
        }
      }
      ws
    }

    let tLinkTwo(db: Db, a: Work, b: Work): Void throws Bubble {
      let l = linksGetOrCreate(db, a.id, b.id).ok;
      if (l != null) { linksSetStatus(db, l, "linked", linksAttrsSummary(null)); }
    }

    test("index: a page of rows, not all of them, and the way to more") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tMany(db, me.scope);
      let body = tBody(tGet(db, me.ctx, "/links"));
      expectInt(test, tCount(body, "class=\"lx-row\""), 40);
      expectHas(test, body, "<div class=\"lx-more\">");
      expectHas(test, body, "<button class=\"mg-btn sm\" phx-click=\"more\">");
      expectHas(test, body, "Show 5 more");
      expectHas(test, body, "<span class=\"mg-meta\">of 5 left</span>");
      expectHas(test, body, "45 of 45 linked");
    }

    test("index: more gives the rest, and asking again breaks nothing") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tMany(db, me.scope);
      let one = tMain(tEvent(db, me.ctx, "/links", "more", "{}", tNever()));
      expectInt(test, tCount(one, "class=\"lx-row\""), 45);
      expectLacks(test, one, "lx-more");
      let again = tMain(tEvent(db, me.ctx, "/links", "more", "{}", tNever()));
      expectInt(test, tCount(again, "class=\"lx-row\""), 45);
    }

    test("index: the filter matches either side of a pair, and resets the paging") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tMany(db, me.scope);
      tEvent(db, me.ctx, "/links", "more", "{}", tNever());
      let hit = tMain(tEvent(db, me.ctx, "/links", "filter", "{\"q\":\"Draft 7\"}", tNever()));
      let rows = tCount(hit, "class=\"lx-row\"");
      expectTrue(test, rows > 0, "some rows match Draft 7");
      expectTrue(test, rows < 45, "but not all of them");
      expectHas(test, hit, "<input type=\"text\" name=\"q\" value=\"Draft 7\" placeholder=\"narrow by either draft&#39;s title\" autocomplete=\"off\" phx-debounce=\"150\">");
      expectHas(test, hit, "<form phx-change=\"filter\" id=\"lx-filter\" class=\"lx-filter\">");
      expectLacks(test, hit, "Nothing matches");
      let wide = tMain(tEvent(db, me.ctx, "/links", "filter", "{\"q\":\"draft\"}", tNever()));
      expectInt(test, tCount(wide, "class=\"lx-row\""), 40);
    }

    test("index: the filter is case-insensitive") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tMany(db, me.scope);
      let hit = tMain(tEvent(db, me.ctx, "/links", "filter", "{\"q\":\"DRAFT 7\"}", tNever()));
      expectTrue(test, tCount(hit, "class=\"lx-row\"") > 0, "matches regardless of case");
    }

    test("index: a filter that matches nothing says so instead of showing everything") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tMany(db, me.scope);
      let none = tMain(tEvent(db, me.ctx, "/links", "filter", "{\"q\":\"nonesuch\"}", tNever()));
      expectHas(test, none, "<p class=\"none\">\nNothing matches “nonesuch”.\n</p>");
      expectInt(test, tCount(none, "class=\"lx-row\""), 0);
      expectHas(test, none, "0 of 45 linked");
    }

    test("index: a plain visit forgets the filter") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tMany(db, me.scope);
      tEvent(db, me.ctx, "/links", "filter", "{\"q\":\"nonesuch\"}", tNever());
      expectLacks(test, tBody(tGet(db, me.ctx, "/links")), "Nothing matches");
    }

## The webs

    test("index: three drafts and two links are one web, drawn once, with the pair nobody has related") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let a = tWork(db, me.scope, "Alpha", "read");
      let b = tWork(db, me.scope, "Beta", "read");
      let c = tWork(db, me.scope, "Gamma", "read");
      tLinkTwo(db, a, b);
      tLinkTwo(db, b, c);
      let body = tBody(tGet(db, me.ctx, "/links"));
      expectHas(test, body, "<details class=\"lx-fold\">");
      expectHas(test, body, "1 web of three or more");
      expectHas(test, body, "<div class=\"lx-web\">");
      expectHas(test, body, "3 drafts, 2 links");
      expectHas(test, body, "<svg class=\"lx-svg\" viewBox=\"0 0 520 300\" preserveAspectRatio=\"xMidYMid meet\">");
      expectHas(test, body, "class=\"edge\"");
      expectHas(test, body, "<a href=\"/works/${a.slug}\" class=\"node\">");
      expectHas(test, body, "<circle cx=\"260.0\" cy=\"45.0\" r=\"7\"></circle>");
      expectHas(test, body, "class=\"gap\"");
      expectHas(test, body, "Not related yet:");
      expectHas(test, body, "<span class=\"pair\">Alpha ↔ Gamma</span>");
      expectInt(test, tCount(body, "class=\"node\""), 3);
    }

    test("index: a lone pair is not drawn: there is no shape to show") { test =>
      let fx = tFx();
      let body = tBody(tGet(fx.db, fx.me.ctx, "/links"));
      expectLacks(test, body, "of three or more");
      expectLacks(test, body, "<svg");
    }

    test("index: coordinates print with one decimal, as the browser reads the Elixir's") { test =>
      expectText(test, pagesLinksOneDecimal(260.0), "260.0");
      expectText(test, pagesLinksOneDecimal(429.99999999999994), "430.0");
      expectText(test, pagesLinksOneDecimal(112.5), "112.5");
    }

    test("index: a long title is cut to 30 characters and an ellipsis in a diagram") { test =>
      expectText(test, pagesLinksShort("Short title"), "Short title");
      expectText(test, "[${pagesLinksShort("A title that is much too long for the diagram")}]", "[A title that is much too long …]");
      expectText(test, pagesLinksShort("12345678901234567890123456789012"), "12345678901234567890123456789012");
    }

    test("index: the relations of a pair, largest first and then by name, three at most") { test =>
      let by = new MapBuilder<String, Int>();
      by.set("echoes", 2);
      by.set("tension", 5);
      by.set("answers", 2);
      by.set("pays_off", 1);
      let top = pagesLinksTop(new LinkStats(10, by.toMap(), 3, 3));
      expectInt(test, top.length, 3);
      expectText(test, "${top[0].key} ${top[0].value.toString()}", "tension 5");
      expectText(test, "${top[1].key} ${top[1].value.toString()}", "answers 2");
      expectText(test, "${top[2].key} ${top[2].value.toString()}", "echoes 2");
    }

    test("index: the tools and the diagrams are folded, not gone") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tWork(db, me.scope, "Alpha", "read");
      foldersCreateFolder(db, me.scope, "Case file", null);
      let body = tBody(tGet(db, me.ctx, "/links"));
      expectHas(test, body, "<details class=\"lx-fold\">");
      expectHas(test, body, "<span class=\"mg-label\">relate a whole folder</span>");
      expectHas(test, body, "relate two drafts");
      expectHas(test, body, "<form phx-submit=\"bulk_propose\" class=\"lx-bulk-pick\">");
      expectHas(test, body, "<select name=\"folder\">");
      expectHas(test, body, "Work out what to relate");
      expectLacks(test, body, "Reading the folder…");
      expectLacks(test, body, "<details class=\"lx-fold\" open>");
      expectLacks(test, body, "data-poll");
    }

## Relating a whole folder

A folder with `titles` as its drafts, oldest first, each with a beat.

    class TFolder(public folder: Folder, public works: List<Work>, public nodes: List<GraphNode>) {}

    let tFolder(db: Db, s: Scope, name: String, titles: List<String>, status: String): TFolder throws Bubble {
      let made = foldersCreateFolder(db, s, name, null).folder;
      if (made == null) { bubble(); }
      let works = new ListBuilder<Work>();
      let nodes = new ListBuilder<GraphNode>();
      for (let t of titles) {
        let w = tWork(db, s, t, status);
        works.add(w);
        nodes.add(tBeat(db, w, "a beat in ${t}", "A sentence long enough"));
        if (made != null) { foldersMoveWork(db, s, w.id, made.id); }
      }
      if (made != null) { new TFolder(made, works.toList(), nodes.toList()) } else { bubble() }
    }

    let tProposal(): String throws Bubble {
      tTool("{\"pairs\":[{\"a\":1,\"b\":2,\"why\":\"One sets up what two pays off.\",\"expect\":\"pays_off\"}],\"skipped\":\"The rest share only a subject.\"}")
    }

    test("bulk: the cheap pass shows the pairs it chose, what it left out, and the way to relate them") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tFolder(db, me.scope, "Case file", ["Opinion", "Dissent"], "read");
      let launcher = tNow([tProposal()]);
      let r = tEvent(db, me.ctx, "/links", "bulk_propose", "{\"folder\":\"${f.folder.id.toString()}\"}", launcher);
      let main = tMain(r);
      expectProposes(test, launcher, 1);
      expectHas(test, main, "<details class=\"lx-fold\" open>");
      expectHas(test, main, "<div class=\"lx-bulk-out\">");
      expectHas(test, main, "<ol class=\"mg-rows\">");
      expectHas(test, main, "<span class=\"n\">pays_off</span>");
      expectHas(test, main, "<strong>Opinion</strong>");
      expectHas(test, main, "<strong>Dissent</strong>");
      expectHas(test, main, "<p class=\"mg-meta\">One sets up what two pays off.</p>");
      expectHas(test, main, "Left out: The rest share only a subject.");
      expectHas(test, main, "phx-click=\"bulk_relate\"");
      expectHas(test, main, "data-confirm=\"Read each of these pairs against each other? That is one model call per pair.\"");
      expectHas(test, main, "Relate these 1");
      expectLacks(test, main, "data-poll");
      expectLacks(test, main, "Reading the folder…");
      expectText(test, tFlash(r), "");
    }

    test("bulk: while the pass runs the folder tool is open, disabled, and the page polls") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tFolder(db, me.scope, "Case file", ["Opinion", "Dissent"], "read");
      let launcher = tQueue();
      let main = tMain(tEvent(db, me.ctx, "/links", "bulk_propose", "{\"folder\":${f.folder.id.toString()}}", launcher));
      expectProposes(test, launcher, 1);
      expectHas(test, main, "<div class=\"space-y-4\" data-poll=\"2\">");
      expectHas(test, main, "<details class=\"lx-fold\" open>");
      expectHas(test, main, "<select name=\"folder\" disabled>");
      expectHas(test, main, "Reading the folder…");
      expectHas(test, main, "<button type=\"submit\" class=\"mg-btn sm\" disabled>");
      expectLacks(test, main, "lx-bulk-out");
      let still = tMain(tPoll(db, me.ctx, "/links"));
      expectHas(test, still, "data-poll=\"2\"");
      pagesLinksRunPropose(db, pagesLinksBulkKey(f.folder.id), llmFake([tProposal()]), me.scope, f.folder.id);
      let done = tMain(tPoll(db, me.ctx, "/links"));
      expectLacks(test, done, "data-poll");
      expectHas(test, done, "<ol class=\"mg-rows\">");
      expectHas(test, done, "Relate these 1");
    }

    test("bulk: a folder that is not yours, or is empty, or whose model call failed, is a flash") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let them = tWho(db, "b@example.com");
      let mine = tFolder(db, me.scope, "Mine", ["One"], "read");
      let theirs = tFolder(db, them.scope, "Theirs", ["Two"], "read");
      let empty = foldersCreateFolder(db, me.scope, "Nothing in it", null).folder;
      let notMine = tEvent(db, me.ctx, "/links", "bulk_propose", "{\"folder\":\"${theirs.folder.id.toString()}\"}", tNow([]));
      expectText(test, tFlash(notMine), "error: Could not read that folder: :no_folder");
      expectLacks(test, tMain(notMine), "lx-bulk-out");
      if (empty != null) {
        let none = tEvent(db, me.ctx, "/links", "bulk_propose", "{\"folder\":\"${empty.id.toString()}\"}", tNow([]));
        expectText(test, tFlash(none), "error: Could not read that folder: :empty_folder");
      }
      let broke = tEvent(db, me.ctx, "/links", "bulk_propose", "{\"folder\":\"${mine.folder.id.toString()}\"}",
        new TLauncher(tFailScript(), true));
      expectHas(test, tFlash(broke), "error: Could not read that folder: \"");
    }

    test("bulk: a folder id that is not a number does nothing") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tFolder(db, me.scope, "Case file", ["Opinion", "Dissent"], "read");
      let launcher = tQueue();
      let r = tEvent(db, me.ctx, "/links", "bulk_propose", "{\"folder\":\"oops\"}", launcher);
      expectProposes(test, launcher, 0);
      expectText(test, tFlash(r), "");
      expectLacks(test, tMain(r), "Reading the folder…");
    }

    test("bulk: a pass that proposes nothing says nothing looked worth relating") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tFolder(db, me.scope, "Case file", ["Opinion", "Dissent"], "read");
      let main = tMain(tEvent(db, me.ctx, "/links", "bulk_propose", "{\"folder\":\"${f.folder.id.toString()}\"}",
        tNow([tTool("{\"pairs\":[],\"skipped\":\"\"}")])));
      expectHas(test, main, "<p class=\"none\">\nNothing in that folder looked worth relating.\n</p>");
      expectLacks(test, main, "bulk_relate");
      expectLacks(test, main, "Left out:");
    }

    test("bulk: proposals the validator threw away are listed") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tFolder(db, me.scope, "Case file", ["Opinion", "Dissent"], "read");
      let main = tMain(tEvent(db, me.ctx, "/links", "bulk_propose", "{\"folder\":\"${f.folder.id.toString()}\"}",
        tNow([tTool("{\"pairs\":[{\"a\":1,\"b\":2,\"why\":\"Real.\",\"expect\":\"tension\"},{\"a\":1,\"b\":9,\"why\":\"Made up.\",\"expect\":\"tension\"}],\"skipped\":\"\"}")])));
      expectHas(test, main, "<p class=\"cut-err\">\n1 proposal(s) discarded:");
      expectHas(test, main, "Relate these 1");
    }

    test("bulk: pairs with an unread draft are named, and with nothing else there is no button") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tFolder(db, me.scope, "Case file", ["Opinion", "Dissent"], "reading");
      let main = tMain(tEvent(db, me.ctx, "/links", "bulk_propose", "{\"folder\":\"${f.folder.id.toString()}\"}", tNow([tProposal()])));
      expectHas(test, main, "<p class=\"cut-err\">\n1 of these cannot be read yet — Opinion ↔ Dissent: Opinion and Dissent has not been read\n</p>");
      expectLacks(test, main, "bulk_relate");
    }

    test("bulk: relating the pairs reads each, and says how many were started") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tFolder(db, me.scope, "Case file", ["Opinion", "Dissent"], "read");
      let launcher = tNow([tProposal(), tLinkerReply(f.nodes[0], f.nodes[1])]);
      tEvent(db, me.ctx, "/links", "bulk_propose", "{\"folder\":\"${f.folder.id.toString()}\"}", launcher);
      let r = tEvent(db, me.ctx, "/links", "bulk_relate", "{}", launcher);
      expectRelates(test, launcher, 1);
      expectText(test, tFlash(r), "info: Started 1 readings.");
      expectLacks(test, tMain(r), "lx-bulk-out");
      expectLacks(test, tMain(r), "data-poll");
      let link = linksGetOrCreate(db, f.works[0].id, f.works[1].id).ok;
      expectTrue(test, link != null, "the pair has a link");
      if (link != null) {
        expectText(test, tStatus(db, link), "linked");
        expectInt(test, tN(db, "SELECT count(*) AS n FROM link_edges"), 1);
      }
    }

    test("bulk: relating while the job runs keeps the triage on the page and polls") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tFolder(db, me.scope, "Case file", ["Opinion", "Dissent"], "read");
      tEvent(db, me.ctx, "/links", "bulk_propose", "{\"folder\":\"${f.folder.id.toString()}\"}", tNow([tProposal()]));
      let queue = tQueue();
      let main = tMain(tEvent(db, me.ctx, "/links", "bulk_relate", "{}", queue));
      expectRelates(test, queue, 1);
      expectHas(test, main, "data-poll=\"2\"");
      expectHas(test, main, "<ol class=\"mg-rows\">");
      expectHas(test, main, "phx-click=\"bulk_relate\" disabled");
    }

    test("bulk: relate with nothing proposed does nothing") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      tFolder(db, me.scope, "Case file", ["Opinion", "Dissent"], "read");
      let launcher = tQueue();
      tEvent(db, me.ctx, "/links", "bulk_relate", "{}", launcher);
      expectRelates(test, launcher, 0);
    }

    test("bulk: a job that crashed is a flash, not a page that polls for ever") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tFolder(db, me.scope, "Case file", ["Opinion", "Dissent"], "read");
      tEvent(db, me.ctx, "/links", "bulk_propose", "{\"folder\":\"${f.folder.id.toString()}\"}", tQueue());
      db.exec("UPDATE runs SET status = 'crashed', detail = 'Bubble' WHERE key = $1", [pagesLinksBulkKey(f.folder.id)]);
      let r = tPoll(db, me.ctx, "/links");
      expectText(test, tFlash(r), "error: Crashed: Bubble");
      expectLacks(test, tMain(r), "data-poll");
    }

    test("bulk: a triage survives a fresh visit while its folder is chosen") { test =>
      let db = dbOpen(":memory:");
      let me = tWho(db, "a@example.com");
      let f = tFolder(db, me.scope, "Case file", ["Opinion", "Dissent"], "read");
      tEvent(db, me.ctx, "/links", "bulk_propose", "{\"folder\":\"${f.folder.id.toString()}\"}", tNow([tProposal()]));
      expectHas(test, tBody(tGet(db, me.ctx, "/links")), "<ol class=\"mg-rows\">");
    }

    test("bulk: the inspect of a reason: atoms print as atoms and text is quoted") { test =>
      expectText(test, pagesLinksInspect("no_folder"), ":no_folder");
      expectText(test, pagesLinksInspect("empty_folder"), ":empty_folder");
      expectText(test, pagesLinksInspect("http: status 500"), "\"http: status 500\"");
      expectText(test, pagesLinksInspect("say \"no\""), "\"say \\\"no\\\"\"");
    }
