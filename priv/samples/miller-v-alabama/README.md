# Miller v. Alabama — a three-document fixture

Three public-domain documents from one Supreme Court case, chosen because they
argue with each other. Used to exercise the linker: everything here is a real
reference between real texts, so a link the system proposes is either right or
wrong on the merits rather than on a coin flip.

| File | What it is | Words |
|------|------------|-------|
| `01-opinion-of-the-court.md` | Syllabus and Justice Kagan's opinion for the Court | ~10,300 |
| `02-concurrence-and-dissents.md` | Breyer's concurrence; the Roberts, Thomas and Alito dissents | ~8,800 |
| `03-oral-argument.md` | The March 20, 2012 argument, Stevenson for Miller, Neiman for Alabama | ~11,600 |

*Miller v. Alabama*, 567 U. S. 460 (2012), Nos. 10–9646 and 10–9647, argued
March 20, 2012, decided June 25, 2012. Held: mandatory life without parole for a
juvenile homicide offender violates the Eighth Amendment.

## How they are tied together

- **Explicit pin cites, both directions.** The dissents point back at the majority
  23 times ("*Ante,* at 17"); the majority answers the dissents 13 times
  ("*Post,* at 6"). Doc 1 and doc 2 are two halves of one argument that was
  written to be read against itself.
- **A shared spine of precedent.** *Graham* v. *Florida* appears 80 / 57 / 41
  times across the three, *Roper* v. *Simmons* 39 / 29 / 13, *Harmelin* 11 / 12 / 9.
  Majority and dissent read the same cases to opposite ends, which is a harder and
  more interesting linking problem than agreement.
- **The argument prefigures the opinions.** Scalia's "what about 50 years?" in doc 3
  becomes the dissent's line-drawing objection in doc 2; Ginsburg's *Roper* quotation
  at argument turns up in the majority's treatment of deterrence. The same people
  are saying the same things in two registers, one transcribed and one drafted.
- **A companion case running through all three.** Kuntrell Jackson (No. 10–9647)
  was decided in the same opinion; Breyer's concurrence is about him alone, and the
  Arkansas dissent by Danielson, J., is quoted in both doc 1 and doc 2.

## Provenance

- Opinions: Cornell LII's copy of the slip opinion, <https://www.law.cornell.edu/supremecourt/text/10-9646>.
  LII drops the hyphen where the slip opinion broke a word across a line
  ("nonhomi cide", "pen- alty"); those were repaired against the official bound
  volume, <https://www.supremecourt.gov/opinions/boundvolumes/567bv.pdf>, which keeps a
  soft hyphen at every such break. 64 words were rejoined, each one verified to
  appear whole in the bound volume and never as two adjacent words.
- Transcript: <https://www.supremecourt.gov/oral_arguments/argument_transcripts/2011/10-9646.pdf>,
  line numbers and page furniture stripped, speaker turns joined into paragraphs.
- The companion argument in Jackson v. Hobbs is at
  `.../argument_transcripts/2011/10-9647.pdf` if a fourth document is ever wanted.

Works of the United States government; no copyright.
