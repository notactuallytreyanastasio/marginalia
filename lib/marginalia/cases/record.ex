defmodule Marginalia.Cases.Record do
  @moduledoc """
  The public-record facts about a case that belong to no one document.

  A collection is a name several drafts agree on — it has no table, and
  deliberately so. But a Supreme Court case has facts that are true of the
  case rather than of its opinion or its transcript: the docket number,
  the day it was argued, the day it was decided, and what the Court held.
  They are printed on the first pages of the slip opinion and they are
  what a reader checks first.

  So they live here, as data, keyed by collection name. A collection with
  no entry simply has none of this and the page renders without it, which
  is what should happen for a collection that is not a court case.

  Dates and dockets are transcribed from the slip opinions themselves
  (`Argued December 8, 2025—Decided June 29, 2026`) — extracted rather
  than written, because sixteen transcriptions by hand is where a slip
  becomes indistinguishable from a claim. They are facts of record; the
  page states them flatly.

  What the Court *held* is deliberately not here. It was, taken from the
  Reporter's syllabus, which is the obvious source and the wrong one: the
  syllabus is not part of the opinion, carries no authority, says so on
  its own first page, and a lawyer does not read it. The holding now
  comes from the opinion itself, in the Court's words — see
  `Marginalia.Cases.holding/1`.

  `question` is written, and only where it says something the holding
  does not: what the Court was asked, as against what it decided.
  """

  @records %{
    "Blanche v. Lau" => %{
      docket: "No. 25-429",
      argued: "April 22, 2026",
      decided: "June 23, 2026"
    },
    "Chatrie v. United States" => %{
      docket: "No. 25-112",
      argued: "April 27, 2026",
      decided: "June 29, 2026",
      question:
        "Whether a geofence warrant compelling Google to disclose the " <>
        "Location History of every device in an area is a Fourth Amendment " <>
        "search."
    },
    "Cisco Systems v. Doe" => %{
      docket: "No. 24-856",
      argued: "April 28, 2026",
      decided: "June 23, 2026"
    },
    "Exxon Mobil Corp. v. Corporacion Cimex" => %{
      docket: "No. 24-699",
      argued: "February 23, 2026",
      decided: "June 23, 2026"
    },
    "Landor v. Louisiana" => %{
      docket: "No. 23-1197",
      argued: "November 10, 2025",
      decided: "June 23, 2026",
      question:
        "Whether RLUIPA, enacted under the Spending Clause, lets a prisoner " <>
        "sue a state official for damages in their individual capacity."
    },
    "Monsanto Co. v. Durnell" => %{
      docket: "No. 24-1068",
      argued: "April 27, 2026",
      decided: "June 25, 2026"
    },
    "Mullin v. Al Otro Lado" => %{
      docket: "No. 25-5",
      argued: "March 24, 2026",
      decided: "June 25, 2026"
    },
    "Mullin v. Doe" => %{
      docket: "No. 25-1083",
      argued: "April 29, 2026",
      decided: "June 25, 2026"
    },
    "National Republican Senatorial Committee v. FEC" => %{
      docket: "No. 24-621",
      argued: "December 9, 2025",
      decided: "June 30, 2026"
    },
    "Pung v. Isabella County" => %{
      docket: "No. 25-95",
      argued: "February 25, 2026",
      decided: "June 23, 2026"
    },
    "T. M. v. University of Maryland Medical System" => %{
      docket: "No. 25-197",
      argued: "April 20, 2026",
      decided: "June 18, 2026"
    },
    "Trump v. Barbara" => %{
      docket: "No. 25-365",
      argued: "April 1, 2026",
      decided: "June 30, 2026"
    },
    "Trump v. Slaughter" => %{
      docket: "No. 25-332",
      argued: "December 8, 2025",
      decided: "June 29, 2026",
      question:
        "Whether a President may remove a Federal Trade Commission " <>
        "commissioner before the end of their term, and whether Humphrey's " <>
        "Executor survives."
    },
    "Watson v. Republican National Committee" => %{
      docket: "No. 24-1260",
      argued: "March 23, 2026",
      decided: "June 29, 2026"
    },
    "West Virginia v. B. P. J." => %{
      docket: "No. 24-43",
      argued: "January 13, 2026",
      decided: "June 30, 2026",
      question:
        "Whether Title IX or the Equal Protection Clause bars a State from " <>
        "limiting girls' school sports teams to students assigned female at " <>
        "birth."
    },
    "Wolford v. Lopez" => %{
      docket: "No. 24-1046",
      argued: "January 20, 2026",
      decided: "June 25, 2026"
    }
  }

  @doc "The record for a collection, or nil."
  def for(name), do: Map.get(@records, name)

  @doc "Every collection this module knows about."
  def names, do: Map.keys(@records)
end
