defmodule Temper.MarginaliaCore.WordsTest do
  use ExUnit.Case

  setup_all do
    Temper.MarginaliaCore.Tests.__temper_init__()
    :ok
  end

  test "both sides reconstruct exactly" do
    TemperCore.Test.check(&Temper.MarginaliaCore.Tests.bothSidesReconstructExactly/1, "src/words_test.temper.md:25")
  end

  test "each side's whitespace, newlines included, comes back with its words" do
    TemperCore.Test.check(&Temper.MarginaliaCore.Tests.eachSideSWhitespaceNewlinesIncludedComesBackWithItsWords/1, "src/words_test.temper.md:33")
  end

  test "identical spans are all one piece" do
    TemperCore.Test.check(&Temper.MarginaliaCore.Tests.identicalSpansAreAllOnePiece/1, "src/words_test.temper.md:37")
  end

  test "an empty original is all insertion" do
    TemperCore.Test.check(&Temper.MarginaliaCore.Tests.anEmptyOriginalIsAllInsertion/1, "src/words_test.temper.md:41")
  end

  test "it finds the shared middle rather than replacing everything" do
    TemperCore.Test.check(&Temper.MarginaliaCore.Tests.itFindsTheSharedMiddleRatherThanReplacingEverything/1, "src/words_test.temper.md:45")
  end

  test "a word is the same word whatever whitespace followed it" do
    TemperCore.Test.check(&Temper.MarginaliaCore.Tests.aWordIsTheSameWordWhateverWhitespaceFollowedIt/1, "src/words_test.temper.md:49")
  end
end
