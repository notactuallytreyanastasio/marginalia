# The record of a case

`Marginalia.Cases.Record`: the public-record facts that belong to no one
document, as data keyed by collection name. A collection with no entry has
none of this and the page renders without it, which is what happens for a
collection that is not a court case.

Dockets and dates are transcribed from the slip opinions (`Argued December 8,
2025—Decided June 29, 2026`). What the Court held is deliberately not here:
it comes from the opinion itself, in the Court's words (`casesHolding`). The
`question` is written, and only where it says something the holding does not.

    let casesRecords(): List<CaseRecord> {
      [
        new CaseRecord("Blanche v. Lau", "No. 25-429", "April 22, 2026", "June 23, 2026", null),
        new CaseRecord("Chatrie v. United States", "No. 25-112", "April 27, 2026", "June 29, 2026", "Whether a geofence warrant compelling Google to disclose the Location History of every device in an area is a Fourth Amendment search."),
        new CaseRecord("Cisco Systems v. Doe", "No. 24-856", "April 28, 2026", "June 23, 2026", null),
        new CaseRecord("Exxon Mobil Corp. v. Corporacion Cimex", "No. 24-699", "February 23, 2026", "June 23, 2026", null),
        new CaseRecord("Landor v. Louisiana", "No. 23-1197", "November 10, 2025", "June 23, 2026", "Whether RLUIPA, enacted under the Spending Clause, lets a prisoner sue a state official for damages in their individual capacity."),
        new CaseRecord("Monsanto Co. v. Durnell", "No. 24-1068", "April 27, 2026", "June 25, 2026", null),
        new CaseRecord("Mullin v. Al Otro Lado", "No. 25-5", "March 24, 2026", "June 25, 2026", null),
        new CaseRecord("Mullin v. Doe", "No. 25-1083", "April 29, 2026", "June 25, 2026", null),
        new CaseRecord("National Republican Senatorial Committee v. FEC", "No. 24-621", "December 9, 2025", "June 30, 2026", null),
        new CaseRecord("Pung v. Isabella County", "No. 25-95", "February 25, 2026", "June 23, 2026", null),
        new CaseRecord("T. M. v. University of Maryland Medical System", "No. 25-197", "April 20, 2026", "June 18, 2026", null),
        new CaseRecord("Trump v. Barbara", "No. 25-365", "April 1, 2026", "June 30, 2026", null),
        new CaseRecord("Trump v. Slaughter", "No. 25-332", "December 8, 2025", "June 29, 2026", "Whether a President may remove a Federal Trade Commission commissioner before the end of their term, and whether Humphrey's Executor survives."),
        new CaseRecord("Watson v. Republican National Committee", "No. 24-1260", "March 23, 2026", "June 29, 2026", null),
        new CaseRecord("West Virginia v. B. P. J.", "No. 24-43", "January 13, 2026", "June 30, 2026", "Whether Title IX or the Equal Protection Clause bars a State from limiting girls' school sports teams to students assigned female at birth."),
        new CaseRecord("Wolford v. Lopez", "No. 24-1046", "January 20, 2026", "June 25, 2026", null),
      ]
    }

`Record.for(name)`: the record for a collection, or null.

    export let casesRecordFor(collection: String): CaseRecord? {
      let all = casesRecords();
      var i = 0;
      while (i < all.length) {
        if (all[i].name == collection) { return all[i]; }
        i += 1;
      }
      null
    }

`Record.names/0`: every collection this module knows about, in the order of
the data (alphabetical by name).

    export let casesRecordNames(): List<String> {
      casesRecords().map { (r: CaseRecord): String => r.name }
    }
