defmodule MarginaliaWeb.LandingLive do
  @moduledoc """
  The pitch, as a draft, with Marginalia's notes in the margin.

  The page is the demo. Prose on the left, a dotted leader, and notes in the
  right-hand rail that arrive as you scroll past the paragraph they belong to —
  the same arrangement a writer gets on their own manuscript. Several of the
  notes argue with the pitch rather than selling it, which is the point: a tool
  that only flattered the text would be worthless, and demonstrating that is
  cheaper than promising it.

  One section per surface the product actually has, because a feature nobody
  can picture is a feature nobody asks for: the margin, the thread pinned to a
  paragraph, the graph, the rewrites, the editor. The worked examples play out
  on scroll rather than sitting there as screenshots, because the product is a
  conversation and a still image of a conversation sells nothing.

  The "will not do" section used to promise no rewritten sentences, ever. That
  stopped being true the day `Marginalia.Rewrite` shipped, and a pitch that
  contradicts the product is worse than one that undersells it — so the claim
  is now the narrower and truer one: there is exactly one door, the writer
  opens it, and nothing comes through it unasked.

  "Just the notes" drops the prose and leaves the rail.
  """
  use MarginaliaWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: nil,
       notes_only: false
     )}
  end

  # Where "upload a draft" should actually go. Logged out, that is
  # registration; logged in, registration redirects home, so sending them
  # there makes the button a no-op.
  # Uploading needs no account, so every call to action goes straight at the
  # upload — a signed-out visitor is given a guest on the way in.
  defp start_path(_scope), do: ~p"/works/new"

  @impl true
  def handle_event("toggle_notes", _params, socket) do
    {:noreply, assign(socket, notes_only: !socket.assigns.notes_only)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Reveal">
      // Notes arrive as you reach the paragraph they annotate, and the worked
      // examples play their turns in sequence once they're on screen. Both are
      // one-shot: re-animating on every scroll past would be nauseating.
      export default {
        mounted() {
          const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
          const targets = this.el.querySelectorAll("[data-reveal]");

          if (reduce || !("IntersectionObserver" in window)) return;

          // Only now does anything hide. Without JS, or before this runs, the
          // page is fully readable — a landing page that needs JS to show its
          // own copy is a landing page that sometimes shows nothing.
          this.el.classList.add("reveal-ready");

          this.io = new IntersectionObserver(
            (entries) => {
              entries.forEach((entry) => {
                if (!entry.isIntersecting) return;
                entry.target.classList.add("in");
                this.io.unobserve(entry.target);
              });
            },
            // fire a little before the top edge so the note is already there
            // by the time the eye arrives
            { rootMargin: "0px 0px -12% 0px", threshold: 0.15 }
          );

          targets.forEach((el) => this.io.observe(el));
        },

        destroyed() {
          if (this.io) this.io.disconnect();
        },
      };
    </script>

    <style>
      :root{
        --mg-paper:#fbfaf7; --mg-ink:#1c1a17; --mg-dim:#6b665e; --mg-rule:#e0dbd2;
        --mg-accent:#8a3324; --mg-margin:#f4f1ea;
        --mg-serif:"Iowan Old Style","Palatino Linotype",Palatino,Georgia,serif;
        --mg-sans:-apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif;
      }
      .mg{background:var(--mg-paper); color:var(--mg-ink); font-family:var(--mg-serif);
        font-size:17px; line-height:1.7; min-height:100vh; padding:0 1.5rem 8rem}
      .mg *{box-sizing:border-box}

      .mg-head{max-width:74rem; margin:0 auto; display:flex; align-items:baseline; gap:.9rem;
        padding:1.1rem 0 .8rem; border-bottom:1px solid var(--mg-rule);
        position:sticky; top:0; background:var(--mg-paper); z-index:5}
      .mg-brand{font-family:var(--mg-sans); font-size:.72rem; letter-spacing:.22em;
        text-transform:uppercase; font-weight:600}
      .mg-head .right{margin-left:auto; font-family:var(--mg-sans); font-size:.78rem;
        display:flex; gap:.9rem; align-items:center}
      .mg-head a{color:var(--mg-dim); text-decoration:none}
      .mg-head a:hover{color:var(--mg-accent)}
      .mg-toggle{font-family:var(--mg-sans); font-size:.72rem; background:none; cursor:pointer;
        border:1px solid var(--mg-rule); border-radius:3px; padding:.25rem .6rem; color:var(--mg-dim)}
      .mg-toggle:hover{border-color:var(--mg-accent); color:var(--mg-accent)}
      .mg-toggle.on{background:var(--mg-accent); border-color:var(--mg-accent); color:#fff}

      /* ---- the rail ---------------------------------------------------- */
      .sec{display:grid; grid-template-columns:minmax(0,58ch) 3rem minmax(0,30ch);
        justify-content:center; align-items:start; column-gap:0}
      .sec-title{grid-column:1; padding-right:.5rem; min-width:0}
      .sec-main{grid-column:1; padding-right:.5rem; min-width:0}
      .sec-aside{grid-column:3; padding-left:.5rem; position:sticky; top:5rem; padding-bottom:2.5rem}
      .sec.head .sec-aside{grid-row:1 / 3}
      .sec-leader{grid-column:2; grid-row:1; border-top:1px dotted #c3bcb0; height:0;
        margin-top:1.9rem; align-self:start}
      .sec.head{margin-top:3.4rem}
      .sec.head:first-of-type{margin-top:.5rem}
      .sec:not(.head){margin-top:1.6rem}
      .sec:not(.head) .sec-leader{display:none}

      /* ---- notes, arriving --------------------------------------------- */
      .note{font-family:var(--mg-sans); font-size:.79rem; line-height:1.6; color:var(--mg-ink);
        background:var(--mg-margin); border-left:2px solid var(--mg-accent);
        padding:.7rem .85rem; border-radius:0 3px 3px 0}
      /* the hiding only exists once the observer is live — see the hook */
      .reveal-ready .note{opacity:0; transform:translateY(10px);
        transition:opacity .5s ease, transform .5s ease;
        transition-delay:calc(var(--i, 0) * 140ms)}
      .reveal-ready .note.in{opacity:1; transform:none}
      .note + .note{margin-top:.7rem}
      .note b{font-weight:600}
      .note .who{display:block; font-size:.62rem; letter-spacing:.1em; text-transform:uppercase;
        color:var(--mg-dim); margin-bottom:.35rem}
      .note.act{background:#fff; border-left-color:var(--mg-ink)}
      .note-cta{display:inline-block; margin-top:.55rem; font-family:var(--mg-sans);
        font-size:.74rem; font-weight:600; text-decoration:none; color:var(--mg-paper);
        background:var(--mg-ink); padding:.35rem .7rem; border-radius:2px}
      .note-cta:hover{background:var(--mg-accent)}

      .mg h1{font-size:2.5rem; line-height:1.14; letter-spacing:-.022em; margin:1.2rem 0 .9rem;
        font-weight:600}
      .mg h2{font-size:1.3rem; margin:0 0 .7rem; font-weight:600; letter-spacing:-.01em}
      .mg p{margin:0 0 1.05rem}
      .mg .lede{font-size:1.14rem; color:var(--mg-dim); margin-bottom:1.5rem}
      .mg .fine{font-family:var(--mg-sans); font-size:.75rem; color:var(--mg-dim)}

      .cta{display:inline-block; font-family:var(--mg-sans); font-size:.9rem; font-weight:600;
        background:var(--mg-ink); color:var(--mg-paper); padding:.7rem 1.4rem; text-decoration:none;
        border-radius:2px}
      .cta:hover{background:var(--mg-accent)}
      .cta.ghost{background:none; color:var(--mg-ink); border:1px solid var(--mg-rule)}
      .cta.ghost:hover{border-color:var(--mg-accent); color:var(--mg-accent)}
      .ctas{display:flex; gap:.6rem; flex-wrap:wrap; margin:1.4rem 0 .5rem}

      .demo{border:1px solid var(--mg-rule); background:#fff; padding:1.1rem 1.3rem; margin:1.3rem 0}
      .demo .src{font-size:.98rem; line-height:1.65; color:#2a2723; margin:0}
      .demo .mark{background:#fdf2c9; padding:0 .1em}

      /* ---- an exchange, playing out ------------------------------------ */
      .play{border:1px solid var(--mg-rule); background:#fff; margin:1.3rem 0;
        font-family:var(--mg-sans); font-size:.84rem; line-height:1.6}
      .play .cap{font-size:.62rem; letter-spacing:.1em; text-transform:uppercase;
        color:var(--mg-dim); padding:.55rem .95rem; border-bottom:1px solid var(--mg-rule)}
      .play .turns{padding:.85rem .95rem; display:flex; flex-direction:column; gap:.7rem}
      .reveal-ready .turn{opacity:0; transform:translateY(6px);
        transition:opacity .45s ease, transform .45s ease;
        transition-delay:calc(var(--i, 0) * 800ms)}
      .reveal-ready .play.in .turn{opacity:1; transform:none}
      .turn.you{align-self:flex-end; max-width:85%; background:var(--mg-ink); color:var(--mg-paper);
        padding:.45rem .7rem; border-radius:3px}
      .turn.it{max-width:96%}
      .turn.it q{quotes:none; display:block; border-left:2px solid var(--mg-rule);
        padding-left:.6rem; margin:.4rem 0; color:var(--mg-dim); font-family:var(--mg-serif);
        font-size:.9rem}
      .turn.think{color:var(--mg-dim); font-style:italic; font-size:.78rem}

      .wont{border-top:2px solid var(--mg-ink); border-bottom:2px solid var(--mg-ink);
        padding:1.2rem 0; margin:1.5rem 0}
      .wont ul{margin:.5rem 0 0; padding-left:1.1rem}
      .wont li{margin:.3rem 0}

      /* ---- the filter row, as the read view has it ---------------------- */
      .mg-chips{display:flex; gap:1.1rem; flex-wrap:wrap; font-family:var(--mg-sans);
        font-size:.7rem; letter-spacing:.11em; text-transform:uppercase; color:var(--dim, #6b665e);
        border-bottom:1px solid var(--mg-rule); padding-bottom:.55rem; margin:0 0 .9rem}
      .mg-chips b{font-weight:600; color:var(--mg-ink); border-bottom:2px solid var(--mg-accent);
        padding-bottom:.55rem; margin-bottom:-.57rem}

      /* ---- candidates, side by side ------------------------------------- */
      .mg-cands{border:1px solid var(--mg-rule); background:#fff; margin:1.3rem 0}
      .mg-cands .cap{font-family:var(--mg-sans); font-size:.62rem; letter-spacing:.1em;
        text-transform:uppercase; color:var(--mg-dim); padding:.55rem .95rem;
        border-bottom:1px solid var(--mg-rule)}
      .mg-cands .c{padding:.8rem .95rem}
      .mg-cands .c + .c{border-top:1px solid var(--mg-rule)}
      .mg-cands .c.orig{background:var(--mg-margin)}
      .mg-cands .lab{display:block; font-family:var(--mg-sans); font-size:.62rem; letter-spacing:.1em;
        text-transform:uppercase; color:var(--mg-dim); margin-bottom:.4rem; font-weight:600}
      .mg-cands .lab em{font-style:normal; font-weight:400; letter-spacing:.04em;
        text-transform:none; font-size:.72rem}
      .mg-cands p{margin:0; font-size:1rem; line-height:1.6}
      .mg-cands .c.orig p{color:var(--mg-dim)}
      .mg-cands del{text-decoration:none; background:#f7e9e5; color:#8a3324; padding:0 .08em}
      .mg-cands ins{text-decoration:none; background:#e8f0e6; padding:0 .08em}
      .reveal-ready .mg-cands .c.alt{opacity:0; transform:translateY(6px);
        transition:opacity .45s ease, transform .45s ease;
        transition-delay:calc(var(--i, 0) * 600ms)}
      .reveal-ready .mg-cands.in .c.alt{opacity:1; transform:none}

      /* ---- what leads to what -------------------------------------------- */
      .mg-edges{border:1px solid var(--mg-rule); background:#fff; margin:1.3rem 0;
        font-family:var(--mg-sans); font-size:.82rem; line-height:1.5}
      .mg-edges .cap{font-size:.62rem; letter-spacing:.1em; text-transform:uppercase;
        color:var(--mg-dim); padding:.55rem .95rem; border-bottom:1px solid var(--mg-rule)}
      .mg-edges .e{display:flex; align-items:baseline; gap:.55rem; flex-wrap:wrap;
        padding:.6rem .95rem}
      .mg-edges .e + .e{border-top:1px solid #f0ece4}
      .mg-edges .n{color:var(--mg-ink)}
      .mg-edges .n::before{content:"●"; font-size:.5rem; vertical-align:.18em;
        margin-right:.4rem; color:var(--mg-accent)}
      .mg-edges .n.hollow::before{content:"○"; color:var(--mg-dim)}
      .mg-edges .rel{font-size:.64rem; letter-spacing:.1em; text-transform:uppercase;
        color:var(--mg-dim); border:1px solid var(--mg-rule); border-radius:2px;
        padding:.1rem .35rem}
      .mg-edges .why{flex-basis:100%; color:var(--mg-dim); font-size:.78rem; margin-top:.15rem}

      /* ---- the thread in the gutter -------------------------------------- */
      .mg-gut{border:1px solid var(--mg-rule); background:#fff; margin:1.3rem 0;
        padding:1rem 1.2rem .95rem; position:relative}
      .mg-gut .tick{position:absolute; left:.5rem; top:1.35rem; width:2px; height:2.6rem;
        background:var(--mg-accent)}
      .mg-gut p{margin:0 0 .7rem; font-size:1rem; line-height:1.62}
      .mg-gut .turns{border-left:2px solid var(--mg-rule); padding-left:.85rem;
        font-family:var(--mg-sans); font-size:.82rem; line-height:1.55;
        display:flex; flex-direction:column; gap:.5rem}
      .mg-gut .turns .you{color:var(--mg-ink); font-weight:600}
      .mg-gut .turns .it{color:var(--mg-dim)}

      /* ---- notes-only --------------------------------------------------- */
      .notes-only .sec-main, .notes-only .sec-leader{display:none}
      .notes-only .sec{grid-template-columns:minmax(0,62ch)}
      .notes-only .sec-title{padding-right:0; margin-bottom:.3rem}
      .notes-only .sec.head .sec-aside{grid-row:auto}
      .notes-only .sec-aside{grid-column:1; position:static; padding-left:0; padding-bottom:0;
        margin-top:.6rem}
      .notes-only .sec:not(.head){margin-top:1.6rem}
      .notes-only .sec.head{margin-top:2.4rem}
      .notes-only .note{font-size:.92rem}

      @media (max-width:1000px){
        .sec{grid-template-columns:minmax(0,1fr)}
        .sec-title, .sec-main{grid-column:1; padding-right:0}
        .sec-leader{display:none}
        .sec-aside{grid-column:1; grid-row:auto; position:static; padding-left:0;
          padding-bottom:0; margin:.2rem 0 1.7rem; order:2}
        .sec.head .sec-aside{grid-row:auto}
        .mg h1{font-size:2rem}
      }
    </style>

    <div id="landing" phx-hook=".Reveal" class={"mg" <> if(@notes_only, do: " notes-only", else: "")}>
      <div class="mg-head">
        <span class="mg-brand">Marginalia</span>
        <span class="right">
          <button class={"mg-toggle" <> if(@notes_only, do: " on", else: "")} phx-click="toggle_notes">
            just the notes
          </button>
          <%= if @current_scope do %>
            <.link navigate={~p"/works"}>Your drafts</.link>
          <% else %>
            <.link navigate={~p"/users/log-in"}>Log in</.link>
          <% end %>
        </span>
      </div>

      <section class="sec head">
        <div class="sec-title">
          <h1>Someone who has actually read the whole thing.</h1>
        </div>
        <div class="sec-leader"></div>
        <div class="sec-main">
          <p class="lede">
            Upload a draft. Marginalia reads it end to end, maps what's on the page, and then
            argues with you about it in the margin — one thread per paragraph, pinned where it
            belongs. No account, no setup.
          </p>
          <div class="ctas">
            <.link navigate={start_path(@current_scope)} class="cta">Upload a draft</.link>
            <%= if !@current_scope do %>
              <.link navigate={~p"/users/log-in"} class="cta ghost">Log in</.link>
            <% end %>
          </div>
          <p class="fine">Free while it's new. Your draft is private to whoever has its link.</p>
        </div>
        <aside class="sec-aside">
          <div class="note" data-reveal style="--i:0">
            <span class="who">note</span>
            <b>marginalia</b>, <i>n.</i> — what a reader leaves in the margin. The book goes back
            on the shelf exactly as it was printed. Everything down this side of the page is the
            product, annotating its own pitch as you scroll.
          </div>
        </aside>
      </section>

      <section class="sec head">
        <div class="sec-title">
          <h2>Nobody finishes your draft</h2>
        </div>
        <div class="sec-leader"></div>
        <div class="sec-main">
          <p>
            Your writing group reads the first ten pages on the train. The friend who swore they
            would get to it is on chapter three, four months in. The agent read a sample. Nobody
            holds the whole book in their head at once, which is exactly where the problems live:
            the thread you set up on page 30 and abandoned by 140, the two chapters doing the same
            job, the ending that pays off a promise the opening never made.
          </p>
        </div>
        <aside class="sec-aside">
          <div class="note" data-reveal style="--i:0">
            <span class="who">note</span>
            This is the strongest paragraph on the page because it is the only one about the
            reader rather than the tool. It also makes a promise — "holds the whole book" — that
            the section on limits has to pay off honestly, or this pitch has the same problem it
            is describing.
          </div>
        </aside>
      </section>

      <section class="sec head">
        <div class="sec-title">
          <h2>It reads all of it, and you watch</h2>
        </div>
        <div class="sec-leader"></div>
        <div class="sec-main">
          <p>
            Hand it the file you would hand a reader. Novel, essay collection, thesis chapter, or
            four years of blog posts you suspect are secretly one book. You confirm how it is
            divided — about a minute of clicking — and then the reading happens in front of you,
            section by section, in order, with the notes landing on the page as they are made.
          </p>
          <p>
            It goes over the draft three times. Once through each section for its beats: what
            turns, what is revealed, what shifts. Once across the whole thing for the spine, the
            threads and the questions the draft opens whether or not it closes them. Then once
            more to draw the lines between sections — what develops what, what pays off what, what
            contradicts what.
          </p>
        </div>
        <aside class="sec-aside">
          <div class="note" data-reveal style="--i:0">
            <span class="who">note</span>
            "About a minute of clicking" is the version of this sentence that respects the reader.
            The earlier draft called it a feature and hoped a comma would carry it.
          </div>
          <div class="note" data-reveal style="--i:1">
            <span class="who">note</span>
            The word doing the most work here is <b>watch</b>. The reading is visible while it
            happens, which is the difference between a progress bar and being read to.
          </div>
        </aside>
      </section>

      <section class="sec head">
        <div class="sec-title">
          <h2>Pinned to your own sentences</h2>
        </div>
        <div class="sec-leader"></div>
        <div class="sec-main">
          <p>
            Every observation carries a verbatim line from your draft. Not a paraphrase, not a
            summary — the sentence itself, as you wrote it, line breaks and all. If it cannot find
            the line in your text, the observation is thrown away before you ever see it.
          </p>
          <div class="demo">
            <p class="src">
              She had been standing at the window for an hour before anyone noticed, and by then
              the light had gone completely. <span class="mark">"You can't keep doing this," her
              brother said, from the doorway. He did not come in.</span>
            </p>
          </div>
        </div>
        <aside class="sec-aside">
          <div class="note" data-reveal style="--i:0">
            <span class="who">note</span>
            He does not come in here, and he does not come in at the hospital in §14 either. Twice
            is a pattern; three times is a decision. Is that what you meant by him?
          </div>
          <div class="note" data-reveal style="--i:1">
            <span class="who">note</span>
            This is the claim the product rests on, and the one worth being suspicious of. A tool
            that will confidently quote a sentence you never wrote has told you nothing you can
            trust about anything else.
          </div>
        </aside>
      </section>

      <section class="sec head">
        <div class="sec-title">
          <h2>The page, with its notes in the margin</h2>
        </div>
        <div class="sec-leader"></div>
        <div class="sec-main">
          <p>
            What you get back is your draft, laid out to be read, with every note sitting level
            with the line that caused it. The highlight under the prose is the exact span it is
            anchored to. Nothing is stacked at the top of a section hoping you will work out which
            paragraph it meant.
          </p>
          <div class="mg-chips">
            <b>Everything</b>
            <span>Beats</span> <span>Connections</span> <span>Tensions</span>
          </div>
          <p>
            It opens on everything, and the filter narrows what the margin is about rather than
            how much of it there is. <b>Beats</b>
            are what the draft does, in order. <b>Connections</b>
            are what reaches across sections. <b>Tensions</b>
            are where it argues with itself.
          </p>
          <p>
            A map of the draft sits in the left gutter. It is drawn to scale — a sixteen-hundred
            word section is five times the block a three-hundred word one gets — so the shape of
            the thing is visible before you have read a line of it. Click any block to land there.
          </p>
        </div>
        <aside class="sec-aside">
          <div class="note" data-reveal style="--i:0">
            <span class="who">note</span>
            Drawn to scale is a small idea that does a large amount of work. A contents list tells
            you the order; a map tells you that chapter eleven is somehow a third of the book.
          </div>
          <div class="note" data-reveal style="--i:1">
            <span class="who">note</span>
            "Laid out to be read" is doing some quiet bragging. Fine, as long as the page actually
            is — which is checkable in about four seconds, so the risk is low.
          </div>
        </aside>
      </section>

      <section class="sec head">
        <div class="sec-title">
          <h2>A thread on one paragraph</h2>
        </div>
        <div class="sec-leader"></div>
        <div class="sec-main">
          <p>
            Move the pointer to the left edge of any paragraph and a hairline appears in the
            gutter. Click it and a conversation opens underneath that paragraph, about that
            paragraph, already holding it. No re-explaining which bit you meant, no scrolling back
            to check. Close it and it is still there tomorrow.
          </p>

          <div class="mg-gut" data-reveal>
            <span class="tick"></span>
            <p>
              He did not come in. She heard him shift his weight in the doorway and then, after a
              while, the stairs.
            </p>
            <div class="turns">
              <div class="you">Is this doing too much work for one line?</div>
              <div class="it">
                It is carrying the whole relationship, and it can — the doorway is the third time
                he has stopped at a threshold. What it cannot also carry is the time passing.
                "After a while" is the only thing in the paragraph that is vague, and it is
                sitting next to the two most concrete images in the chapter.
              </div>
            </div>
          </div>

          <p>
            Select a passage instead and three things come up at the end of it: talk about that
            spot, ask for rewrites of it, or carry it into the conversation you are already having.
            The bigger chat lives in a drawer over half the page, holds as many separate
            conversations as you want to keep apart, and has three stances — what is on the page,
            questions that open the next draft, or pressure-testing an idea against the draft.
          </p>

          <div class="play" data-reveal>
            <div class="cap">A real exchange, on a real draft</div>
            <div class="turns">
              <div class="turn you" style="--i:0">Which thread did I set up and never pay off?</div>
              <div class="turn think" style="--i:1">reading…</div>
              <div class="turn it" style="--i:2">
                The five-point scale. You name it, you point at Level 3 as the early warning, and
                then Levels 1, 2, 4 and 5 never appear.
                <q>Pay close attention to Level 3 — this is your early warning sign.</q>
                A reader holding that page has no idea what a 3 is a 3 <i>of</i>. Is the full scale
                written somewhere, or did it only ever exist as Level 3?
              </div>
            </div>
          </div>
        </div>
        <aside class="sec-aside">
          <div class="note" data-reveal style="--i:0">
            <span class="who">note</span>
            This is the section that would sell the product if anyone read it, and it is the sixth
            one down. The hairline in the gutter is the whole idea: an interface that is invisible
            until you go looking for it, on prose that should be the only thing on screen.
          </div>
          <div class="note" data-reveal style="--i:1">
            <span class="who">note</span>
            That exchange is not staged. It is what came back the first time this was pointed at a
            real manuscript, quote and all.
          </div>
          <div class="note" data-reveal style="--i:2">
            <span class="who">note</span>
            Three stances is one more than most people will ever use. Naming them here is honest
            and it is also clutter — the sentence would survive losing its second half.
          </div>
        </aside>
      </section>

      <section class="sec head">
        <div class="sec-title">
          <h2>What leads to what</h2>
        </div>
        <div class="sec-leader"></div>
        <div class="sec-main">
          <p>
            Beside the page there is the draft as a structure: every move it makes, and every line
            drawn between them. Hover a row and the panel fills in with what it says, so you can
            move down the whole draft without clicking anything. Click to keep one there, and it
            holds its section, your own sentence underneath it, and everything it follows from or
            leads to.
          </p>

          <div class="mg-edges" data-reveal>
            <div class="cap">Lines it drew across sections</div>
            <div class="e">
              <span class="n">The argument about the car</span>
              <span class="rel">develops</span>
              <span class="n">He stops answering the phone</span>
              <span class="why">
                The silence in §11 is only legible as a refusal because of what was said in §4.
              </span>
            </div>
            <div class="e">
              <span class="n">A five-point scale is named</span>
              <span class="rel">requires</span>
              <span class="n hollow">The scale is never given</span>
              <span class="why">
                Level 3 is used as an early warning four times. Levels 1, 2, 4 and 5 do not exist.
              </span>
            </div>
            <div class="e">
              <span class="n">Grief as something survived</span>
              <span class="rel">tension</span>
              <span class="n">Grief as something owed</span>
              <span class="why">
                The opening and chapter nine want different books, and chapter nine is better.
              </span>
            </div>
          </div>

          <p>
            A filled dot is anchored to a line you wrote. A hollow one is structural — a move with
            no single sentence behind it, which is usually where the missing scene is. Alongside
            it: the spine the whole draft hangs off, the threads that run across it and whether
            each is carried, thin or dropped, and the questions the draft opens.
          </p>
        </div>
        <aside class="sec-aside">
          <div class="note" data-reveal style="--i:0">
            <span class="who">note</span>
            A dropped thread is the most useful thing the graph produces and it is mentioned in a
            subordinate clause. That is the wrong shape for the best thing in the section.
          </div>
          <div class="note act" data-reveal style="--i:1">
            <span class="who">your turn</span>
            Every draft has one. Yours is probably a character who stops having opinions around
            the midpoint.
            <.link navigate={start_path(@current_scope)} class="note-cta">Find yours →</.link>
          </div>
        </aside>
      </section>

      <section class="sec head">
        <div class="sec-title">
          <h2>The one place it writes</h2>
        </div>
        <div class="sec-leader"></div>
        <div class="sec-main">
          <p>
            Select a span and ask, and it will hand you three rewrites of it. This is the only
            door, it only opens from your side, and nothing comes through it unasked. The chat has
            no path here at all — asking a question about a paragraph and asking for versions of it
            are different requests, and collapsing them is how an editor becomes a ghostwriter.
          </p>

          <div class="mg-cands" data-reveal>
            <div class="cap">Three candidates, on a span you chose</div>
            <div class="c orig">
              <span class="lab">your line</span>
              <p>
                It was, in a sense, the beginning of something that would eventually change
                everything about the way she saw her father.
              </p>
            </div>
            <div class="c alt" style="--i:0">
              <span class="lab">Cuts the gloss <em>· loses the narrator's distance</em></span>
              <p>It <ins>changed how</ins> she saw her father.</p>
            </div>
            <div class="c alt" style="--i:1">
              <span class="lab">Puts the change last <em>· slower into the paragraph</em></span>
              <p>
                <del>It was, in a sense, the beginning of</del>
                <ins>She would not see her father the same way again, and this was where it</ins>
                <ins>started</ins>.
              </p>
            </div>
            <div class="c alt" style="--i:2">
              <span class="lab">Hands it to the image <em>· only works if the car is in the scene</em></span>
              <p><ins>She watched him back the car out, and something in it went</ins>.</p>
            </div>
          </div>

          <p>
            Three, not one, because a single suggestion reads as the answer. Each is labelled with
            the move it makes and <b>what it costs</b> — every rewrite gives something up, and one
            that claims not to has not been thought about. They are shown as a diff over your own
            line, in place, so you can see exactly what changed. It never applies anything.
          </p>

          <div class="wont">
            <p>What it still will not do, and this part has not moved:</p>
            <ul>
              <li>No prose you did not ask for, ever, from the chat.</li>
              <li>No generated scenes, dialogue or filled-in gaps.</li>
              <li>No score, no grade, no rating out of ten.</li>
              <li>
                No "show, don't tell" — generic craft advice fits every manuscript, which means it
                is about none of them.
              </li>
            </ul>
          </div>

          <div class="play" data-reveal>
            <div class="cap">Asking the chat anyway</div>
            <div class="turns">
              <div class="turn you" style="--i:0">
                Rewrite my opening paragraph so it hits harder.
              </div>
              <div class="turn think" style="--i:1">reading…</div>
              <div class="turn it" style="--i:2">
                Your opening is the orientation box — <i>take a breath and let your shoulders
                drop</i>. That is already doing the work you are hoping a hook would do.
                <br /><br />
                So the question is not how to make it hit harder. It is: what do you want the reader
                to feel by the end of the first paragraph — relief, or urgency? Right now it is
                relief. Urgency is the opposite of what this book promises. Those two pull against
                each other. Where did you feel it was not landing?
              </div>
            </div>
          </div>
        </div>
        <aside class="sec-aside">
          <div class="note" data-reveal style="--i:0">
            <span class="who">tension</span>
            This section argues with the one before it. The front of this page used to promise no
            rewritten sentences, ever, and here are three of them. The narrow claim is the true
            one, and a page that quietly dropped the old promise would be worth less than a page
            that says out loud which one it broke.
          </div>
          <div class="note" data-reveal style="--i:1">
            <span class="who">note</span>
            "It never applies anything" is the load-bearing sentence and it is last. A reader who
            stops after the diff has read a ghostwriter.
          </div>
          <div class="note act" data-reveal style="--i:2">
            <span class="who">your turn</span>
            The chat's half of this is testable in about four seconds. Upload something and ask it
            to write for you.
            <.link navigate={start_path(@current_scope)} class="note-cta">Try to break it →</.link>
          </div>
        </aside>
      </section>

      <section class="sec head">
        <div class="sec-title">
          <h2>Then you change it yourself</h2>
        </div>
        <div class="sec-leader"></div>
        <div class="sec-main">
          <p>
            Click into any paragraph on the page and it becomes editable, in your own words, in
            the markdown you wrote it in. Save and the draft is the draft — which means you can
            answer a rewrite with a third thing that is neither your line nor its version, while
            both are still in front of you.
          </p>
          <p>
            When a line changes, the notes anchored to it are marked as belonging to a sentence
            that has moved rather than quietly kept. A note about a paragraph you have since
            rewritten is not an observation any more, it is a fossil, and pretending otherwise
            would undo the only thing this is careful about.
          </p>
        </div>
        <aside class="sec-aside">
          <div class="note" data-reveal style="--i:0">
            <span class="who">note</span>
            "It is a fossil" is the best phrase in this section and it is explaining a housekeeping
            detail. Consider whether the thing it describes deserves to be the section.
          </div>
        </aside>
      </section>

      <section class="sec head">
        <div class="sec-title">
          <h2>What it costs, and where your draft goes</h2>
        </div>
        <div class="sec-leader"></div>
        <div class="sec-main">
          <p>
            No account to upload. A minute of your attention at the start, then a few minutes of
            reading while you watch. A draft is private to whoever holds its link — the URL is the
            permission, nothing is listed publicly, and search engines are told to stay out.
            Send the link to your writing group and they can read the margin with you.
          </p>
          <p>
            Your draft is stored so you can come back to it, and deleting it deletes it: the text,
            the map, the threads, the conversations. It is sent to a model to be read. It is not
            used to train anything.
          </p>
          <p class="fine">
            Plain text and markdown, up to 120,000 words. A hundred questions per account while
            this is free, which is enough to find out whether it is any good. Everything above
            describes what it does now, not what is planned.
          </p>
        </div>
        <aside class="sec-aside">
          <div class="note" data-reveal style="--i:0">
            <span class="who">note</span>
            You promise "it reads all of it" five sections up and then cap it at 120,000 words
            here. Both are true and they read as a contradiction in this order. Either move the
            limit up or soften the claim.
          </div>
          <div class="note" data-reveal style="--i:1">
            <span class="who">tension</span>
            "Private to whoever holds its link" and "send the link to your writing group" are the
            same sentence pointed in opposite directions. That is the actual security model and it
            is worth one more line saying a link is a key.
          </div>
        </aside>
      </section>

      <section class="sec head">
        <div class="sec-title">
          <h2>Bring the draft in the drawer.</h2>
        </div>
        <div class="sec-leader"></div>
        <div class="sec-main">
          <div class="ctas">
            <.link navigate={start_path(@current_scope)} class="cta">Upload a draft</.link>
          </div>
          <p class="fine">It reads. You decide. That division is the product.</p>
        </div>
        <aside class="sec-aside">
          <div class="note act" data-reveal style="--i:0">
            <span class="who">last note</span>
            Ten sections, one ask, no testimonials, no logos. The page is doing the thing it is
            selling, and two of the notes above disagree with the paragraph they are attached to,
            which is the only demo available to a product nobody has used yet.
            <.link navigate={start_path(@current_scope)} class="note-cta">Upload a draft →</.link>
          </div>
        </aside>
      </section>
    </div>
    """
  end
end
