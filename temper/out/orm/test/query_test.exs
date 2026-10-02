defmodule Temper.Orm.QueryTest do
  use ExUnit.Case

  setup_all do
    Temper.Orm.Tests.__temper_init__()
    :ok
  end

  test "bare from produces SELECT *" do
    TemperCore.Test.check(&Temper.Orm.Tests.bareFromProducesSelect/1, "src/query_test.temper.md:7")
  end

  test "select restricts columns" do
    TemperCore.Test.check(&Temper.Orm.Tests.selectRestrictsColumns/1, "src/query_test.temper.md:12")
  end

  test "where adds condition with int value" do
    TemperCore.Test.check(&Temper.Orm.Tests.whereAddsConditionWithIntValue/1, "src/query_test.temper.md:17")
  end

  test "where adds condition with bool value" do
    TemperCore.Test.check(&Temper.Orm.Tests.whereAddsConditionWithBoolValue/1, "src/query_test.temper.md:22")
  end

  test "chained where uses AND" do
    TemperCore.Test.check(&Temper.Orm.Tests.chainedWhereUsesAnd/1, "src/query_test.temper.md:27")
  end

  test "orderBy ASC" do
    TemperCore.Test.check(&Temper.Orm.Tests.orderByAsc/1, "src/query_test.temper.md:36")
  end

  test "orderBy DESC" do
    TemperCore.Test.check(&Temper.Orm.Tests.orderByDesc/1, "src/query_test.temper.md:41")
  end

  test "limit and offset" do
    TemperCore.Test.check(&Temper.Orm.Tests.limitAndOffset/1, "src/query_test.temper.md:48")
  end

  test "limit bubbles on negative" do
    TemperCore.Test.check(&Temper.Orm.Tests.limitBubblesOnNegative/1, "src/query_test.temper.md:53")
  end

  test "offset bubbles on negative" do
    TemperCore.Test.check(&Temper.Orm.Tests.offsetBubblesOnNegative/1, "src/query_test.temper.md:58")
  end

  test "complex composed query" do
    TemperCore.Test.check(&Temper.Orm.Tests.complexComposedQuery/1, "src/query_test.temper.md:63")
  end

  test "safeToSql applies default limit when none set" do
    TemperCore.Test.check(&Temper.Orm.Tests.safeToSqlAppliesDefaultLimitWhenNoneSet/1, "src/query_test.temper.md:80")
  end

  test "safeToSql respects explicit limit" do
    TemperCore.Test.check(&Temper.Orm.Tests.safeToSqlRespectsExplicitLimit/1, "src/query_test.temper.md:86")
  end

  test "safeToSql bubbles on negative defaultLimit" do
    TemperCore.Test.check(&Temper.Orm.Tests.safeToSqlBubblesOnNegativeDefaultLimit/1, "src/query_test.temper.md:92")
  end

  test "where with injection attempt in string value is escaped" do
    TemperCore.Test.check(&Temper.Orm.Tests.whereWithInjectionAttemptInStringValueIsEscaped/1, "src/query_test.temper.md:97")
  end

  test "safeIdentifier rejects user-supplied table name with metacharacters" do
    TemperCore.Test.check(&Temper.Orm.Tests.safeIdentifierRejectsUserSuppliedTableNameWithMetacharacters/1, "src/query_test.temper.md:106")
  end

  test "innerJoin produces INNER JOIN" do
    TemperCore.Test.check(&Temper.Orm.Tests.innerJoinProducesInnerJoin/1, "src/query_test.temper.md:113")
  end

  test "leftJoin produces LEFT JOIN" do
    TemperCore.Test.check(&Temper.Orm.Tests.leftJoinProducesLeftJoin/1, "src/query_test.temper.md:121")
  end

  test "rightJoin produces RIGHT JOIN" do
    TemperCore.Test.check(&Temper.Orm.Tests.rightJoinProducesRightJoin/1, "src/query_test.temper.md:129")
  end

  test "fullJoin produces FULL OUTER JOIN" do
    TemperCore.Test.check(&Temper.Orm.Tests.fullJoinProducesFullOuterJoin/1, "src/query_test.temper.md:137")
  end

  test "chained joins" do
    TemperCore.Test.check(&Temper.Orm.Tests.chainedJoins/1, "src/query_test.temper.md:145")
  end

  test "join with where and orderBy" do
    TemperCore.Test.check(&Temper.Orm.Tests.joinWithWhereAndOrderBy/1, "src/query_test.temper.md:154")
  end

  test "col helper produces qualified reference" do
    TemperCore.Test.check(&Temper.Orm.Tests.colHelperProducesQualifiedReference/1, "src/query_test.temper.md:167")
  end

  test "join with col helper" do
    TemperCore.Test.check(&Temper.Orm.Tests.joinWithColHelper/1, "src/query_test.temper.md:172")
  end

  test "orWhere basic" do
    TemperCore.Test.check(&Temper.Orm.Tests.orWhereBasic/1, "src/query_test.temper.md:187")
  end

  test "where then orWhere" do
    TemperCore.Test.check(&Temper.Orm.Tests.whereThenOrWhere/1, "src/query_test.temper.md:192")
  end

  test "multiple orWhere" do
    TemperCore.Test.check(&Temper.Orm.Tests.multipleOrWhere/1, "src/query_test.temper.md:201")
  end

  test "mixed where and orWhere" do
    TemperCore.Test.check(&Temper.Orm.Tests.mixedWhereAndOrWhere/1, "src/query_test.temper.md:211")
  end

  test "whereNull" do
    TemperCore.Test.check(&Temper.Orm.Tests.whereNull/1, "src/query_test.temper.md:221")
  end

  test "whereNotNull" do
    TemperCore.Test.check(&Temper.Orm.Tests.whereNotNull/1, "src/query_test.temper.md:226")
  end

  test "whereNull chained with where" do
    TemperCore.Test.check(&Temper.Orm.Tests.whereNullChainedWithWhere/1, "src/query_test.temper.md:231")
  end

  test "whereNotNull chained with orWhere" do
    TemperCore.Test.check(&Temper.Orm.Tests.whereNotNullChainedWithOrWhere/1, "src/query_test.temper.md:240")
  end

  test "whereIn with int values" do
    TemperCore.Test.check(&Temper.Orm.Tests.whereInWithIntValues/1, "src/query_test.temper.md:249")
  end

  test "whereIn with string values escaping" do
    TemperCore.Test.check(&Temper.Orm.Tests.whereInWithStringValuesEscaping/1, "src/query_test.temper.md:254")
  end

  test "whereIn with empty list produces 1=0" do
    TemperCore.Test.check(&Temper.Orm.Tests.whereInWithEmptyListProduces1_0/1, "src/query_test.temper.md:259")
  end

  test "whereIn chained" do
    TemperCore.Test.check(&Temper.Orm.Tests.whereInChained/1, "src/query_test.temper.md:264")
  end

  test "whereIn single element" do
    TemperCore.Test.check(&Temper.Orm.Tests.whereInSingleElement/1, "src/query_test.temper.md:273")
  end

  test "whereNot basic" do
    TemperCore.Test.check(&Temper.Orm.Tests.whereNotBasic/1, "src/query_test.temper.md:278")
  end

  test "whereNot chained" do
    TemperCore.Test.check(&Temper.Orm.Tests.whereNotChained/1, "src/query_test.temper.md:283")
  end

  test "whereBetween integers" do
    TemperCore.Test.check(&Temper.Orm.Tests.whereBetweenIntegers/1, "src/query_test.temper.md:292")
  end

  test "whereBetween chained" do
    TemperCore.Test.check(&Temper.Orm.Tests.whereBetweenChained/1, "src/query_test.temper.md:297")
  end

  test "whereLike basic" do
    TemperCore.Test.check(&Temper.Orm.Tests.whereLikeBasic/1, "src/query_test.temper.md:306")
  end

  test "whereILike basic" do
    TemperCore.Test.check(&Temper.Orm.Tests.whereIlikeBasic/1, "src/query_test.temper.md:311")
  end

  test "whereLike with injection attempt" do
    TemperCore.Test.check(&Temper.Orm.Tests.whereLikeWithInjectionAttempt/1, "src/query_test.temper.md:316")
  end

  test "whereLike wildcard patterns" do
    TemperCore.Test.check(&Temper.Orm.Tests.whereLikeWildcardPatterns/1, "src/query_test.temper.md:323")
  end

  test "countAll produces COUNT(*)" do
    TemperCore.Test.check(&Temper.Orm.Tests.countAllProducesCount/1, "src/query_test.temper.md:330")
  end

  test "countCol produces COUNT(field)" do
    TemperCore.Test.check(&Temper.Orm.Tests.countColProducesCountField/1, "src/query_test.temper.md:335")
  end

  test "sumCol produces SUM(field)" do
    TemperCore.Test.check(&Temper.Orm.Tests.sumColProducesSumField/1, "src/query_test.temper.md:340")
  end

  test "avgCol produces AVG(field)" do
    TemperCore.Test.check(&Temper.Orm.Tests.avgColProducesAvgField/1, "src/query_test.temper.md:345")
  end

  test "minCol produces MIN(field)" do
    TemperCore.Test.check(&Temper.Orm.Tests.minColProducesMinField/1, "src/query_test.temper.md:350")
  end

  test "maxCol produces MAX(field)" do
    TemperCore.Test.check(&Temper.Orm.Tests.maxColProducesMaxField/1, "src/query_test.temper.md:355")
  end

  test "selectExpr with aggregate" do
    TemperCore.Test.check(&Temper.Orm.Tests.selectExprWithAggregate/1, "src/query_test.temper.md:360")
  end

  test "selectExpr with multiple expressions" do
    TemperCore.Test.check(&Temper.Orm.Tests.selectExprWithMultipleExpressions/1, "src/query_test.temper.md:365")
  end

  test "selectExpr overrides selectedFields" do
    TemperCore.Test.check(&Temper.Orm.Tests.selectExprOverridesSelectedFields/1, "src/query_test.temper.md:371")
  end

  test "groupBy single field" do
    TemperCore.Test.check(&Temper.Orm.Tests.groupBySingleField/1, "src/query_test.temper.md:378")
  end

  test "groupBy multiple fields" do
    TemperCore.Test.check(&Temper.Orm.Tests.groupByMultipleFields/1, "src/query_test.temper.md:387")
  end

  test "having basic" do
    TemperCore.Test.check(&Temper.Orm.Tests.havingBasic/1, "src/query_test.temper.md:396")
  end

  test "orHaving" do
    TemperCore.Test.check(&Temper.Orm.Tests.orHaving/1, "src/query_test.temper.md:406")
  end

  test "distinct basic" do
    TemperCore.Test.check(&Temper.Orm.Tests.distinctBasic/1, "src/query_test.temper.md:416")
  end

  test "distinct with where" do
    TemperCore.Test.check(&Temper.Orm.Tests.distinctWithWhere/1, "src/query_test.temper.md:421")
  end

  test "countSql bare" do
    TemperCore.Test.check(&Temper.Orm.Tests.countSqlBare/1, "src/query_test.temper.md:431")
  end

  test "countSql with WHERE" do
    TemperCore.Test.check(&Temper.Orm.Tests.countSqlWithWhere/1, "src/query_test.temper.md:436")
  end

  test "countSql with JOIN" do
    TemperCore.Test.check(&Temper.Orm.Tests.countSqlWithJoin/1, "src/query_test.temper.md:443")
  end

  test "countSql drops orderBy/limit/offset" do
    TemperCore.Test.check(&Temper.Orm.Tests.countSqlDropsOrderByLimitOffset/1, "src/query_test.temper.md:452")
  end

  test "full aggregation query" do
    TemperCore.Test.check(&Temper.Orm.Tests.fullAggregationQuery/1, "src/query_test.temper.md:464")
  end

  test "unionSql" do
    TemperCore.Test.check(&Temper.Orm.Tests.unionSql__2/1, "src/query_test.temper.md:478")
  end

  test "unionAllSql" do
    TemperCore.Test.check(&Temper.Orm.Tests.unionAllSql__2/1, "src/query_test.temper.md:485")
  end

  test "intersectSql" do
    TemperCore.Test.check(&Temper.Orm.Tests.intersectSql__2/1, "src/query_test.temper.md:492")
  end

  test "exceptSql" do
    TemperCore.Test.check(&Temper.Orm.Tests.exceptSql__2/1, "src/query_test.temper.md:499")
  end

  test "subquery with alias" do
    TemperCore.Test.check(&Temper.Orm.Tests.subqueryWithAlias/1, "src/query_test.temper.md:506")
  end

  test "existsSql" do
    TemperCore.Test.check(&Temper.Orm.Tests.existsSql__2/1, "src/query_test.temper.md:512")
  end

  test "whereInSubquery" do
    TemperCore.Test.check(&Temper.Orm.Tests.whereInSubquery/1, "src/query_test.temper.md:518")
  end

  test "set operation with WHERE on each side" do
    TemperCore.Test.check(&Temper.Orm.Tests.setOperationWithWhereOnEachSide/1, "src/query_test.temper.md:525")
  end

  test "whereInSubquery chained with where" do
    TemperCore.Test.check(&Temper.Orm.Tests.whereInSubqueryChainedWithWhere/1, "src/query_test.temper.md:532")
  end

  test "existsSql used in where" do
    TemperCore.Test.check(&Temper.Orm.Tests.existsSqlUsedInWhere/1, "src/query_test.temper.md:541")
  end

  test "UpdateQuery basic" do
    TemperCore.Test.check(&Temper.Orm.Tests.updateQueryBasic/1, "src/query_test.temper.md:550")
  end

  test "UpdateQuery multiple SET" do
    TemperCore.Test.check(&Temper.Orm.Tests.updateQueryMultipleSet/1, "src/query_test.temper.md:560")
  end

  test "UpdateQuery multiple WHERE" do
    TemperCore.Test.check(&Temper.Orm.Tests.updateQueryMultipleWhere/1, "src/query_test.temper.md:571")
  end

  test "UpdateQuery orWhere" do
    TemperCore.Test.check(&Temper.Orm.Tests.updateQueryOrWhere/1, "src/query_test.temper.md:582")
  end

  test "UpdateQuery bubbles without WHERE" do
    TemperCore.Test.check(&Temper.Orm.Tests.updateQueryBubblesWithoutWhere/1, "src/query_test.temper.md:593")
  end

  test "UpdateQuery bubbles without SET" do
    TemperCore.Test.check(&Temper.Orm.Tests.updateQueryBubblesWithoutSet/1, "src/query_test.temper.md:598")
  end

  test "UpdateQuery with limit" do
    TemperCore.Test.check(&Temper.Orm.Tests.updateQueryWithLimit/1, "src/query_test.temper.md:603")
  end

  test "UpdateQuery escaping" do
    TemperCore.Test.check(&Temper.Orm.Tests.updateQueryEscaping/1, "src/query_test.temper.md:614")
  end

  test "DeleteQuery basic" do
    TemperCore.Test.check(&Temper.Orm.Tests.deleteQueryBasic/1, "src/query_test.temper.md:624")
  end

  test "DeleteQuery multiple WHERE" do
    TemperCore.Test.check(&Temper.Orm.Tests.deleteQueryMultipleWhere/1, "src/query_test.temper.md:633")
  end

  test "DeleteQuery bubbles without WHERE" do
    TemperCore.Test.check(&Temper.Orm.Tests.deleteQueryBubblesWithoutWhere/1, "src/query_test.temper.md:643")
  end

  test "DeleteQuery orWhere" do
    TemperCore.Test.check(&Temper.Orm.Tests.deleteQueryOrWhere/1, "src/query_test.temper.md:648")
  end

  test "DeleteQuery with limit" do
    TemperCore.Test.check(&Temper.Orm.Tests.deleteQueryWithLimit/1, "src/query_test.temper.md:658")
  end

  test "orderByNulls NULLS FIRST" do
    TemperCore.Test.check(&Temper.Orm.Tests.orderByNullsNullsFirst/1, "src/query_test.temper.md:670")
  end

  test "orderByNulls NULLS LAST" do
    TemperCore.Test.check(&Temper.Orm.Tests.orderByNullsNullsLast/1, "src/query_test.temper.md:675")
  end

  test "mixed orderBy and orderByNulls" do
    TemperCore.Test.check(&Temper.Orm.Tests.mixedOrderByAndOrderByNulls/1, "src/query_test.temper.md:680")
  end

  test "crossJoin" do
    TemperCore.Test.check(&Temper.Orm.Tests.crossJoin/1, "src/query_test.temper.md:689")
  end

  test "crossJoin combined with other joins" do
    TemperCore.Test.check(&Temper.Orm.Tests.crossJoinCombinedWithOtherJoins/1, "src/query_test.temper.md:694")
  end

  test "lock FOR UPDATE" do
    TemperCore.Test.check(&Temper.Orm.Tests.lockForUpdate/1, "src/query_test.temper.md:703")
  end

  test "lock FOR SHARE" do
    TemperCore.Test.check(&Temper.Orm.Tests.lockForShare/1, "src/query_test.temper.md:710")
  end

  test "lock with full query" do
    TemperCore.Test.check(&Temper.Orm.Tests.lockWithFullQuery/1, "src/query_test.temper.md:717")
  end

  test "query builder immutability - two queries from same base" do
    TemperCore.Test.check(&Temper.Orm.Tests.queryBuilderImmutabilityTwoQueriesFromSameBase/1, "src/query_test.temper.md:729")
  end

  test "limit zero produces LIMIT 0" do
    TemperCore.Test.check(&Temper.Orm.Tests.limitZeroProducesLimit0/1, "src/query_test.temper.md:737")
  end

  test "safeToSql with zero defaultLimit" do
    TemperCore.Test.check(&Temper.Orm.Tests.safeToSqlWithZeroDefaultLimit/1, "src/query_test.temper.md:742")
  end

  test "UpdateQuery limit bubbles on negative" do
    TemperCore.Test.check(&Temper.Orm.Tests.updateQueryLimitBubblesOnNegative/1, "src/query_test.temper.md:748")
  end

  test "DeleteQuery limit bubbles on negative" do
    TemperCore.Test.check(&Temper.Orm.Tests.deleteQueryLimitBubblesOnNegative/1, "src/query_test.temper.md:759")
  end

  test "UpdateQuery immutability - two from same base" do
    TemperCore.Test.check(&Temper.Orm.Tests.updateQueryImmutabilityTwoFromSameBase/1, "src/query_test.temper.md:769")
  end

  test "DeleteQuery immutability" do
    TemperCore.Test.check(&Temper.Orm.Tests.deleteQueryImmutability/1, "src/query_test.temper.md:782")
  end
end
