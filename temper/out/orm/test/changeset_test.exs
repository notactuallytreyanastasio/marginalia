defmodule Temper.Orm.ChangesetTest do
  use ExUnit.Case

  setup_all do
    Temper.Orm.Tests.__temper_init__()
    :ok
  end

  test "cast whitelists allowed fields" do
    TemperCore.Test.check(&Temper.Orm.Tests.castWhitelistsAllowedFields/1, "src/changeset_test.temper.md:21")
  end

  test "cast is replacing not additive — second call resets whitelist" do
    TemperCore.Test.check(&Temper.Orm.Tests.castIsReplacingNotAdditiveSecondCallResetsWhitelist/1, "src/changeset_test.temper.md:34")
  end

  test "cast ignores empty string values" do
    TemperCore.Test.check(&Temper.Orm.Tests.castIgnoresEmptyStringValues/1, "src/changeset_test.temper.md:47")
  end

  test "validateRequired passes when field present" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateRequiredPassesWhenFieldPresent/1, "src/changeset_test.temper.md:59")
  end

  test "validateRequired fails when field missing" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateRequiredFailsWhenFieldMissing/1, "src/changeset_test.temper.md:66")
  end

  test "validateLength passes within range" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateLengthPassesWithinRange/1, "src/changeset_test.temper.md:76")
  end

  test "validateLength fails when too short" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateLengthFailsWhenTooShort/1, "src/changeset_test.temper.md:82")
  end

  test "validateLength fails when too long" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateLengthFailsWhenTooLong/1, "src/changeset_test.temper.md:88")
  end

  test "validateInt passes for valid integer" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateIntPassesForValidInteger/1, "src/changeset_test.temper.md:96")
  end

  test "validateInt fails for non-integer" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateIntFailsForNonInteger/1, "src/changeset_test.temper.md:102")
  end

  test "validateFloat passes for valid float" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateFloatPassesForValidFloat/1, "src/changeset_test.temper.md:108")
  end

  test "validateInt64 passes for valid 64-bit integer" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateInt64_passesForValid64_bitInteger/1, "src/changeset_test.temper.md:116")
  end

  test "validateInt64 fails for non-integer" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateInt64_failsForNonInteger/1, "src/changeset_test.temper.md:122")
  end

  test "validateBool accepts true/1/yes/on" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateBoolAcceptsTrue1_yesOn/1, "src/changeset_test.temper.md:130")
  end

  test "validateBool accepts false/0/no/off" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateBoolAcceptsFalse0_noOff/1, "src/changeset_test.temper.md:138")
  end

  test "validateBool rejects ambiguous values" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateBoolRejectsAmbiguousValues/1, "src/changeset_test.temper.md:146")
  end

  test "toInsertSql escapes Bobby Tables" do
    TemperCore.Test.check(&Temper.Orm.Tests.toInsertSqlEscapesBobbyTables/1, "src/changeset_test.temper.md:156")
  end

  test "toInsertSql produces correct SQL for string field" do
    TemperCore.Test.check(&Temper.Orm.Tests.toInsertSqlProducesCorrectSqlForStringField/1, "src/changeset_test.temper.md:170")
  end

  test "toInsertSql produces correct SQL for int field" do
    TemperCore.Test.check(&Temper.Orm.Tests.toInsertSqlProducesCorrectSqlForIntField/1, "src/changeset_test.temper.md:184")
  end

  test "toInsertSql bubbles on invalid changeset" do
    TemperCore.Test.check(&Temper.Orm.Tests.toInsertSqlBubblesOnInvalidChangeset/1, "src/changeset_test.temper.md:199")
  end

  test "toInsertSql enforces non-nullable fields independently of isValid" do
    TemperCore.Test.check(&Temper.Orm.Tests.toInsertSqlEnforcesNonNullableFieldsIndependentlyOfIsValid/1, "src/changeset_test.temper.md:206")
  end

  test "toUpdateSql produces correct SQL" do
    TemperCore.Test.check(&Temper.Orm.Tests.toUpdateSqlProducesCorrectSql/1, "src/changeset_test.temper.md:224")
  end

  test "toUpdateSql bubbles on invalid changeset" do
    TemperCore.Test.check(&Temper.Orm.Tests.toUpdateSqlBubblesOnInvalidChangeset/1, "src/changeset_test.temper.md:232")
  end

  test "putChange adds a new field" do
    TemperCore.Test.check(&Temper.Orm.Tests.putChangeAddsANewField/1, "src/changeset_test.temper.md:241")
  end

  test "putChange overwrites existing field" do
    TemperCore.Test.check(&Temper.Orm.Tests.putChangeOverwritesExistingField/1, "src/changeset_test.temper.md:250")
  end

  test "putChange value appears in toInsertSql" do
    TemperCore.Test.check(&Temper.Orm.Tests.putChangeValueAppearsInToInsertSql/1, "src/changeset_test.temper.md:258")
  end

  test "getChange returns value for existing field" do
    TemperCore.Test.check(&Temper.Orm.Tests.getChangeReturnsValueForExistingField/1, "src/changeset_test.temper.md:272")
  end

  test "getChange bubbles on missing field" do
    TemperCore.Test.check(&Temper.Orm.Tests.getChangeBubblesOnMissingField/1, "src/changeset_test.temper.md:279")
  end

  test "deleteChange removes field" do
    TemperCore.Test.check(&Temper.Orm.Tests.deleteChangeRemovesField/1, "src/changeset_test.temper.md:288")
  end

  test "deleteChange on nonexistent field is no-op" do
    TemperCore.Test.check(&Temper.Orm.Tests.deleteChangeOnNonexistentFieldIsNoOp/1, "src/changeset_test.temper.md:300")
  end

  test "validateInclusion passes when value in list" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateInclusionPassesWhenValueInList/1, "src/changeset_test.temper.md:311")
  end

  test "validateInclusion fails when value not in list" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateInclusionFailsWhenValueNotInList/1, "src/changeset_test.temper.md:319")
  end

  test "validateInclusion skips when field not in changes" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateInclusionSkipsWhenFieldNotInChanges/1, "src/changeset_test.temper.md:328")
  end

  test "validateExclusion passes when value not in list" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateExclusionPassesWhenValueNotInList/1, "src/changeset_test.temper.md:338")
  end

  test "validateExclusion fails when value in list" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateExclusionFailsWhenValueInList/1, "src/changeset_test.temper.md:346")
  end

  test "validateExclusion skips when field not in changes" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateExclusionSkipsWhenFieldNotInChanges/1, "src/changeset_test.temper.md:355")
  end

  test "validateNumber greaterThan passes" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateNumberGreaterThanPasses/1, "src/changeset_test.temper.md:365")
  end

  test "validateNumber greaterThan fails" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateNumberGreaterThanFails/1, "src/changeset_test.temper.md:373")
  end

  test "validateNumber lessThan passes" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateNumberLessThanPasses/1, "src/changeset_test.temper.md:381")
  end

  test "validateNumber lessThan fails" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateNumberLessThanFails/1, "src/changeset_test.temper.md:389")
  end

  test "validateNumber greaterThanOrEqual boundary" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateNumberGreaterThanOrEqualBoundary/1, "src/changeset_test.temper.md:397")
  end

  test "validateNumber combined options" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateNumberCombinedOptions/1, "src/changeset_test.temper.md:405")
  end

  test "validateNumber non-numeric value" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateNumberNonNumericValue/1, "src/changeset_test.temper.md:413")
  end

  test "validateNumber skips when field not in changes" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateNumberSkipsWhenFieldNotInChanges/1, "src/changeset_test.temper.md:422")
  end

  test "validateAcceptance passes for true values" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateAcceptancePassesForTrueValues/1, "src/changeset_test.temper.md:432")
  end

  test "validateAcceptance fails for non-true values" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateAcceptanceFailsForNonTrueValues/1, "src/changeset_test.temper.md:442")
  end

  test "validateConfirmation passes when fields match" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateConfirmationPassesWhenFieldsMatch/1, "src/changeset_test.temper.md:453")
  end

  test "validateConfirmation fails when fields differ" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateConfirmationFailsWhenFieldsDiffer/1, "src/changeset_test.temper.md:468")
  end

  test "validateConfirmation fails when confirmation missing" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateConfirmationFailsWhenConfirmationMissing/1, "src/changeset_test.temper.md:484")
  end

  test "validateContains passes when substring found" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateContainsPassesWhenSubstringFound/1, "src/changeset_test.temper.md:500")
  end

  test "validateContains fails when substring not found" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateContainsFailsWhenSubstringNotFound/1, "src/changeset_test.temper.md:508")
  end

  test "validateContains skips when field not in changes" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateContainsSkipsWhenFieldNotInChanges/1, "src/changeset_test.temper.md:516")
  end

  test "validateStartsWith passes" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateStartsWithPasses/1, "src/changeset_test.temper.md:526")
  end

  test "validateStartsWith fails" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateStartsWithFails/1, "src/changeset_test.temper.md:534")
  end

  test "validateEndsWith passes" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateEndsWithPasses/1, "src/changeset_test.temper.md:544")
  end

  test "validateEndsWith fails" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateEndsWithFails/1, "src/changeset_test.temper.md:552")
  end

  test "validateEndsWith handles repeated suffix correctly" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateEndsWithHandlesRepeatedSuffixCorrectly/1, "src/changeset_test.temper.md:560")
  end

  test "toInsertSql uses default value when field not in changes" do
    TemperCore.Test.check(&Temper.Orm.Tests.toInsertSqlUsesDefaultValueWhenFieldNotInChanges/1, "src/changeset_test.temper.md:570")
  end

  test "toInsertSql change overrides default value" do
    TemperCore.Test.check(&Temper.Orm.Tests.toInsertSqlChangeOverridesDefaultValue/1, "src/changeset_test.temper.md:583")
  end

  test "toInsertSql with timestamps uses DEFAULT" do
    TemperCore.Test.check(&Temper.Orm.Tests.toInsertSqlWithTimestampsUsesDefault/1, "src/changeset_test.temper.md:597")
  end

  test "toInsertSql skips virtual fields" do
    TemperCore.Test.check(&Temper.Orm.Tests.toInsertSqlSkipsVirtualFields/1, "src/changeset_test.temper.md:611")
  end

  test "toInsertSql allows missing non-nullable virtual field" do
    TemperCore.Test.check(&Temper.Orm.Tests.toInsertSqlAllowsMissingNonNullableVirtualField/1, "src/changeset_test.temper.md:626")
  end

  test "toUpdateSql skips virtual fields" do
    TemperCore.Test.check(&Temper.Orm.Tests.toUpdateSqlSkipsVirtualFields/1, "src/changeset_test.temper.md:638")
  end

  test "toUpdateSql uses custom primary key" do
    TemperCore.Test.check(&Temper.Orm.Tests.toUpdateSqlUsesCustomPrimaryKey/1, "src/changeset_test.temper.md:653")
  end

  test "deleteSql uses custom primary key" do
    TemperCore.Test.check(&Temper.Orm.Tests.deleteSqlUsesCustomPrimaryKey/1, "src/changeset_test.temper.md:663")
  end

  test "deleteSql uses default id when primaryKey null" do
    TemperCore.Test.check(&Temper.Orm.Tests.deleteSqlUsesDefaultIdWhenPrimaryKeyNull/1, "src/changeset_test.temper.md:671")
  end

  test "already-invalid changeset skips subsequent validators" do
    TemperCore.Test.check(&Temper.Orm.Tests.alreadyInvalidChangesetSkipsSubsequentValidators/1, "src/changeset_test.temper.md:683")
  end

  test "validateNumber lessThanOrEqual passes at boundary" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateNumberLessThanOrEqualPassesAtBoundary/1, "src/changeset_test.temper.md:700")
  end

  test "validateNumber lessThanOrEqual fails above boundary" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateNumberLessThanOrEqualFailsAboveBoundary/1, "src/changeset_test.temper.md:708")
  end

  test "validateNumber equalTo passes when equal" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateNumberEqualToPassesWhenEqual/1, "src/changeset_test.temper.md:717")
  end

  test "validateNumber equalTo fails when not equal" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateNumberEqualToFailsWhenNotEqual/1, "src/changeset_test.temper.md:725")
  end

  test "validateNumber greaterThan fails at exact threshold" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateNumberGreaterThanFailsAtExactThreshold/1, "src/changeset_test.temper.md:734")
  end

  test "validateNumber lessThan fails at exact threshold" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateNumberLessThanFailsAtExactThreshold/1, "src/changeset_test.temper.md:742")
  end

  test "validateFloat fails for non-float string" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateFloatFailsForNonFloatString/1, "src/changeset_test.temper.md:752")
  end

  test "toInsertSql with all six field types" do
    TemperCore.Test.check(&Temper.Orm.Tests.toInsertSqlWithAllSixFieldTypes/1, "src/changeset_test.temper.md:763")
  end

  test "deleteChange on non-nullable field causes toInsertSql to bubble" do
    TemperCore.Test.check(&Temper.Orm.Tests.deleteChangeOnNonNullableFieldCausesToInsertSqlToBubble/1, "src/changeset_test.temper.md:795")
  end

  test "validateLength passes at exact min" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateLengthPassesAtExactMin/1, "src/changeset_test.temper.md:813")
  end

  test "validateLength passes at exact max" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateLengthPassesAtExactMax/1, "src/changeset_test.temper.md:821")
  end

  test "validateAcceptance skips when field not in changes" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateAcceptanceSkipsWhenFieldNotInChanges/1, "src/changeset_test.temper.md:831")
  end

  test "multiple validators chain correctly on valid changeset" do
    TemperCore.Test.check(&Temper.Orm.Tests.multipleValidatorsChainCorrectlyOnValidChangeset/1, "src/changeset_test.temper.md:841")
  end

  test "toUpdateSql with multiple non-virtual fields" do
    TemperCore.Test.check(&Temper.Orm.Tests.toUpdateSqlWithMultipleNonVirtualFields/1, "src/changeset_test.temper.md:860")
  end

  test "toUpdateSql bubbles when all changes are virtual fields" do
    TemperCore.Test.check(&Temper.Orm.Tests.toUpdateSqlBubblesWhenAllChangesAreVirtualFields/1, "src/changeset_test.temper.md:878")
  end

  test "putChange satisfies subsequent validateRequired" do
    TemperCore.Test.check(&Temper.Orm.Tests.putChangeSatisfiesSubsequentValidateRequired/1, "src/changeset_test.temper.md:894")
  end

  test "validateStartsWith skips when field not in changes" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateStartsWithSkipsWhenFieldNotInChanges/1, "src/changeset_test.temper.md:905")
  end

  test "validateEndsWith skips when field not in changes" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateEndsWithSkipsWhenFieldNotInChanges/1, "src/changeset_test.temper.md:915")
  end

  test "validateInt accepts zero" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateIntAcceptsZero/1, "src/changeset_test.temper.md:925")
  end

  test "validateInt accepts negative" do
    TemperCore.Test.check(&Temper.Orm.Tests.validateIntAcceptsNegative/1, "src/changeset_test.temper.md:933")
  end

  test "changeset immutability - validators do not mutate base" do
    TemperCore.Test.check(&Temper.Orm.Tests.changesetImmutabilityValidatorsDoNotMutateBase/1, "src/changeset_test.temper.md:943")
  end
end
