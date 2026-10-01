defmodule Temper.MarginaliaCore.Tests do
  def kinds__438(before, after_) do
    fn_ = fn r ->
      Temper.MarginaliaCore.Row.get_kind(r)
    end
    TemperCore.List.join(Temper.MarginaliaCore.rows(before, after_), " ", fn_)
  end
  def expectText__510(test, got, want) do
    fn_ = fn ->
      "got:" <> "\n" <> got <> "\n" <> "want:" <> "\n" <> want
    end
    TemperCore.Test.assert(test, got == want, fn_)
    nil
  end
  def rowsAre__439(test, before, after_, want) do
    Temper.MarginaliaCore.Tests.expectText__510(test, Temper.MarginaliaCore.Tests.kinds__438(before, after_), want)
    nil
  end
  def identicalProseIsAllSame__1374(test__635) do
    Temper.MarginaliaCore.Tests.rowsAre__439(test__635, "One.\n\nTwo.\n\nThree.", "One.\n\nTwo.\n\nThree.", "same same same")
    nil
  end
  def anEditedParagraphIsAChangeNotADeleteAndAnInsert__1375(test__637) do
    Temper.MarginaliaCore.Tests.rowsAre__439(test__637, "One.\n\nTwo.\n\nThree.", "One.\n\nTwo, amended.\n\nThree.", "same change same")
    nil
  end
  def aParagraphInsertedInTheMiddleShiftsNothingAfterIt__1376(test__639) do
    Temper.MarginaliaCore.Tests.rowsAre__439(test__639, "One.\n\nTwo.", "One.\n\nINSERTED.\n\nTwo.", "same ins same")
    nil
  end
  def aRemovedParagraphIsADeleteAndTheRestStillLinesUp__1377(test__641) do
    Temper.MarginaliaCore.Tests.rowsAre__439(test__641, "One.\n\nGONE.\n\nThree.", "One.\n\nThree.", "same del same")
    nil
  end
  def rewrappingIsNotAnEdit__1378(test__643) do
    Temper.MarginaliaCore.Tests.rowsAre__439(test__643, "A sentence that\nwraps across lines.", "A sentence that wraps   across lines.", "same")
    nil
  end
  def fn__1831(line) do
    line
  end
  def paragraphsOf__460(page) do
    TemperCore.String.split(Temper.MarginaliaCore.reflowPage(page), "\n\n")
  end
  def wrappedIs__461(test, text, want) do
    fn_ = fn ->
      "isWrapped: wanted " <> Atom.to_string(want)
    end
    TemperCore.Test.assert(test, Temper.MarginaliaCore.isWrapped(text) == want, fn_)
    nil
  end
  def hardWrappedTextWithNoBlankLinesIsPageText__1379(test__795) do
    Temper.MarginaliaCore.Tests.wrappedIs__461(test__795, TemperCore.Global.get(:"Temper.MarginaliaCore.landor__536"), true)
    nil
  end
  def repeated__508(word, n) do
    sb = TemperCore.StringBuilder.new()
    i = 0
    ex_loop_213 = fn ex_loop_213, i ->
      if i < n do
        TemperCore.StringBuilder.append(sb, word)
        i = TemperCore.int32(i + 1)
        ex_loop_213.(ex_loop_213, i)
      else
        i
      end
    end
    _i = ex_loop_213.(ex_loop_213, i)
    TemperCore.StringBuilder.to_string(sb)
  end
  def textThatAlreadyHasParagraphsIsLeftAlone__1380(test__797) do
    _para = "word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word "
    _prose = "Paragraph 1. word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word \n\nParagraph 2. word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word \n\nParagraph 3. word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word \n\nParagraph 4. word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word "
    Temper.MarginaliaCore.Tests.wrappedIs__461(test__797, "Paragraph 1. word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word \n\nParagraph 2. word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word \n\nParagraph 3. word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word \n\nParagraph 4. word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word ", false)
    Temper.MarginaliaCore.Tests.expectText__510(test__797, "Paragraph 1. word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word \n\nParagraph 2. word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word \n\nParagraph 3. word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word \n\nParagraph 4. word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word ", "Paragraph 1. word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word \n\nParagraph 2. word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word \n\nParagraph 3. word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word \n\nParagraph 4. word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word ")
    nil
  end
  def includes__509(s, part) do
    TemperCore.List.length(TemperCore.String.split(s, part)) > 1
  end
  def theTypesetterSHyphensAreClosedUpAndTheRunningHeadIsDropped__1381(test__801) do
    out = Temper.MarginaliaCore.reflowPage(TemperCore.Global.get(:"Temper.MarginaliaCore.landor__536"))
    fn_1 = fn ->
      out
    end
    TemperCore.Test.assert(test__801, Temper.MarginaliaCore.Tests.includes__509(out, "private capacities for damages"), fn_1)
    fn_2 = fn ->
      out
    end
    TemperCore.Test.assert(test__801, Temper.MarginaliaCore.Tests.includes__509(out, "Congress has conditioned federal Medicaid"), fn_2)
    fn_3 = fn ->
      out
    end
    TemperCore.Test.assert(test__801, not Temper.MarginaliaCore.Tests.includes__509(out, "LANDOR v. LOUISIANA"), fn_3)
    nil
  end
  def theDivisionNumeralStandsAlone__1382(test__804) do
    paragraphs = Temper.MarginaliaCore.Tests.paragraphsOf__460(TemperCore.Global.get(:"Temper.MarginaliaCore.landor__536"))
    found = false
    i = 0
    ex_loop_222 = fn ex_loop_222, found, i ->
      if i < TemperCore.List.length(paragraphs) do
        found = if TemperCore.List.get(paragraphs, i) == "I" do
          found = true
          found
        else
          found
        end
        i = TemperCore.int32(i + 1)
        ex_loop_222.(ex_loop_222, found, i)
      else
        {found, i}
      end
    end
    {found, _i} = ex_loop_222.(ex_loop_222, found, i)
    fn_1 = fn ->
      fn_2 = fn p ->
        p
      end
      TemperCore.List.join(paragraphs, "\n--\n", fn_2)
    end
    TemperCore.Test.assert(test__804, found, fn_1)
    nil
  end
  def titles__482(sections) do
    fn_ = fn s ->
      Temper.MarginaliaCore.Section.get_title(s)
    end
    TemperCore.List.join(sections, " / ", fn_)
  end
  def titlesAre__483(test, text, want) do
    Temper.MarginaliaCore.Tests.expectText__510(test, Temper.MarginaliaCore.Tests.titles__482(Temper.MarginaliaCore.segment(text)), want)
    nil
  end
  def aBlogPostWithNoStructureIsOneSection__1404(test__982) do
    _para = "word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word "
    sections = Temper.MarginaliaCore.segment("Paragraph 1. word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word \n\nParagraph 2. word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word \n\nParagraph 4. word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word ")
    fn_1 = fn ->
      TemperCore.int_to_string(TemperCore.List.length(sections)) <> " sections"
    end
    TemperCore.Test.assert(test__982, TemperCore.List.length(sections) == 1, fn_1)
    fn_2 = fn ->
      Temper.MarginaliaCore.Section.get_body(TemperCore.List.get(sections, 0))
    end
    TemperCore.Test.assert(test__982, Temper.MarginaliaCore.Tests.includes__509(Temper.MarginaliaCore.Section.get_body(TemperCore.List.get(sections, 0)), "Paragraph 4"), fn_2)
    nil
  end
  def markdownHeadingsWinWhenTheWriterSuppliedThem__1405(test__986) do
    Temper.MarginaliaCore.Tests.titlesAre__483(test__986, "\# The Opening\nalpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha alpha \n\n\# The Middle\nbeta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta beta \n\n\# The End\ngamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma gamma \n", "The Opening / The Middle / The End")
    nil
  end
  def chapterMarkersAreFoundWhenThereIsNoMarkdown__1406(test__988) do
    sections = Temper.MarginaliaCore.segment("Chapter 1\none one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one \n\nChapter 2\ntwo two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two \n")
    fn_1 = fn ->
      Temper.MarginaliaCore.Tests.titles__482(sections)
    end
    TemperCore.Test.assert(test__988, TemperCore.List.length(sections) == 2, fn_1)
    fn_2 = fn ->
      Temper.MarginaliaCore.Tests.titles__482(sections)
    end
    TemperCore.Test.assert(test__988, Temper.MarginaliaCore.Tests.includes__509(Temper.MarginaliaCore.Section.get_title(TemperCore.List.get(sections, 0)), "Chapter 1"), fn_2)
    nil
  end
  def aRunOfEmDashesIsASectionMarkerAsHyphensAre__1407(test__991) do
    sections = Temper.MarginaliaCore.segment("——— One\none one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one one \n\n———\ntwo two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two two \n")
    fn_ = fn ->
      Temper.MarginaliaCore.Tests.titles__482(sections)
    end
    TemperCore.Test.assert(test__991, TemperCore.List.length(sections) == 2, fn_)
    Temper.MarginaliaCore.Tests.expectText__510(test__991, Temper.MarginaliaCore.Section.get_title(TemperCore.List.get(sections, 0)), "——— One")
    nil
  end
  def emptyInputYieldsNothing__1408(test__994) do
    Temper.MarginaliaCore.Tests.titlesAre__483(test__994, "", "")
    nil
  end
  def reflowsTo__507(test, text, want) do
    Temper.MarginaliaCore.Tests.expectText__510(test, Temper.MarginaliaCore.reflow(text), want)
    nil
  end
  def aHardWrappedParagraphComesBackOneSentencePerLine__1409(test__1130) do
    Temper.MarginaliaCore.Tests.reflowsTo__507(test__1130, "At 04:47 UTC on 22 September 2026, agent-7 implemented the Guideline step\nreset for lock delay. The idea came from agent-8, which had not committed the\ncode. Agent-8 had logged a decision.", "At 04:47 UTC on 22 September 2026, agent-7 implemented the Guideline step reset for lock delay.\nThe idea came from agent-8, which had not committed the code.\nAgent-8 had logged a decision.")
    nil
  end
  def paragraphsStaySeparatedByABlankLine__1410(test__1132) do
    Temper.MarginaliaCore.Tests.reflowsTo__507(test__1132, "One. Two.\n\nThree. Four.", "One.\nTwo.\n\nThree.\nFour.")
    nil
  end
  def reflowingTwiceChangesNothing__1411(test__1134) do
    once = Temper.MarginaliaCore.reflow("She stood at the window\nfor an hour. The kettle went cold. It was late.")
    Temper.MarginaliaCore.Tests.reflowsTo__507(test__1134, once, once)
    nil
  end
  def abbreviationsAndInitialsDoNotEndASentence__1412(test__1137) do
    Temper.MarginaliaCore.Tests.reflowsTo__507(test__1137, "Ask Dr. Jones, e.g. tomorrow. J. K. Rowling agreed. It cost No. 4 dearly. Done.", "Ask Dr. Jones, e.g. tomorrow.\nJ. K. Rowling agreed.\nIt cost No. 4 dearly.\nDone.")
    nil
  end
  def decimalsQuestionMarksExclamationsAndClosingQuotes__1413(test__1139) do
    Temper.MarginaliaCore.Tests.reflowsTo__507(test__1139, "It scored 3.16 on the board! Was that enough? \"No,\" she said. \"Not nearly.\" Fine.", "It scored 3.16 on the board!\nWas that enough?\n\"No,\" she said.\n\"Not nearly.\"\nFine.")
    nil
  end
  def fencedCodeIsUntouchedBlankLinesAndAll__1414(test__1141) do
    _code = "```\nfoo. Bar baz.\n\nqux. Quux.\n```"
    Temper.MarginaliaCore.Tests.reflowsTo__507(test__1141, "Intro one. Intro two.\n\n```\nfoo. Bar baz.\n\nqux. Quux.\n```", "Intro one.\nIntro two.\n\n```\nfoo. Bar baz.\n\nqux. Quux.\n```")
    nil
  end
  def render__532(parts) do
    fn_ = fn part ->
      Temper.MarginaliaCore.Part.get_kind(part) <> ":" <> Temper.MarginaliaCore.Part.get_text(part)
    end
    TemperCore.List.join(parts, "|", fn_)
  end
  def side__533(parts, skip) do
    fn_1 = fn part1 ->
      Temper.MarginaliaCore.Part.get_kind(part1) != skip
    end
    fn_2 = fn part2 ->
      Temper.MarginaliaCore.Part.get_text(part2)
    end
    TemperCore.List.join(TemperCore.List.filter(parts, fn_1), "", fn_2)
  end
  def reconstructs__534(test, a, b) do
    parts = Temper.MarginaliaCore.diff(a, b)
    Temper.MarginaliaCore.Tests.expectText__510(test, Temper.MarginaliaCore.Tests.side__533(parts, "ins"), a)
    Temper.MarginaliaCore.Tests.expectText__510(test, Temper.MarginaliaCore.Tests.side__533(parts, "del"), b)
    nil
  end
  def diffIs__535(test, a, b, want) do
    Temper.MarginaliaCore.Tests.expectText__510(test, Temper.MarginaliaCore.Tests.render__532(Temper.MarginaliaCore.diff(a, b)), want)
    nil
  end
  def bothSidesReconstructExactly__1448(test__1333) do
    Temper.MarginaliaCore.Tests.reconstructs__534(test__1333, "The kettle went cold on the counter, and nobody moved to fill it again.", "The kettle went cold, and nobody moved.")
    nil
  end
  def eachSideSWhitespaceNewlinesIncludedComesBackWithItsWords__1449(test__1335) do
    Temper.MarginaliaCore.Tests.reconstructs__534(test__1335, "One sentence.\nAnother  sentence.\nA third.", "One sentence.\nA different sentence.\nA third.")
    nil
  end
  def identicalSpansAreAllOnePiece__1450(test__1337) do
    Temper.MarginaliaCore.Tests.diffIs__535(test__1337, "a b c", "a b c", "same:a b c")
    nil
  end
  def anEmptyOriginalIsAllInsertion__1451(test__1339) do
    Temper.MarginaliaCore.Tests.diffIs__535(test__1339, "", "new text", "ins:new text")
    nil
  end
  def itFindsTheSharedMiddleRatherThanReplacingEverything__1452(test__1341) do
    Temper.MarginaliaCore.Tests.diffIs__535(test__1341, "the cat sat on the mat", "the dog sat on the mat", "same:the |del:cat |ins:dog |same:sat on the mat")
    nil
  end
  def aWordIsTheSameWordWhateverWhitespaceFollowedIt__1453(test__1343) do
    Temper.MarginaliaCore.Tests.diffIs__535(test__1343, "a b\nc", "a b c", "same:a b c")
    nil
  end
  def __temper_init__() do
    TemperCore.init_once(:"Temper.MarginaliaCore.Tests", fn ->
      Temper.MarginaliaCore.__temper_init__()
      Temper.Std.__temper_init__()
      TemperCore.Global.put(:"Temper.MarginaliaCore.landor__536", TemperCore.List.join(%TemperCore.Vec{t: {"JUSTICE GORSUCH delivered the opinion of the Court.", "This case concerns whether the Religious Land Use and", "Institutionalized Persons Act of 2000 permits plaintiffs to", "sue nonconsenting state employees in their private capaci-", "ties for damages.", "I", "Today, Congress offers financial support to all 50 States", "and many other entities. Much of that support comes with", "strings attached. So, for example, Congress has conditioned", "receipt of federal highway funds on a State's agreement to", "maintain laws setting a minimum drinking age of 21. See", "South Dakota v. Dole, 483 U. S. 203 (1987). Likewise, Con-", "gress has conditioned federal Medicaid funds on a State's", "willingness to administer its healthcare programs con-", "sistent with various rules.", "2 LANDOR v. LOUISIANA DEPT. OF CORRECTIONS AND", "PUBLIC SAFETY", "In each of these contexts and many others, the penalty for", "noncompliance is straightforward: Congress may termi-", "nate funds if a recipient fails to abide by the conditions", "associated with its grants."}}, "\n", &Temper.MarginaliaCore.Tests.fn__1831/1))
      TemperCore.Global.put(:"Temper.MarginaliaCore.targetWords__537", 1800)
      TemperCore.Global.put(:"Temper.MarginaliaCore.minWords__538", 250)
      TemperCore.Global.put(:"Temper.MarginaliaCore.maxWords__539", 4000)
      TemperCore.Global.put(:"Temper.MarginaliaCore.v_EQ__541", 0)
      TemperCore.Global.put(:"Temper.MarginaliaCore.v_DEL__542", 1)
      TemperCore.Global.put(:"Temper.MarginaliaCore.v_INS__543", 2)
      nil
    end)
  end
  def __temper_tests__() do
    Temper.MarginaliaCore.Tests.__temper_init__()
    TemperCore.Test.run_cases([TemperCore.Pair.new("identicalProseIsAllSame__1374", &Temper.MarginaliaCore.Tests.identicalProseIsAllSame__1374/1), TemperCore.Pair.new("anEditedParagraphIsAChangeNotADeleteAndAnInsert__1375", &Temper.MarginaliaCore.Tests.anEditedParagraphIsAChangeNotADeleteAndAnInsert__1375/1), TemperCore.Pair.new("aParagraphInsertedInTheMiddleShiftsNothingAfterIt__1376", &Temper.MarginaliaCore.Tests.aParagraphInsertedInTheMiddleShiftsNothingAfterIt__1376/1), TemperCore.Pair.new("aRemovedParagraphIsADeleteAndTheRestStillLinesUp__1377", &Temper.MarginaliaCore.Tests.aRemovedParagraphIsADeleteAndTheRestStillLinesUp__1377/1), TemperCore.Pair.new("rewrappingIsNotAnEdit__1378", &Temper.MarginaliaCore.Tests.rewrappingIsNotAnEdit__1378/1), TemperCore.Pair.new("hardWrappedTextWithNoBlankLinesIsPageText__1379", &Temper.MarginaliaCore.Tests.hardWrappedTextWithNoBlankLinesIsPageText__1379/1), TemperCore.Pair.new("textThatAlreadyHasParagraphsIsLeftAlone__1380", &Temper.MarginaliaCore.Tests.textThatAlreadyHasParagraphsIsLeftAlone__1380/1), TemperCore.Pair.new("theTypesetterSHyphensAreClosedUpAndTheRunningHeadIsDropped__1381", &Temper.MarginaliaCore.Tests.theTypesetterSHyphensAreClosedUpAndTheRunningHeadIsDropped__1381/1), TemperCore.Pair.new("theDivisionNumeralStandsAlone__1382", &Temper.MarginaliaCore.Tests.theDivisionNumeralStandsAlone__1382/1), TemperCore.Pair.new("aBlogPostWithNoStructureIsOneSection__1404", &Temper.MarginaliaCore.Tests.aBlogPostWithNoStructureIsOneSection__1404/1), TemperCore.Pair.new("markdownHeadingsWinWhenTheWriterSuppliedThem__1405", &Temper.MarginaliaCore.Tests.markdownHeadingsWinWhenTheWriterSuppliedThem__1405/1), TemperCore.Pair.new("chapterMarkersAreFoundWhenThereIsNoMarkdown__1406", &Temper.MarginaliaCore.Tests.chapterMarkersAreFoundWhenThereIsNoMarkdown__1406/1), TemperCore.Pair.new("aRunOfEmDashesIsASectionMarkerAsHyphensAre__1407", &Temper.MarginaliaCore.Tests.aRunOfEmDashesIsASectionMarkerAsHyphensAre__1407/1), TemperCore.Pair.new("emptyInputYieldsNothing__1408", &Temper.MarginaliaCore.Tests.emptyInputYieldsNothing__1408/1), TemperCore.Pair.new("aHardWrappedParagraphComesBackOneSentencePerLine__1409", &Temper.MarginaliaCore.Tests.aHardWrappedParagraphComesBackOneSentencePerLine__1409/1), TemperCore.Pair.new("paragraphsStaySeparatedByABlankLine__1410", &Temper.MarginaliaCore.Tests.paragraphsStaySeparatedByABlankLine__1410/1), TemperCore.Pair.new("reflowingTwiceChangesNothing__1411", &Temper.MarginaliaCore.Tests.reflowingTwiceChangesNothing__1411/1), TemperCore.Pair.new("abbreviationsAndInitialsDoNotEndASentence__1412", &Temper.MarginaliaCore.Tests.abbreviationsAndInitialsDoNotEndASentence__1412/1), TemperCore.Pair.new("decimalsQuestionMarksExclamationsAndClosingQuotes__1413", &Temper.MarginaliaCore.Tests.decimalsQuestionMarksExclamationsAndClosingQuotes__1413/1), TemperCore.Pair.new("fencedCodeIsUntouchedBlankLinesAndAll__1414", &Temper.MarginaliaCore.Tests.fencedCodeIsUntouchedBlankLinesAndAll__1414/1), TemperCore.Pair.new("bothSidesReconstructExactly__1448", &Temper.MarginaliaCore.Tests.bothSidesReconstructExactly__1448/1), TemperCore.Pair.new("eachSideSWhitespaceNewlinesIncludedComesBackWithItsWords__1449", &Temper.MarginaliaCore.Tests.eachSideSWhitespaceNewlinesIncludedComesBackWithItsWords__1449/1), TemperCore.Pair.new("identicalSpansAreAllOnePiece__1450", &Temper.MarginaliaCore.Tests.identicalSpansAreAllOnePiece__1450/1), TemperCore.Pair.new("anEmptyOriginalIsAllInsertion__1451", &Temper.MarginaliaCore.Tests.anEmptyOriginalIsAllInsertion__1451/1), TemperCore.Pair.new("itFindsTheSharedMiddleRatherThanReplacingEverything__1452", &Temper.MarginaliaCore.Tests.itFindsTheSharedMiddleRatherThanReplacingEverything__1452/1), TemperCore.Pair.new("aWordIsTheSameWordWhateverWhitespaceFollowedIt__1453", &Temper.MarginaliaCore.Tests.aWordIsTheSameWordWhateverWhitespaceFollowedIt__1453/1)])
  end
end
