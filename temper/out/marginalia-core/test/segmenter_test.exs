defmodule Temper.MarginaliaCore.SegmenterTest do
  use ExUnit.Case

  setup_all do
    Temper.MarginaliaCore.Tests.__temper_init__()
    :ok
  end

  test "a blog post with no structure is one section" do
    TemperCore.Test.check(&Temper.MarginaliaCore.Tests.aBlogPostWithNoStructureIsOneSection__1404/1, "src/segmenter_test.temper.md:13")
  end

  test "markdown headings win when the writer supplied them" do
    TemperCore.Test.check(&Temper.MarginaliaCore.Tests.markdownHeadingsWinWhenTheWriterSuppliedThem__1405/1, "src/segmenter_test.temper.md:20")
  end

  test "chapter markers are found when there is no markdown" do
    TemperCore.Test.check(&Temper.MarginaliaCore.Tests.chapterMarkersAreFoundWhenThereIsNoMarkdown__1406/1, "src/segmenter_test.temper.md:28")
  end

  test "a run of em dashes is a section marker, as hyphens are" do
    TemperCore.Test.check(&Temper.MarginaliaCore.Tests.aRunOfEmDashesIsASectionMarkerAsHyphensAre__1407/1, "src/segmenter_test.temper.md:37")
  end

  test "empty input yields nothing" do
    TemperCore.Test.check(&Temper.MarginaliaCore.Tests.emptyInputYieldsNothing__1408/1, "src/segmenter_test.temper.md:43")
  end
end
