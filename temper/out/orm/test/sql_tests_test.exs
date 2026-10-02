defmodule Temper.Orm.SqlTestsTest do
  use ExUnit.Case

  setup_all do
    Temper.Orm.Tests.__temper_init__()
    :ok
  end

  test "string escaping" do
    TemperCore.Test.check(&Temper.Orm.Tests.stringEscaping/1, "src/sql_tests.temper.md:7")
  end

  test "string edge cases" do
    TemperCore.Test.check(&Temper.Orm.Tests.stringEdgeCases/1, "src/sql_tests.temper.md:40")
  end

  test "numbers and booleans" do
    TemperCore.Test.check(&Temper.Orm.Tests.numbersAndBooleans/1, "src/sql_tests.temper.md:60")
  end

  test "lists" do
    TemperCore.Test.check(&Temper.Orm.Tests.lists/1, "src/sql_tests.temper.md:78")
  end

  test "SqlFloat64 NaN renders as NULL" do
    TemperCore.Test.check(&Temper.Orm.Tests.sqlFloat64_naNRendersAsNull/1, "src/sql_tests.temper.md:97")
  end

  test "SqlFloat64 Infinity renders as NULL" do
    TemperCore.Test.check(&Temper.Orm.Tests.sqlFloat64_infinityRendersAsNull/1, "src/sql_tests.temper.md:102")
  end

  test "SqlFloat64 negative Infinity renders as NULL" do
    TemperCore.Test.check(&Temper.Orm.Tests.sqlFloat64_negativeInfinityRendersAsNull/1, "src/sql_tests.temper.md:107")
  end

  test "SqlFloat64 normal values still work" do
    TemperCore.Test.check(&Temper.Orm.Tests.sqlFloat64_normalValuesStillWork/1, "src/sql_tests.temper.md:112")
  end

  test "SqlDate renders with quotes" do
    TemperCore.Test.check(&Temper.Orm.Tests.sqlDateRendersWithQuotes/1, "src/sql_tests.temper.md:120")
  end

  test "nesting" do
    TemperCore.Test.check(&Temper.Orm.Tests.nesting/1, "src/sql_tests.temper.md:129")
  end

  test "SqlInt32 negative and zero values" do
    TemperCore.Test.check(&Temper.Orm.Tests.sqlInt32_negativeAndZeroValues/1, "src/sql_tests.temper.md:155")
  end

  test "SqlInt64 negative value" do
    TemperCore.Test.check(&Temper.Orm.Tests.sqlInt64_negativeValue/1, "src/sql_tests.temper.md:160")
  end

  test "single element list rendering" do
    TemperCore.Test.check(&Temper.Orm.Tests.singleElementListRendering/1, "src/sql_tests.temper.md:164")
  end

  test "SqlDefault renders DEFAULT keyword" do
    TemperCore.Test.check(&Temper.Orm.Tests.sqlDefaultRendersDefaultKeyword/1, "src/sql_tests.temper.md:169")
  end

  test "SqlString with backslash" do
    TemperCore.Test.check(&Temper.Orm.Tests.sqlStringWithBackslash/1, "src/sql_tests.temper.md:176")
  end

  test "toParameterized numbers the values and keeps them out of the text" do
    TemperCore.Test.check(&Temper.Orm.Tests.toParameterizedNumbersTheValuesAndKeepsThemOutOfTheText/1, "src/sql_tests.temper.md:186")
  end

  test "toParameterized leaves what is not data in the text" do
    TemperCore.Test.check(&Temper.Orm.Tests.toParameterizedLeavesWhatIsNotDataInTheText/1, "src/sql_tests.temper.md:196")
  end

  test "toParameterized works on a whole query" do
    TemperCore.Test.check(&Temper.Orm.Tests.toParameterizedWorksOnAWholeQuery/1, "src/sql_tests.temper.md:212")
  end

  test "toParameterized with no values is the same text as toString" do
    TemperCore.Test.check(&Temper.Orm.Tests.toParameterizedWithNoValuesIsTheSameTextAsToString/1, "src/sql_tests.temper.md:222")
  end
end
