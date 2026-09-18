# One employment contract, renegotiated twice

Three versions of the same agreement between American Axle & Manufacturing Holdings,
Inc. and David C. Dauch, its President and Chief Executive Officer. Each one amends and
restates the last in its entirety, so all three are complete contracts covering the same
26 sections plus the same form of release — which makes the differences between them the
only thing that carries information.

| File | Version | Words |
|------|---------|-------|
| `01-2012-08-27-employment-agreement.md` | Original, effective September 1, 2012 | ~9,300 |
| `02-2013-09-27-amended-and-restated.md` | First restatement | ~10,400 |
| `03-2015-02-19-amended-and-restated.md` | Second restatement | ~11,000 |

## How they are tied together

- **A dated chain in the preamble.** The 2013 agreement says it "amends and restates in
  its entirety that certain Employment Agreement... dated August 27, 2012"; the 2015
  agreement says the same of the September 27, 2013 one. Each document names its
  predecessor by date, so the ordering is stated, not inferred.
- **An identical skeleton.** All three have the same 40 headings: Sections 1–26 and an
  Exhibit A form of waiver and mutual release with its own 13 sections. Section 8 is
  Non-Competition in every version. A linker that matches on structure will line them up
  almost perfectly — and then has to explain the handful of places where it can't.
- **Terms that moved.** Base Salary is $1,000,000 in the first two and $1,150,000
  "effective January 1, 2015" in the third. Target bonus stays at 125% throughout.
  Life insurance stays at four times Base Salary. The interesting links are the ones
  that changed against a background of things that didn't.
- **A section that split in two.** In 2012 there is one severance clause, Section 4(c),
  "Termination Without Cause; Resignation for Good Reason Prior to a Change in Control."
  In 2013 it becomes two — 4(c) for a termination *not* in connection with a change in
  control and 4(d) for one on or within two years after one — and everything below it
  shifts a letter: what was 4(d) Execution and Delivery of Release becomes 4(e).
- **Internal cross-references that had to follow.** The release condition in the
  severance clause reads "subject to Section 4(d)" in 2012 and "subject to Section 4(e)"
  in both later versions. Same sentence, same function, different pointer. There are 46,
  52 and 64 internal section references across the three.
- **A clause rewritten rather than edited.** The change-in-control severance in 2013 is
  two years of continued salary and bonus payments; in 2015 the same subsection pays
  three times Base Salary and three times target bonus as cash. And Section 5(d), the
  definition of Change in Control, is added in 2013 ("shall be deemed to have occurred
  when") and rewritten in 2015 ("means any one of the following").
- **Things that appear from nowhere.** Section 4(h), Legal Fees, exists only in the 2015
  version.

## Provenance

SEC EDGAR, Exhibit 10.1 of three Forms 8-K filed by American Axle & Manufacturing
Holdings, Inc. (CIK 0001062231):

- <https://www.sec.gov/Archives/edgar/data/1062231/000106223112000042/exhibit101.htm>
- <https://www.sec.gov/Archives/edgar/data/1062231/000106223113000042/exhibit101-axlamendedandre.htm>
- <https://www.sec.gov/Archives/edgar/data/1062231/000106223115000025/exhibit101amendedrestatede.htm>

The exhibits are HTML with one `<div>` per paragraph and one `<font>` run per formatting
change; section numbers and their underlined titles became `##` and `###` headings.

One normalization worth knowing about: the original and 2015 filings underline defined
terms ("Base Salary", "Term"), and the 2013 filing lost that underlining in conversion,
leaving stray spaces behind. Rendering the underlines as bold would have made the middle
document look different from its neighbours for a reason that has nothing to do with the
renegotiation, so defined-term emphasis is dropped from body text in all three; the
quotation marks around them are untouched. Headings are still detected from the
underlining before it is discarded. Also repaired: spaces stranded by that lost markup
("&ldquo; Term .&rdquo;") and list markers run into the following word ("(i)a cash amount").
