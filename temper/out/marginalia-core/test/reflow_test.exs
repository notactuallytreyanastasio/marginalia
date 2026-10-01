defmodule Temper.MarginaliaCore.ReflowTest do
  use ExUnit.Case

  setup_all do
    Temper.MarginaliaCore.Tests.__temper_init__()
    :ok
  end

  test "hard-wrapped text with no blank lines is page text" do
    TemperCore.Test.check(&Temper.MarginaliaCore.Tests.hardWrappedTextWithNoBlankLinesIsPageText/1, "src/reflow_test.temper.md:38")
  end

  test "text that already has paragraphs is left alone" do
    TemperCore.Test.check(&Temper.MarginaliaCore.Tests.textThatAlreadyHasParagraphsIsLeftAlone/1, "src/reflow_test.temper.md:42")
  end

  test "the typesetter's hyphens are closed up, and the running head is dropped" do
    TemperCore.Test.check(&Temper.MarginaliaCore.Tests.theTypesetterSHyphensAreClosedUpAndTheRunningHeadIsDropped/1, "src/reflow_test.temper.md:49")
  end

  test "the division numeral stands alone" do
    TemperCore.Test.check(&Temper.MarginaliaCore.Tests.theDivisionNumeralStandsAlone/1, "src/reflow_test.temper.md:56")
  end
end
