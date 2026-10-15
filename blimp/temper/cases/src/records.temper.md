# The shapes a case is made of

A case has no table: it is a name several drafts agree on (`works.collection`)
and a role each plays in it (`works.collection_role`). So the records here are
not rows. They are what `Marginalia.Cases` assembled in maps, as classes: a
`CaseStudy` is one collection with its drafts, the links between them and the
edges on those links, and the counts a contents page shows.

The Elixir named the pieces with atom-key maps (`%{name, slug, works, links,
by_link, holding, ...}`); the field names are the same in camelCase.
`Case` is not used as a class name (`case` is a Temper keyword neighbour and
`Case` is too easily shadowed), so the record is `CaseStudy`.

    let { Work } = import("works/src");
    let { Link, LinkEdgeEnds } = import("links/src");

## CaseStudy

`works` are in reading order (opinion, concurrence, dissent, argument, then
anything else, stable). `links` are only the links with both ends inside this
collection. `byLink` maps a link id to its edges, each with the two nodes it
joins, ordered `ordinal` then `id`. `holding` is the Court's own sentence, or
null. `read` counts drafts whose status is `read`; `words` sums their word
counts; `edges` is the total edge count over `byLink`; `missing` is every
unlinked pair of drafts (lower id first); `kin` is the other cases this one is
related to, strongest first.

    export class CaseStudy(
      public name: String,
      public slug: String,
      public works: List<Work>,
      public links: List<Link>,
      public byLink: Map<Int, List<LinkEdgeEnds>>,
      public holding: String?,
      public read: Int,
      public words: Int,
      public edges: Int,
      public missing: List<CasePair>,
      public kin: List<CaseKin>,
    ) {}

    export class CasePair(public a: Work, public b: Work) {}

One link that leaves this case: `lead` is the draft inside it, `other` the one
outside, `caseName` the other draft's collection, `edges` how many edges the
link has.

    export class CaseKin(
      public linkId: Int,
      public lead: Work,
      public other: Work,
      public caseName: String,
      public edges: Int,
    ) {}

## Ways in

A pairing inside a case, ordered so the draft a reader would lead with (the
opinion before the dissent, either before an advocate) is `lead`.

    export class CaseWay(
      public link: Link,
      public lead: Work,
      public other: Work,
      public edges: Int,
    ) {}

## What a case looks like on a contents page

`kinds` is how many edges of each type, most first (ties in type-name order).

    export class CaseKind(public edgeType: String, public count: Int) {}

    export class CasePreview(
      public summary: String?,
      public sharpest: List<LinkEdgeEnds>,
      public kinds: List<CaseKind>,
      public impression: String?,
    ) {}

## One document, read against the rest

A source is a link the lead draft is on, with the draft at its other end.
`elsewhere` is null for a link inside the case and the other draft's
collection for one that leaves it.

    export class CaseSource(public link: Link, public work: Work, public elsewhere: String?) {}

A margin note, in the shape `Links.margin` gives, stamped with the document it
came from. `key` is `link:<edge id>`, `kind` the edge type, `quote` the
sentence in the lead it is anchored to, `title` the far node's title with an
arrow (`→ ` when the lead's node is the edge's `from`, `← ` otherwise), `body`
the rationale with A and B resolved to titles. `far*` describe the node at the
other end; `farSection` is that node's section ordinal in its own draft.

    export class CaseNote(
      public key: String,
      public sectionId: Int,
      public kind: String,
      public quote: String,
      public title: String,
      public body: String,
      public stale: Boolean,
      public edgeId: Int,
      public peer: Int,
      public farTitle: String,
      public farBody: String?,
      public farQuote: String?,
      public farKind: String,
      public farSection: Int?,
      public fromWork: Int,
      public fromTitle: String,
      public fromRole: String?,
      public fromCase: String?,
      public linkId: Int,
    ) {}

`page` (the Elixir's `Reading.page(lead, notes:)`) is not part of this record:
the reading library builds it from `lead` and `notes`.

    export class CaseReading(
      public lead: Work,
      public sources: List<CaseSource>,
      public notes: List<CaseNote>,
    ) {}

## The record of a case

`Marginalia.Cases.Record`: facts true of a case rather than of one document.
`question` is written only where it says something the holding does not.

    export class CaseRecord(
      public name: String,
      public docket: String,
      public argued: String,
      public decided: String,
      public question: String?,
    ) {}

## Chat

`text` is set on success, `error` on failure: `empty_reply`, or the model
client's `kind: detail`.

    export class CaseChatResult(public text: String?, public error: String?) {}
