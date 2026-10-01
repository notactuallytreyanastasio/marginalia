defmodule Temper.MarginaliaCore.SentencesTest do
  use ExUnit.Case

  setup_all do
    Temper.MarginaliaCore.Tests.__temper_init__()
    :ok
  end

  test "a hard-wrapped paragraph comes back one sentence per line" do
    TemperCore.Test.check(&Temper.MarginaliaCore.Tests.aHardWrappedParagraphComesBackOneSentencePerLine__1409/1, "src/sentences_test.temper.md:9")
  end

  test "paragraphs stay separated by a blank line" do
    TemperCore.Test.check(&Temper.MarginaliaCore.Tests.paragraphsStaySeparatedByABlankLine__1410/1, "src/sentences_test.temper.md:17")
  end

  test "reflowing twice changes nothing" do
    TemperCore.Test.check(&Temper.MarginaliaCore.Tests.reflowingTwiceChangesNothing__1411/1, "src/sentences_test.temper.md:21")
  end

  test "abbreviations and initials do not end a sentence" do
    TemperCore.Test.check(&Temper.MarginaliaCore.Tests.abbreviationsAndInitialsDoNotEndASentence__1412/1, "src/sentences_test.temper.md:26")
  end

  test "decimals, question marks, exclamations and closing quotes" do
    TemperCore.Test.check(&Temper.MarginaliaCore.Tests.decimalsQuestionMarksExclamationsAndClosingQuotes__1413/1, "src/sentences_test.temper.md:34")
  end

  test "fenced code is untouched, blank lines and all" do
    TemperCore.Test.check(&Temper.MarginaliaCore.Tests.fencedCodeIsUntouchedBlankLinesAndAll__1414/1, "src/sentences_test.temper.md:42")
  end
end
