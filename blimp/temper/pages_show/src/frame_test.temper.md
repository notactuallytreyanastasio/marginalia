# Tests for the frame

The header, the tabs, the gate, the progress strip, the poll. Each draws the
page for a person and reads the text, as `notes/tests.md` parts 7 and 8 do for
the LiveView.

    let { accountsOwnerEmail } = import("accounts/src");
    let { worksSetStatus, worksGetById } = import("works/src");
    let { runsGet } = import("runs/src");

## The page and who is looking

    test("frame: the page names the draft, its size and its sections") { test =>
      let w = tWorld();
      let r = tGet(w.db, w.owner, tPath(w.work, "read"), tKeyed());
      expectInt(test, r.resp.status, 200);
      expectHas(test, tBodyOf(r), "<h1");
      expectHas(test, tBodyOf(r), "Draft");
      expectHas(test, tBodyOf(r), "1 sections");
      expectHas(test, tBodyOf(r), "0 beats");
      expectHas(test, tBodyOf(r), "words");
    }

    test("frame: the page asks not to be indexed") { test =>
      let w = tWorld();
      let r = tGet(w.db, w.owner, tPath(w.work, "read"), tKeyed());
      expectHas(test, tBodyOf(r), "noindex, nofollow");
    }

    test("frame: the tabs read in the order the work happens") { test =>
      let w = tWorld();
      let html = tBodyOf(tGet(w.db, w.owner, tPath(w.work, "read"), tKeyed()));
      let read = html.split(">Read<").getOr(0, "").split("").length;
      let graph = html.split(">Graph<").getOr(0, "").split("").length;
      let spine = html.split(">Spine<").getOr(0, "").split("").length;
      let threads = html.split(">Threads<").getOr(0, "").split("").length;
      expectTrue(test, read < graph && graph < spine && spine < threads, "Read, Graph, Spine, Threads in that order");
      expectHas(test, html, "phx-click=\"set_view\" phx-value-view=\"graph\"");
    }

    test("frame: the tab being shown is lit") { test =>
      let w = tWorld();
      let html = tBodyOf(tGet(w.db, w.owner, tPath(w.work, "spine"), tKeyed()));
      expectHas(test, html, "class=\"mg-tab on\" phx-click=\"set_view\" phx-value-view=\"spine\"");
      expectLacks(test, html, "class=\"mg-tab on\" phx-click=\"set_view\" phx-value-view=\"read\"");
    }

    test("frame: Changes is offered once something has changed, not before") { test =>
      let w = tWorld();
      expectLacks(test, tBodyOf(tGet(w.db, w.owner, tPath(w.work, "read"), tKeyed())), ">Changes<");
      tEdit(w.db, w.work, "kettle", "AMENDED");
      expectHas(test, tBodyOf(tGet(w.db, w.owner, tPath(w.work, "read"), tKeyed())), ">Changes<");
    }

    test("frame: Trace and Prompts are the deploy owner's, and nobody else's") { test =>
      let w = tWorld();
      let boss = tWho(w.db, accountsOwnerEmail());
      let theirs = tBodyOf(tGet(w.db, boss, tPath(w.work, "read"), tKeyed()));
      expectHas(test, theirs, ">Trace<");
      expectHas(test, theirs, ">Prompts<");
      let mine = tBodyOf(tGet(w.db, w.owner, tPath(w.work, "read"), tKeyed()));
      expectLacks(test, mine, ">Trace<");
      expectLacks(test, mine, ">Prompts<");
    }

    test("frame: asked for directly, the owner's tabs fall back to the page") { test =>
      let w = tWorld();
      let html = tBodyOf(tGet(w.db, w.owner, tPath(w.work, "trace"), tKeyed()));
      expectHas(test, html, "The page");
      expectLacks(test, html, "Build trace");
      let boss = tWho(w.db, accountsOwnerEmail());
      expectHas(test, tBodyOf(tGet(w.db, boss, tPath(w.work, "trace"), tKeyed())), "Build trace");
    }

    test("frame: an unknown view is the page, not a report about it") { test =>
      let w = tWorld();
      let html = tBodyOf(tGet(w.db, w.owner, tPath(w.work, "nonsense"), tKeyed()));
      expectInt(test, tCount(html, "id=\"read-rail\""), 1);
    }

    test("frame: the default view is the draft itself") { test =>
      let w = tWorld();
      let html = tBodyOf(tGet(w.db, w.owner, "/works/${w.work.slug}", tKeyed()));
      expectHas(test, html, "id=\"read-rail\"");
    }

    test("frame: every view the owner can reach renders by direct link") { test =>
      let w = tWorld();
      let views = ["read", "graph", "spine", "threads", "changes"];
      var i = 0;
      while (i < views.length) {
        let r = tGet(w.db, w.owner, tPath(w.work, views[i]), tKeyed());
        expectInt(test, r.resp.status, 200);
        expectHas(test, tBodyOf(r), "page-body");
        i += 1;
      }
    }

    test("frame: the owner has a link to hand out, a reader has a badge") { test =>
      let w = tWorld();
      let mine = tBodyOf(tGet(w.db, w.owner, tPath(w.work, "read"), tKeyed()));
      expectHas(test, mine, "Copy link");
      expectHas(test, mine, "id=\"share-link\"");
      expectHas(test, mine, "data-url=\"");
      expectHas(test, mine, "/works/${w.work.slug}");
      expectLacks(test, mine, "reading someone&#39;s draft");
      let theirs = tBodyOf(tGet(w.db, w.reader, tPath(w.work, "read"), tKeyed()));
      expectHas(test, theirs, "reading someone&#39;s draft");
      expectLacks(test, theirs, "Copy link");
    }

    test("frame: the drawer's toggle is lit only while the drawer is open") { test =>
      let w = tWorld();
      let closed = tBodyOf(tGet(w.db, w.owner, tPath(w.work, "read"), tKeyed()));
      expectHas(test, closed, "class=\"mg-btn sm ghost\" phx-click=\"toggle_chat\"");
      expectHas(test, closed, "mg-drawer \" aria-hidden");
      let open = tBodyOf(tGet(w.db, w.owner, "${tPath(w.work, "read")}&chat=1", tKeyed()));
      expectHas(test, open, "class=\"mg-btn sm\" phx-click=\"toggle_chat\"");
      expectHas(test, open, "mg-drawer open");
      expectHas(test, open, "mg-shifted");
    }

    test("frame: the help button is beside the tabs") { test =>
      let w = tWorld();
      let html = tBodyOf(tGet(w.db, w.owner, tPath(w.work, "read"), tKeyed()));
      expectHas(test, html, "class=\"mg-help\" phx-click=\"show_help\"");
    }

    test("frame: the page and its selection toolbar carry the ids the hooks look for") { test =>
      let w = tWorld();
      let html = tBodyOf(tGet(w.db, w.owner, tPath(w.work, "read"), tKeyed()));
      expectHas(test, html, "id=\"page-body\"");
      expectHas(test, html, "phx-hook=\"Selection\"");
      expectHas(test, html, "id=\"sel-actions\" hidden");
      expectHas(test, html, "id=\"sel-discuss\"");
      expectHas(test, html, "id=\"sel-rewrite\"");
      expectHas(test, html, "id=\"sel-add\"");
    }

    test("frame: a draft that is not there goes back to /works and says so") { test =>
      let w = tWorld();
      let r = tGet(w.db, w.owner, "/works/nothing-here", tKeyed());
      expectInt(test, r.resp.status, 303);
      expectText(test, tLocation(r), "/works");
      let poll = tPoll(w.db, w.owner, "/works/nothing-here", tKeyed());
      expectText(test, tRedirect(poll), "/works");
    }

    test("frame: a visitor with a link reads, and is not asked who they are") { test =>
      let w = tWorld();
      let r = tGet(w.db, w.reader, tPath(w.work, "read"), tKeyed());
      expectInt(test, r.resp.status, 200);
      expectHas(test, tBodyOf(r), "She had been standing at the window");
    }

    test("frame: links to other drafts are listed, read alongside") { test =>
      let w = tWorld();
      let other = tRead(w.db, w.owner.scope, "Other draft", tBody());
      let id = w.db.insert("INSERT INTO links (a_work_id, b_work_id, status) VALUES ($1, $2, 'linked')", [w.work.id.toString(), other.id.toString()]);
      let html = tBodyOf(tGet(w.db, w.owner, tPath(w.work, "read"), tKeyed()));
      expectHas(test, html, "read alongside");
      expectHas(test, html, "/links/${id.toString()}?lead=${w.work.slug}");
      expectHas(test, html, "Other draft");
      expectLacks(test, html, "class=\"st linked\"");
    }

    test("frame: a pair still being read shows its status") { test =>
      let w = tWorld();
      let other = tRead(w.db, w.owner.scope, "Other draft", tBody());
      w.db.insert("INSERT INTO links (a_work_id, b_work_id, status) VALUES ($1, $2, 'linking')", [w.work.id.toString(), other.id.toString()]);
      let html = tBodyOf(tGet(w.db, w.owner, tPath(w.work, "read"), tKeyed()));
      expectHas(test, html, "class=\"st linking\"");
    }

    test("frame: the link menu offers read drafts, and only the owner's") { test =>
      let w = tWorld();
      let other = tRead(w.db, w.owner.scope, "Other draft", tBody());
      let html = tBodyOf(tGet(w.db, w.owner, tPath(w.work, "read"), tKeyed()));
      expectHas(test, html, "id=\"linkbox\"");
      expectLacks(test, html, "phx-value-id=\"${other.id.toString()}\"");
      tEvent(w.db, w.owner, tPath(w.work, "read"), "toggle_linking", "{}", tKeyed());
      let open = tBodyOf(tGet(w.db, w.owner, tPath(w.work, "read"), tKeyed()));
      expectHas(test, open, "phx-click-away=\"toggle_linking\"");
      expectHas(test, open, "phx-click=\"link_to\" phx-value-id=\"${other.id.toString()}\"");
      expectLacks(test, tBodyOf(tGet(w.db, w.reader, tPath(w.work, "read"), tKeyed())), "id=\"linkbox\"");
    }

    test("frame: Read again is offered on a read draft with no beats, to its owner") { test =>
      let w = tWorld();
      expectHas(test, tBodyOf(tGet(w.db, w.owner, tPath(w.work, "read"), tKeyed())), "phx-click=\"start_read\">Read again<");
      expectLacks(test, tBodyOf(tGet(w.db, w.reader, tPath(w.work, "read"), tKeyed())), "Read again");
      tBeat(w.db, w.work, "A beat");
      expectLacks(test, tBodyOf(tGet(w.db, w.owner, tPath(w.work, "read"), tKeyed())), "Read again");
    }

