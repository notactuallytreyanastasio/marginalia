defmodule Temper.MarginaliaCore.DiffTest do
  use ExUnit.Case

  setup_all do
    Temper.MarginaliaCore.Tests.__temper_init__()
    :ok
  end

  test "identical prose is all same" do
    TemperCore.Test.check(&Temper.MarginaliaCore.Tests.identicalProseIsAllSame/1, "src/diff_test.temper.md:13")
  end

  test "an edited paragraph is a change, not a delete and an insert" do
    TemperCore.Test.check(&Temper.MarginaliaCore.Tests.anEditedParagraphIsAChangeNotADeleteAndAnInsert/1, "src/diff_test.temper.md:17")
  end

  test "a paragraph inserted in the middle shifts nothing after it" do
    TemperCore.Test.check(&Temper.MarginaliaCore.Tests.aParagraphInsertedInTheMiddleShiftsNothingAfterIt/1, "src/diff_test.temper.md:21")
  end

  test "a removed paragraph is a delete, and the rest still lines up" do
    TemperCore.Test.check(&Temper.MarginaliaCore.Tests.aRemovedParagraphIsADeleteAndTheRestStillLinesUp/1, "src/diff_test.temper.md:25")
  end

  test "rewrapping is not an edit" do
    TemperCore.Test.check(&Temper.MarginaliaCore.Tests.rewrappingIsNotAnEdit/1, "src/diff_test.temper.md:29")
  end
end
