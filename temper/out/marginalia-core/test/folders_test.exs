defmodule Temper.MarginaliaCore.FoldersTest do
  use ExUnit.Case

  setup_all do
    Temper.MarginaliaCore.Tests.__temper_init__()
    :ok
  end

  test "a folder is looked up by owner and id, both bound as integers" do
    TemperCore.Test.check(&Temper.MarginaliaCore.Tests.aFolderIsLookedUpByOwnerAndIdBothBoundAsIntegers/1, "src/folders_test.temper.md:23")
  end

  test "siblings sort by lower(name), selected so Alloy can order by it" do
    TemperCore.Test.check(&Temper.MarginaliaCore.Tests.siblingsSortByLowerNameSelectedSoAlloyCanOrderByIt/1, "src/folders_test.temper.md:32")
  end

  test "a new folder's name is trimmed and its timestamps are the database's" do
    TemperCore.Test.check(&Temper.MarginaliaCore.Tests.aNewFolderSNameIsTrimmedAndItsTimestampsAreTheDatabaseS/1, "src/folders_test.temper.md:41")
  end

  test "a blank name is refused before any SQL" do
    TemperCore.Test.check(&Temper.MarginaliaCore.Tests.aBlankNameIsRefusedBeforeAnySql/1, "src/folders_test.temper.md:51")
  end

  test "a name over 80 characters is refused" do
    TemperCore.Test.check(&Temper.MarginaliaCore.Tests.aNameOver80_charactersIsRefused/1, "src/folders_test.temper.md:55")
  end

  test "moving a folder to the root sets its parent to NULL, not a parameter" do
    TemperCore.Test.check(&Temper.MarginaliaCore.Tests.movingAFolderToTheRootSetsItsParentToNullNotAParameter/1, "src/folders_test.temper.md:59")
  end

  test "deleting a folder lifts its drafts and children before it goes" do
    TemperCore.Test.check(&Temper.MarginaliaCore.Tests.deletingAFolderLiftsItsDraftsAndChildrenBeforeItGoes/1, "src/folders_test.temper.md:68")
  end

  test "filing drafts binds each id" do
    TemperCore.Test.check(&Temper.MarginaliaCore.Tests.filingDraftsBindsEachId/1, "src/folders_test.temper.md:75")
  end

  test "a slug is data, never SQL" do
    TemperCore.Test.check(&Temper.MarginaliaCore.Tests.aSlugIsDataNeverSql/1, "src/folders_test.temper.md:82")
  end
end