## Before it reads

    let tUnread(db: Db, who: TWho, sections: Int): Work throws Bubble {
      let parts = new ListBuilder<String>();
      for (var i = 1; i <= sections; ++i) {
        parts.add("# Part ${i.toString()}\n\n${tWords(300)}");
      }
      tDraft(db, who.scope, "A long draft", parts.toList().join("\n\n") { (x: String): String => x })
    }

    test("gate: the read can be started before the list of sections") { test =>
      let w = tWorld();
      let long = tUnread(w.db, w.owner, 25);
      let html = tBodyOf(tGet(w.db, w.owner, "/works/${long.slug}", tKeyed()));
      expectHas(test, html, "Read it — 25 sections");
      expectHas(test, html, "Before it reads");
      let after = html.split("Before it reads").getOr(1, "");
      let button = after.split("Read it —").getOr(0, "").split("").length;
      let list = after.split("class=\"mg-rows").getOr(0, "").split("").length;
      expectTrue(test, button < list, "the only way to start a read is not underneath twenty-five rows");
    }

    test("gate: a long draft offers it at the bottom too") { test =>
      let w = tWorld();
      let long = tUnread(w.db, w.owner, 25);
      let html = tBodyOf(tGet(w.db, w.owner, "/works/${long.slug}", tKeyed()));
      expectInt(test, tCount(html, "Read it — 25 sections"), 2);
    }

    test("gate: a short draft does not repeat itself") { test =>
      let w = tWorld();
      let short = tUnread(w.db, w.owner, 3);
      let html = tBodyOf(tGet(w.db, w.owner, "/works/${short.slug}", tKeyed()));
      expectInt(test, tCount(html, "Read it — 3 sections"), 1);
    }

    test("gate: the sections are listed with their size") { test =>
      let w = tWorld();
      let short = tUnread(w.db, w.owner, 3);
      let html = tBodyOf(tGet(w.db, w.owner, "/works/${short.slug}", tKeyed()));
      expectHas(test, html, "Part 1");
      expectHas(test, html, "Part 3");
      expectHas(test, html, "300w");
    }

    test("gate: with no key it says so rather than offering a button") { test =>
      let w = tWorld();
      let short = tUnread(w.db, w.owner, 4);
      let html = tBodyOf(tGet(w.db, w.owner, "/works/${short.slug}", tNoKey()));
      expectLacks(test, html, "Read it —");
      expectHas(test, html, "key is configured on this deploy");
    }

    test("gate: someone else's draft offers no button at all") { test =>
      let w = tWorld();
      let short = tUnread(w.db, w.owner, 4);
      let html = tBodyOf(tGet(w.db, w.reader, "/works/${short.slug}", tKeyed()));
      expectLacks(test, html, "Read it —");
    }

    test("gate: nothing of the read view is drawn before the read") { test =>
      let w = tWorld();
      let short = tUnread(w.db, w.owner, 4);
      let html = tBodyOf(tGet(w.db, w.owner, "/works/${short.slug}", tKeyed()));
      expectLacks(test, html, "id=\"read-rail\"");
      expectLacks(test, html, "Reading your draft");
    }

    test("gate: pressing it starts the read, and the page then shows the read") { test =>
      let w = tWorld();
      let short = tUnread(w.db, w.owner, 3);
      let r = tEvent(w.db, w.owner, "/works/${short.slug}", "start_read", "{}", tQueue());
      expectInt(test, r.resp.status, 200);
      expectHas(test, tMain(r), "Reading your draft");
      expectText(test, tStatusOf(w.db, short), "reading");
      expectTrue(test, runsGet(w.db, showReadKey(short.id)) != null, "the read is a run");
    }

