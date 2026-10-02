defmodule Temper.Orm.SchemaTest do
  use ExUnit.Case

  setup_all do
    Temper.Orm.Tests.__temper_init__()
    :ok
  end

  test "safeIdentifier accepts valid names" do
    TemperCore.Test.check(&Temper.Orm.Tests.safeIdentifierAcceptsValidNames/1, "src/schema_test.temper.md:3")
  end

  test "safeIdentifier rejects empty string" do
    TemperCore.Test.check(&Temper.Orm.Tests.safeIdentifierRejectsEmptyString/1, "src/schema_test.temper.md:8")
  end

  test "safeIdentifier rejects leading digit" do
    TemperCore.Test.check(&Temper.Orm.Tests.safeIdentifierRejectsLeadingDigit/1, "src/schema_test.temper.md:13")
  end

  test "safeIdentifier rejects SQL metacharacters" do
    TemperCore.Test.check(&Temper.Orm.Tests.safeIdentifierRejectsSqlMetacharacters/1, "src/schema_test.temper.md:18")
  end

  test "TableDef field lookup - found" do
    TemperCore.Test.check(&Temper.Orm.Tests.tableDefFieldLookupFound/1, "src/schema_test.temper.md:26")
  end

  test "TableDef field lookup - not found bubbles" do
    TemperCore.Test.check(&Temper.Orm.Tests.tableDefFieldLookupNotFoundBubbles/1, "src/schema_test.temper.md:39")
  end

  test "FieldDef nullable flag" do
    TemperCore.Test.check(&Temper.Orm.Tests.fieldDefNullableFlag/1, "src/schema_test.temper.md:49")
  end

  test "pkName defaults to id when primaryKey is null" do
    TemperCore.Test.check(&Temper.Orm.Tests.pkNameDefaultsToIdWhenPrimaryKeyIsNull/1, "src/schema_test.temper.md:58")
  end

  test "pkName returns custom primary key" do
    TemperCore.Test.check(&Temper.Orm.Tests.pkNameReturnsCustomPrimaryKey/1, "src/schema_test.temper.md:67")
  end

  test "timestamps returns two DateField defs" do
    TemperCore.Test.check(&Temper.Orm.Tests.timestampsReturnsTwoDateFieldDefs/1, "src/schema_test.temper.md:76")
  end

  test "FieldDef defaultValue field" do
    TemperCore.Test.check(&Temper.Orm.Tests.fieldDefDefaultValueField/1, "src/schema_test.temper.md:87")
  end

  test "FieldDef virtual flag" do
    TemperCore.Test.check(&Temper.Orm.Tests.fieldDefVirtualFlag/1, "src/schema_test.temper.md:98")
  end

  test "safeIdentifier accepts single character names" do
    TemperCore.Test.check(&Temper.Orm.Tests.safeIdentifierAcceptsSingleCharacterNames/1, "src/schema_test.temper.md:107")
  end

  test "safeIdentifier accepts all-underscore names" do
    TemperCore.Test.check(&Temper.Orm.Tests.safeIdentifierAcceptsAllUnderscoreNames/1, "src/schema_test.temper.md:114")
  end

  test "TableDef with empty field list" do
    TemperCore.Test.check(&Temper.Orm.Tests.tableDefWithEmptyFieldList/1, "src/schema_test.temper.md:119")
  end
end
