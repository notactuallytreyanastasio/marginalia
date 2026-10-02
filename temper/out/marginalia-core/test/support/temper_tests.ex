defmodule Temper.MarginaliaCore.Tests do
  def kinds(before, after_) do
    fn_ = fn r ->
      Temper.MarginaliaCore.Row.get_kind(r)
    end
    TemperCore.List.join(Temper.MarginaliaCore.rows(before, after_), " ", fn_)
  end
  def expectText(test, got, want) do
    fn_ = fn ->
      "got:" <> "\n" <> got <> "\n" <> "want:" <> "\n" <> want
    end
    TemperCore.Test.assert(test, got == want, fn_)
    nil
  end
  def rowsAre(test, before, after_, want) do
    Temper.MarginaliaCore.Tests.expectText(test, Temper.MarginaliaCore.Tests.kinds(before, after_), want)
    nil
  end
  def identicalProseIsAllSame(test) do
    Temper.MarginaliaCore.Tests.rowsAre(test, "One.\n\nTwo.\n\nThree.", "One.\n\nTwo.\n\nThree.", "same same same")
    nil
  end
  def anEditedParagraphIsAChangeNotADeleteAndAnInsert(test) do
    Temper.MarginaliaCore.Tests.rowsAre(test, "One.\n\nTwo.\n\nThree.", "One.\n\nTwo, amended.\n\nThree.", "same change same")
    nil
  end
  def aParagraphInsertedInTheMiddleShiftsNothingAfterIt(test) do
    Temper.MarginaliaCore.Tests.rowsAre(test, "One.\n\nTwo.", "One.\n\nINSERTED.\n\nTwo.", "same ins same")
    nil
  end
  def aRemovedParagraphIsADeleteAndTheRestStillLinesUp(test) do
    Temper.MarginaliaCore.Tests.rowsAre(test, "One.\n\nGONE.\n\nThree.", "One.\n\nThree.", "same del same")
    nil
  end
  def rewrappingIsNotAnEdit(test) do
    Temper.MarginaliaCore.Tests.rowsAre(test, "A sentence that\nwraps across lines.", "A sentence that wraps   across lines.", "same")
    nil
  end
  def paramKinds(s) do
    fn_ = fn p ->
      Temper.MarginaliaCore.Param.get_kind(p) <> ":" <> Temper.MarginaliaCore.Param.get_text(p)
    end
    TemperCore.List.join(Temper.MarginaliaCore.Statement.get_params(s), ",", fn_)
  end
  def statementIs(test, s, text, params) do
    Temper.MarginaliaCore.Tests.expectText(test, Temper.MarginaliaCore.Statement.get_text(s), text)
    Temper.MarginaliaCore.Tests.expectText(test, Temper.MarginaliaCore.Tests.paramKinds(s), params)
    nil
  end
  def refused(test, p, want) do
    isRefusal = Temper.MarginaliaCore.Prepared.get_statement(p) === nil
    fn_1 = fn ->
      "expected a refusal"
    end
    TemperCore.Test.assert(test, isRefusal, fn_1)
    fn_2 = fn e ->
      Temper.MarginaliaCore.FieldError.get_field(e) <> " " <> Temper.MarginaliaCore.FieldError.get_message(e)
    end
    Temper.MarginaliaCore.Tests.expectText(test, TemperCore.List.join(Temper.MarginaliaCore.Prepared.get_errors(p), "; ", fn_2), want)
    nil
  end
  def aFolderIsLookedUpByOwnerAndIdBothBoundAsIntegers(test) do
    Temper.MarginaliaCore.Tests.statementIs(test, Temper.MarginaliaCore.getFolder(7, 3), "SELECT id, name, published_at, slug, user_id, parent_id, inserted_at, updated_at FROM folders WHERE user_id = $1 AND id = $2", "int:7,int:3")
    nil
  end
  def siblingsSortByLowerNameSelectedSoAlloyCanOrderByIt(test) do
    Temper.MarginaliaCore.Tests.statementIs(test, Temper.MarginaliaCore.listFolders(7), "SELECT folders.id, folders.name, folders.published_at, folders.slug, folders.user_id, folders.parent_id, folders.inserted_at, folders.updated_at, lower(name) AS name_key FROM folders WHERE user_id = $1 ORDER BY name_key ASC, id ASC", "int:7")
    nil
  end
  def aNewFolderSNameIsTrimmedAndItsTimestampsAreTheDatabaseS(test) do
    _t1 = nil
    p = Temper.MarginaliaCore.createFolder(7, "  Notes ", 4)
    t1 = try do
      t2 = Temper.MarginaliaCore.Prepared.get_statement(p)
      if t2 === nil do
        raise(TemperCore.Bubble)
      else
        t1 = t2
        t1
      end
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    Temper.MarginaliaCore.Tests.statementIs(test, t1, "INSERT INTO folders (name, parent_id, user_id, inserted_at, updated_at) VALUES ($1, $2, $3, date_trunc('second', now() at time zone 'utc'), date_trunc('second', now() at time zone 'utc')) RETURNING id, name, published_at, slug, user_id, parent_id, inserted_at, updated_at", "text:Notes,int:4,int:7")
    nil
  end
  def aBlankNameIsRefusedBeforeAnySql(test) do
    Temper.MarginaliaCore.Tests.refused(test, Temper.MarginaliaCore.createFolder(7, "   ", nil), "name is required")
    nil
  end
  def aNameOver80_charactersIsRefused(test) do
    Temper.MarginaliaCore.Tests.refused(test, Temper.MarginaliaCore.renameFolder(7, 3, "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"), "name must be between 1 and 80 characters")
    nil
  end
  def movingAFolderToTheRootSetsItsParentToNullNotAParameter(test) do
    Temper.MarginaliaCore.Tests.statementIs(test, Temper.MarginaliaCore.moveFolder(7, 3, nil), "UPDATE folders SET parent_id = NULL, updated_at = date_trunc('second', now() at time zone 'utc') WHERE user_id = $1 AND id = $2 RETURNING id, name, published_at, slug, user_id, parent_id, inserted_at, updated_at", "int:7,int:3")
    nil
  end
  def deletingAFolderLiftsItsDraftsAndChildrenBeforeItGoes(test) do
    steps = Temper.MarginaliaCore.deleteFolder(3, 1)
    actual = TemperCore.List.length(steps)
    fn_ = fn ->
      "expected steps.length == (" <> TemperCore.int_to_string(3) <> ") not (" <> TemperCore.int_to_string(actual) <> ")"
    end
    TemperCore.Test.assert(test, actual == 3, fn_)
    Temper.MarginaliaCore.Tests.statementIs(test, TemperCore.List.get(steps, 0), "UPDATE works SET folder_id = $1 WHERE folder_id = $2", "int:1,int:3")
    Temper.MarginaliaCore.Tests.statementIs(test, TemperCore.List.get(steps, 1), "UPDATE folders SET parent_id = $1 WHERE parent_id = $2", "int:1,int:3")
    nil
  end
  def filingDraftsBindsEachId(test) do
    ids = TemperCore.List.builder()
    TemperCore.List.add(ids, 1)
    TemperCore.List.add(ids, 2)
    Temper.MarginaliaCore.Tests.statementIs(test, Temper.MarginaliaCore.fileWorks(TemperCore.List.to_list(ids), 5), "UPDATE works SET folder_id = $1 WHERE id IN ($2, $3)", "int:5,int:1,int:2")
    nil
  end
  def aSlugIsDataNeverSql(test) do
    Temper.MarginaliaCore.Tests.statementIs(test, Temper.MarginaliaCore.publishedBySlug("x'; DROP TABLE folders; --"), "SELECT id, name, published_at, slug, user_id, parent_id, inserted_at, updated_at FROM folders WHERE slug = $1 AND published_at IS NOT NULL", "text:x'; DROP TABLE folders; --")
    nil
  end
  def fn_(line) do
    line
  end
  def paragraphsOf(page) do
    TemperCore.String.split(Temper.MarginaliaCore.reflowPage(page), "\n\n")
  end
  def wrappedIs(test, text, want) do
    fn_ = fn ->
      "isWrapped: wanted " <> Atom.to_string(want)
    end
    TemperCore.Test.assert(test, Temper.MarginaliaCore.isWrapped(text) == want, fn_)
    nil
  end
  def hardWrappedTextWithNoBlankLinesIsPageText(test) do
    Temper.MarginaliaCore.Tests.wrappedIs(test, TemperCore.Global.get(:"Temper.MarginaliaCore.landor"), true)
    nil
  end
  def textThatAlreadyHasParagraphsIsLeftAlone(test) do
    _para = "word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word "
    _prose = "Paragraph 1. word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word \n\nParagraph 2. word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word \n\nParagraph 3. word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word \n\nParagraph 4. word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word "
    Temper.MarginaliaCore.Tests.wrappedIs(test, "Paragraph 1. word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word \n\nParagraph 2. word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word \n\nParagraph 3. word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word \n\nParagraph 4. word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word ", false)
    Temper.MarginaliaCore.Tests.expectText(test, "Paragraph 1. word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word \n\nParagraph 2. word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word \n\nParagraph 3. word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word \n\nParagraph 4. word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word ", "Paragraph 1. word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word \n\nParagraph 2. word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word \n\nParagraph 3. word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word \n\nParagraph 4. word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word ")
    nil
  end
  def includes(s, part) do
    TemperCore.List.length(TemperCore.String.split(s, part)) > 1
  end
  def theTypesetterSHyphensAreClosedUpAndTheRunningHeadIsDropped(test) do
    out = Temper.MarginaliaCore.reflowPage(TemperCore.Global.get(:"Temper.MarginaliaCore.landor"))
    fn_1 = fn ->
      out
    end
    TemperCore.Test.assert(test, Temper.MarginaliaCore.Tests.includes(out, "private capacities for damages"), fn_1)
    fn_2 = fn ->
      out
    end
    TemperCore.Test.assert(test, Temper.MarginaliaCore.Tests.includes(out, "Congress has conditioned federal Medicaid"), fn_2)
    fn_3 = fn ->
      out
    end
    TemperCore.Test.assert(test, not Temper.MarginaliaCore.Tests.includes(out, "LANDOR v. LOUISIANA"), fn_3)
    nil
  end
  def theDivisionNumeralStandsAlone(test) do
    paragraphs = Temper.MarginaliaCore.Tests.paragraphsOf(TemperCore.Global.get(:"Temper.MarginaliaCore.landor"))
    found = false
    i = 0
    ex_loop_1 = fn ex_loop_1, found, i ->
      if i < TemperCore.List.length(paragraphs) do
        found = if TemperCore.List.get(paragraphs, i) == "I" do
          found = true
          found
        else
          found
        end
        i = TemperCore.int32(i + 1)
        ex_loop_1.(ex_loop_1, found, i)
      else
        {found, i}
      end
    end
    {found, _i} = ex_loop_1.(ex_loop_1, found, i)
    fn_1 = fn ->
      fn_2 = fn p ->
        p
      end
      TemperCore.List.join(paragraphs, "\n--\n", fn_2)
    end
    TemperCore.Test.assert(test, found, fn_1)
    nil
  end
  def titles(sections) do
    fn_ = fn s ->
      Temper.MarginaliaCore.Section.get_title(s)
    end
    TemperCore.List.join(sections, " / ", fn_)
  end
  def titlesAre(test, text, want) do
    Temper.MarginaliaCore.Tests.expectText(test, Temper.MarginaliaCore.Tests.titles(Temper.MarginaliaCore.segment(text)), want)
    nil
  end
  def aBlogPostWithNoStructureIsOneSection(test) do
    _para = "word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word "
    sections = Temper.MarginaliaCore.segment("Paragraph 1. word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word \n\nParagraph 2. word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word \n\nParagraph 4. word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word ")
    fn_1 = fn ->
      TemperCore.int_to_string(TemperCore.List.length(sections)) <> " sections"
    end
    TemperCore.Test.assert(test, TemperCore.List.length(sections) == 1, fn_1)
    fn_2 = fn ->
      Temper.MarginaliaCore.Section.get_body(TemperCore.List.get(sections, 0))
    end
    TemperCore.Test.assert(test, Temper.MarginaliaCore.Tests.includes(Temper.MarginaliaCore.Section.get_body(TemperCore.List.get(sections, 0)), "Paragraph 4"), fn_2)
    nil
  end
  def markdownHeadingsWinWhenTheWriterSuppliedThem(test) do
    Temper.MarginaliaCore.Tests.titlesAre(test, "\# The Opening\nalpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha \n\n\# The Middle\nbeta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta \n\n\# The End\ngamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma \n", "The Opening / The Middle / The End")
    nil
  end
  def chapterMarkersAreFoundWhenThereIsNoMarkdown(test) do
    sections = Temper.MarginaliaCore.segment("Chapter 1\none one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one \n\nChapter 2\ntwo two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two \n")
    fn_1 = fn ->
      Temper.MarginaliaCore.Tests.titles(sections)
    end
    TemperCore.Test.assert(test, TemperCore.List.length(sections) == 2, fn_1)
    fn_2 = fn ->
      Temper.MarginaliaCore.Tests.titles(sections)
    end
    TemperCore.Test.assert(test, Temper.MarginaliaCore.Tests.includes(Temper.MarginaliaCore.Section.get_title(TemperCore.List.get(sections, 0)), "Chapter 1"), fn_2)
    nil
  end
  def aRunOfEmDashesIsASectionMarkerAsHyphensAre(test) do
    sections = Temper.MarginaliaCore.segment("——— One\none one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one \n\n———\ntwo two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two \n")
    fn_ = fn ->
      Temper.MarginaliaCore.Tests.titles(sections)
    end
    TemperCore.Test.assert(test, TemperCore.List.length(sections) == 2, fn_)
    Temper.MarginaliaCore.Tests.expectText(test, Temper.MarginaliaCore.Section.get_title(TemperCore.List.get(sections, 0)), "——— One")
    nil
  end
  def emptyInputYieldsNothing(test) do
    Temper.MarginaliaCore.Tests.titlesAre(test, "", "")
    nil
  end
  def reflowsTo(test, text, want) do
    Temper.MarginaliaCore.Tests.expectText(test, Temper.MarginaliaCore.reflow(text), want)
    nil
  end
  def aHardWrappedParagraphComesBackOneSentencePerLine(test) do
    Temper.MarginaliaCore.Tests.reflowsTo(test, "At 04:47 UTC on 22 September 2026, agent-7 implemented the Guideline step\nreset for lock delay. The idea came from agent-8, which had not committed the\ncode. Agent-8 had logged a decision.", "At 04:47 UTC on 22 September 2026, agent-7 implemented the Guideline step reset for lock delay.\nThe idea came from agent-8, which had not committed the code.\nAgent-8 had logged a decision.")
    nil
  end
  def paragraphsStaySeparatedByABlankLine(test) do
    Temper.MarginaliaCore.Tests.reflowsTo(test, "One. Two.\n\nThree. Four.", "One.\nTwo.\n\nThree.\nFour.")
    nil
  end
  def reflowingTwiceChangesNothing(test) do
    once = Temper.MarginaliaCore.reflow("She stood at the window\nfor an hour. The kettle went cold. It was late.")
    Temper.MarginaliaCore.Tests.reflowsTo(test, once, once)
    nil
  end
  def abbreviationsAndInitialsDoNotEndASentence(test) do
    Temper.MarginaliaCore.Tests.reflowsTo(test, "Ask Dr. Jones, e.g. tomorrow. J. K. Rowling agreed. It cost No. 4 dearly. Done.", "Ask Dr. Jones, e.g. tomorrow.\nJ. K. Rowling agreed.\nIt cost No. 4 dearly.\nDone.")
    nil
  end
  def decimalsQuestionMarksExclamationsAndClosingQuotes(test) do
    Temper.MarginaliaCore.Tests.reflowsTo(test, "It scored 3.16 on the board! Was that enough? \"No,\" she said. \"Not nearly.\" Fine.", "It scored 3.16 on the board!\nWas that enough?\n\"No,\" she said.\n\"Not nearly.\"\nFine.")
    nil
  end
  def fencedCodeIsUntouchedBlankLinesAndAll(test) do
    _code = "```\nfoo. Bar baz.\n\nqux. Quux.\n```"
    Temper.MarginaliaCore.Tests.reflowsTo(test, "Intro one. Intro two.\n\n```\nfoo. Bar baz.\n\nqux. Quux.\n```", "Intro one.\nIntro two.\n\n```\nfoo. Bar baz.\n\nqux. Quux.\n```")
    nil
  end
  def render(parts) do
    fn_ = fn part ->
      Temper.MarginaliaCore.Part.get_kind(part) <> ":" <> Temper.MarginaliaCore.Part.get_text(part)
    end
    TemperCore.List.join(parts, "|", fn_)
  end
  def side(parts, skip) do
    fn_1 = fn part1 ->
      Temper.MarginaliaCore.Part.get_kind(part1) != skip
    end
    fn_2 = fn part2 ->
      Temper.MarginaliaCore.Part.get_text(part2)
    end
    TemperCore.List.join(TemperCore.List.filter(parts, fn_1), "", fn_2)
  end
  def reconstructs(test, a, b) do
    parts = Temper.MarginaliaCore.diff(a, b)
    Temper.MarginaliaCore.Tests.expectText(test, Temper.MarginaliaCore.Tests.side(parts, "ins"), a)
    Temper.MarginaliaCore.Tests.expectText(test, Temper.MarginaliaCore.Tests.side(parts, "del"), b)
    nil
  end
  def diffIs(test, a, b, want) do
    Temper.MarginaliaCore.Tests.expectText(test, Temper.MarginaliaCore.Tests.render(Temper.MarginaliaCore.diff(a, b)), want)
    nil
  end
  def bothSidesReconstructExactly(test) do
    Temper.MarginaliaCore.Tests.reconstructs(test, "The kettle went cold on the counter, and nobody moved to fill it again.", "The kettle went cold, and nobody moved.")
    nil
  end
  def eachSideSWhitespaceNewlinesIncludedComesBackWithItsWords(test) do
    Temper.MarginaliaCore.Tests.reconstructs(test, "One sentence.\nAnother  sentence.\nA third.", "One sentence.\nA different sentence.\nA third.")
    nil
  end
  def identicalSpansAreAllOnePiece(test) do
    Temper.MarginaliaCore.Tests.diffIs(test, "a b c", "a b c", "same:a b c")
    nil
  end
  def anEmptyOriginalIsAllInsertion(test) do
    Temper.MarginaliaCore.Tests.diffIs(test, "", "new text", "ins:new text")
    nil
  end
  def itFindsTheSharedMiddleRatherThanReplacingEverything(test) do
    Temper.MarginaliaCore.Tests.diffIs(test, "the cat sat on the mat", "the dog sat on the mat", "same:the |del:cat |ins:dog |same:sat on the mat")
    nil
  end
  def aWordIsTheSameWordWhateverWhitespaceFollowedIt(test) do
    Temper.MarginaliaCore.Tests.diffIs(test, "a b\nc", "a b c", "same:a b c")
    nil
  end
  def __temper_init__() do
    TemperCore.init_once(:"Temper.MarginaliaCore.Tests", fn ->
      Temper.MarginaliaCore.__temper_init__()
      TemperCore.Global.put(:"Temper.MarginaliaCore.landor", TemperCore.List.join(%TemperCore.Vec{t: {"JUSTICE GORSUCH delivered the opinion of the Court.", "This case concerns whether the Religious Land Use and", "Institutionalized Persons Act of 2000 permits plaintiffs to", "sue nonconsenting state employees in their private capaci-", "ties for damages.", "I", "Today, Congress offers financial support to all 50 States", "and many other entities. Much of that support comes with", "strings attached. So, for example, Congress has conditioned", "receipt of federal highway funds on a State's agreement to", "maintain laws setting a minimum drinking age of 21. See", "South Dakota v. Dole, 483 U. S. 203 (1987). Likewise, Con-", "gress has conditioned federal Medicaid funds on a State's", "willingness to administer its healthcare programs con-", "sistent with various rules.", "2 LANDOR v. LOUISIANA DEPT. OF CORRECTIONS AND", "PUBLIC SAFETY", "In each of these contexts and many others, the penalty for", "noncompliance is straightforward: Congress may termi-", "nate funds if a recipient fails to abide by the conditions", "associated with its grants."}}, "\n", &Temper.MarginaliaCore.Tests.fn_/1))
      nil
    end)
  end
  def __temper_tests__() do
    Temper.MarginaliaCore.Tests.__temper_init__()
    TemperCore.Test.run_cases([TemperCore.Pair.new("identicalProseIsAllSame", &Temper.MarginaliaCore.Tests.identicalProseIsAllSame/1), TemperCore.Pair.new("anEditedParagraphIsAChangeNotADeleteAndAnInsert", &Temper.MarginaliaCore.Tests.anEditedParagraphIsAChangeNotADeleteAndAnInsert/1), TemperCore.Pair.new("aParagraphInsertedInTheMiddleShiftsNothingAfterIt", &Temper.MarginaliaCore.Tests.aParagraphInsertedInTheMiddleShiftsNothingAfterIt/1), TemperCore.Pair.new("aRemovedParagraphIsADeleteAndTheRestStillLinesUp", &Temper.MarginaliaCore.Tests.aRemovedParagraphIsADeleteAndTheRestStillLinesUp/1), TemperCore.Pair.new("rewrappingIsNotAnEdit", &Temper.MarginaliaCore.Tests.rewrappingIsNotAnEdit/1), TemperCore.Pair.new("aFolderIsLookedUpByOwnerAndIdBothBoundAsIntegers", &Temper.MarginaliaCore.Tests.aFolderIsLookedUpByOwnerAndIdBothBoundAsIntegers/1), TemperCore.Pair.new("siblingsSortByLowerNameSelectedSoAlloyCanOrderByIt", &Temper.MarginaliaCore.Tests.siblingsSortByLowerNameSelectedSoAlloyCanOrderByIt/1), TemperCore.Pair.new("aNewFolderSNameIsTrimmedAndItsTimestampsAreTheDatabaseS", &Temper.MarginaliaCore.Tests.aNewFolderSNameIsTrimmedAndItsTimestampsAreTheDatabaseS/1), TemperCore.Pair.new("aBlankNameIsRefusedBeforeAnySql", &Temper.MarginaliaCore.Tests.aBlankNameIsRefusedBeforeAnySql/1), TemperCore.Pair.new("aNameOver80_charactersIsRefused", &Temper.MarginaliaCore.Tests.aNameOver80_charactersIsRefused/1), TemperCore.Pair.new("movingAFolderToTheRootSetsItsParentToNullNotAParameter", &Temper.MarginaliaCore.Tests.movingAFolderToTheRootSetsItsParentToNullNotAParameter/1), TemperCore.Pair.new("deletingAFolderLiftsItsDraftsAndChildrenBeforeItGoes", &Temper.MarginaliaCore.Tests.deletingAFolderLiftsItsDraftsAndChildrenBeforeItGoes/1), TemperCore.Pair.new("filingDraftsBindsEachId", &Temper.MarginaliaCore.Tests.filingDraftsBindsEachId/1), TemperCore.Pair.new("aSlugIsDataNeverSql", &Temper.MarginaliaCore.Tests.aSlugIsDataNeverSql/1), TemperCore.Pair.new("hardWrappedTextWithNoBlankLinesIsPageText", &Temper.MarginaliaCore.Tests.hardWrappedTextWithNoBlankLinesIsPageText/1), TemperCore.Pair.new("textThatAlreadyHasParagraphsIsLeftAlone", &Temper.MarginaliaCore.Tests.textThatAlreadyHasParagraphsIsLeftAlone/1), TemperCore.Pair.new("theTypesetterSHyphensAreClosedUpAndTheRunningHeadIsDropped", &Temper.MarginaliaCore.Tests.theTypesetterSHyphensAreClosedUpAndTheRunningHeadIsDropped/1), TemperCore.Pair.new("theDivisionNumeralStandsAlone", &Temper.MarginaliaCore.Tests.theDivisionNumeralStandsAlone/1), TemperCore.Pair.new("aBlogPostWithNoStructureIsOneSection", &Temper.MarginaliaCore.Tests.aBlogPostWithNoStructureIsOneSection/1), TemperCore.Pair.new("markdownHeadingsWinWhenTheWriterSuppliedThem", &Temper.MarginaliaCore.Tests.markdownHeadingsWinWhenTheWriterSuppliedThem/1), TemperCore.Pair.new("chapterMarkersAreFoundWhenThereIsNoMarkdown", &Temper.MarginaliaCore.Tests.chapterMarkersAreFoundWhenThereIsNoMarkdown/1), TemperCore.Pair.new("aRunOfEmDashesIsASectionMarkerAsHyphensAre", &Temper.MarginaliaCore.Tests.aRunOfEmDashesIsASectionMarkerAsHyphensAre/1), TemperCore.Pair.new("emptyInputYieldsNothing", &Temper.MarginaliaCore.Tests.emptyInputYieldsNothing/1), TemperCore.Pair.new("aHardWrappedParagraphComesBackOneSentencePerLine", &Temper.MarginaliaCore.Tests.aHardWrappedParagraphComesBackOneSentencePerLine/1), TemperCore.Pair.new("paragraphsStaySeparatedByABlankLine", &Temper.MarginaliaCore.Tests.paragraphsStaySeparatedByABlankLine/1), TemperCore.Pair.new("reflowingTwiceChangesNothing", &Temper.MarginaliaCore.Tests.reflowingTwiceChangesNothing/1), TemperCore.Pair.new("abbreviationsAndInitialsDoNotEndASentence", &Temper.MarginaliaCore.Tests.abbreviationsAndInitialsDoNotEndASentence/1), TemperCore.Pair.new("decimalsQuestionMarksExclamationsAndClosingQuotes", &Temper.MarginaliaCore.Tests.decimalsQuestionMarksExclamationsAndClosingQuotes/1), TemperCore.Pair.new("fencedCodeIsUntouchedBlankLinesAndAll", &Temper.MarginaliaCore.Tests.fencedCodeIsUntouchedBlankLinesAndAll/1), TemperCore.Pair.new("bothSidesReconstructExactly", &Temper.MarginaliaCore.Tests.bothSidesReconstructExactly/1), TemperCore.Pair.new("eachSideSWhitespaceNewlinesIncludedComesBackWithItsWords", &Temper.MarginaliaCore.Tests.eachSideSWhitespaceNewlinesIncludedComesBackWithItsWords/1), TemperCore.Pair.new("identicalSpansAreAllOnePiece", &Temper.MarginaliaCore.Tests.identicalSpansAreAllOnePiece/1), TemperCore.Pair.new("anEmptyOriginalIsAllInsertion", &Temper.MarginaliaCore.Tests.anEmptyOriginalIsAllInsertion/1), TemperCore.Pair.new("itFindsTheSharedMiddleRatherThanReplacingEverything", &Temper.MarginaliaCore.Tests.itFindsTheSharedMiddleRatherThanReplacingEverything/1), TemperCore.Pair.new("aWordIsTheSameWordWhateverWhitespaceFollowedIt", &Temper.MarginaliaCore.Tests.aWordIsTheSameWordWhateverWhitespaceFollowedIt/1)])
  end
end