## While it reads

    let tReading(w: TWorld): Work throws Bubble {
      worksSetStatus(w.db, w.work, "reading", null)
    }

    test("progress: all three stages are named while reading") { test =>
      let w = tWorld();
      let work = tReading(w);
      let html = tBodyOf(tGet(w.db, w.owner, "/works/${work.slug}", tKeyed()));
      expectHas(test, html, "Reading your draft");
      expectHas(test, html, "Sections");
      expectHas(test, html, "The spine");
      expectHas(test, html, "Connections");
      expectHas(test, html, "what develops, pays off, requires, or contradicts what");
    }

    test("progress: a reload mid-read recovers which stage is running") { test =>
      let w = tWorld();
      let work = tReading(w);
      tNode(w.db, work, "spine", "The trunk", null);
      let html = tBodyOf(tGet(w.db, w.owner, "/works/${work.slug}", tKeyed()));
      expectHas(test, html, "1 spine");
    }

    test("progress: a finished read shows the map, not the progress view") { test =>
      let w = tWorld();
      expectLacks(test, tBodyOf(tGet(w.db, w.owner, tPath(w.work, "read"), tKeyed())), "Reading your draft");
    }

    test("progress: the sections read so far are counted") { test =>
      let w = tWorld();
      let work = tReading(w);
      let html = tBodyOf(tGet(w.db, w.owner, "/works/${work.slug}", tKeyed()));
      expectHas(test, html, "0 of 1 read");
      w.db.exec("UPDATE sections SET status = 'read' WHERE work_id = $1", [work.id.toString()]);
      tBeat(w.db, work, "A beat");
      let later = tBodyOf(tGet(w.db, w.owner, "/works/${work.slug}", tKeyed()));
      expectHas(test, later, "1 of 1 read");
      expectHas(test, later, "1 beats");
    }

    test("progress: the badges number the sections while the first stage runs") { test =>
      let w = tWorld();
      let work = tReading(w);
      let html = tBodyOf(tGet(w.db, w.owner, "/works/${work.slug}", tKeyed()));
      expectHas(test, html, "class=\"mg-badge \"");
    }

    test("progress: the clock counts from when the run started") { test =>
      let w = tWorld();
      let work = tReading(w);
      w.db.exec("INSERT INTO runs (key, status, started_at) VALUES ($1, 'running', '2020-01-01 00:00:10')", [showReadKey(work.id)]);
      let html = tBodyOf(tGet(w.db, w.owner, "/works/${work.slug}", tKeyed()));
      expectHas(test, html, "id=\"read-clock\"");
      expectHas(test, html, "data-since=\"1577836810\"");
    }

    test("progress: the page polls while the read runs and not otherwise") { test =>
      let w = tWorld();
      expectLacks(test, tBodyOf(tPoll(w.db, w.owner, tPath(w.work, "read"), tKeyed())), "data-poll");
      let work = tReading(w);
      expectHas(test, tBodyOf(tPoll(w.db, w.owner, "/works/${work.slug}", tKeyed())), "data-poll=\\\"2\\\"");
      expectHas(test, tBodyOf(tGet(w.db, w.owner, "/works/${work.slug}", tKeyed())), "data-poll=\"2\"");
    }

    test("progress: a read whose job died is given up on") { test =>
      let w = tWorld();
      let work = tReading(w);
      w.db.exec("INSERT INTO runs (key, status, started_at) VALUES ($1, 'running', '2020-01-01 00:00:10')", [showReadKey(work.id)]);
      tGet(w.db, w.owner, "/works/${work.slug}", tKeyed());
      w.db.exec("UPDATE runs SET status = 'crashed', detail = 'process gone' WHERE key = $1", [showReadKey(work.id)]);
      let r = tPoll(w.db, w.owner, "/works/${work.slug}", tKeyed());
      expectText(test, tStatusOf(w.db, work), "failed");
      expectHas(test, tBodyOf(r), "The read crashed.");
    }

    test("progress: a read that has not been given a run shows no clock from nowhere") { test =>
      let w = tWorld();
      let work = tReading(w);
      let html = tBodyOf(tGet(w.db, w.owner, "/works/${work.slug}", tKeyed()));
      expectHas(test, html, "id=\"read-clock\"");
    }

## The poll while a pass is going

    test("poll: a document pass in flight makes the page poll and disables its button") { test =>
      let w = tWorld();
      tEvent(w.db, w.owner, tPath(w.work, "read"), "summarise_document", "{}", tQueue());
      let page = tGet(w.db, w.owner, tPath(w.work, "read"), tKeyed());
      expectHas(test, tBodyOf(page), "data-poll=\"2\"");
      expectHas(test, tBodyOf(page), "Reading it all…");
    }

    test("poll: the page stops polling when the pass has ended") { test =>
      let w = tWorld();
      tEvent(w.db, w.owner, tPath(w.work, "read"), "summarise_document", "{}", tQueue());
      w.db.exec("UPDATE runs SET status = 'done' WHERE key = $1", [showDocumentKey(w.work.id)]);
      expectLacks(test, tBodyOf(tGet(w.db, w.owner, tPath(w.work, "read"), tKeyed())), "data-poll");
    }
