defmodule Temper.Orm.Tests do
  def csid(name) do
    try do
      try do
        throw({:temper_return, :ex_return_0, Temper.Orm.safeIdentifier(name)})
      rescue
        _ in TemperCore.Bubble ->
          throw({:temper_return, :ex_return_0, raise(TemperCore.Panic)})
      end
      nil
    catch
      {:temper_return, :ex_return_0, ex_value_1} ->
        ex_value_1
    end
  end
  def userTable() do
    Temper.Orm.TableDef.new(Temper.Orm.Tests.csid("users"), %TemperCore.Vec{t: {Temper.Orm.FieldDef.new(Temper.Orm.Tests.csid("name"), Temper.Orm.StringField.new(), false, nil, false), Temper.Orm.FieldDef.new(Temper.Orm.Tests.csid("email"), Temper.Orm.StringField.new(), false, nil, false), Temper.Orm.FieldDef.new(Temper.Orm.Tests.csid("age"), Temper.Orm.IntField.new(), true, nil, false), Temper.Orm.FieldDef.new(Temper.Orm.Tests.csid("score"), Temper.Orm.FloatField.new(), true, nil, false), Temper.Orm.FieldDef.new(Temper.Orm.Tests.csid("active"), Temper.Orm.BoolField.new(), true, nil, false)}}, nil)
  end
  def castWhitelistsAllowedFields(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("name", "Alice"), TemperCore.Pair.new("email", "alice@example.com"), TemperCore.Pair.new("admin", "true")}})
    cs = TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name"), Temper.Orm.Tests.csid("email")}}])
    fn_1 = fn ->
      "name should be in changes"
    end
    TemperCore.Test.assert(test, TemperCore.Map.has(TemperCore.call(cs, :get_changes, []), "name"), fn_1)
    fn_2 = fn ->
      "email should be in changes"
    end
    TemperCore.Test.assert(test, TemperCore.Map.has(TemperCore.call(cs, :get_changes, []), "email"), fn_2)
    fn_3 = fn ->
      "admin must be dropped (not in whitelist)"
    end
    TemperCore.Test.assert(test, not TemperCore.Map.has(TemperCore.call(cs, :get_changes, []), "admin"), fn_3)
    fn_4 = fn ->
      "should still be valid"
    end
    TemperCore.Test.assert(test, TemperCore.call(cs, :get_isValid, []), fn_4)
    nil
  end
  def castIsReplacingNotAdditiveSecondCallResetsWhitelist(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("name", "Alice"), TemperCore.Pair.new("email", "alice@example.com")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name")}}]), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("email")}}])
    fn_1 = fn ->
      "name must be excluded by second cast"
    end
    TemperCore.Test.assert(test, not TemperCore.Map.has(TemperCore.call(cs, :get_changes, []), "name"), fn_1)
    fn_2 = fn ->
      "email should be present"
    end
    TemperCore.Test.assert(test, TemperCore.Map.has(TemperCore.call(cs, :get_changes, []), "email"), fn_2)
    nil
  end
  def castIgnoresEmptyStringValues(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("name", ""), TemperCore.Pair.new("email", "bob@example.com")}})
    cs = TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name"), Temper.Orm.Tests.csid("email")}}])
    fn_1 = fn ->
      "empty name should not be in changes"
    end
    TemperCore.Test.assert(test, not TemperCore.Map.has(TemperCore.call(cs, :get_changes, []), "name"), fn_1)
    fn_2 = fn ->
      "email should be in changes"
    end
    TemperCore.Test.assert(test, TemperCore.Map.has(TemperCore.call(cs, :get_changes, []), "email"), fn_2)
    nil
  end
  def validateRequiredPassesWhenFieldPresent(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("name", "Alice")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name")}}]), :validateRequired, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name")}}])
    fn_1 = fn ->
      "should be valid"
    end
    TemperCore.Test.assert(test, TemperCore.call(cs, :get_isValid, []), fn_1)
    fn_2 = fn ->
      "no errors expected"
    end
    TemperCore.Test.assert(test, TemperCore.List.length(TemperCore.call(cs, :get_errors, [])) == 0, fn_2)
    nil
  end
  def validateRequiredFailsWhenFieldMissing(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name")}}]), :validateRequired, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name")}}])
    fn_1 = fn ->
      "should be invalid"
    end
    TemperCore.Test.assert(test, not TemperCore.call(cs, :get_isValid, []), fn_1)
    fn_2 = fn ->
      "should have one error"
    end
    TemperCore.Test.assert(test, TemperCore.List.length(TemperCore.call(cs, :get_errors, [])) == 1, fn_2)
    fn_3 = fn ->
      "error should name the field"
    end
    TemperCore.Test.assert(test, Temper.Orm.ChangesetError.get_field(TemperCore.List.get(TemperCore.call(cs, :get_errors, []), 0)) == "name", fn_3)
    nil
  end
  def validateLengthPassesWithinRange(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("name", "Alice")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name")}}]), :validateLength, [Temper.Orm.Tests.csid("name"), 2, 50])
    fn_ = fn ->
      "should be valid"
    end
    TemperCore.Test.assert(test, TemperCore.call(cs, :get_isValid, []), fn_)
    nil
  end
  def validateLengthFailsWhenTooShort(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("name", "A")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name")}}]), :validateLength, [Temper.Orm.Tests.csid("name"), 2, 50])
    fn_ = fn ->
      "should be invalid"
    end
    TemperCore.Test.assert(test, not TemperCore.call(cs, :get_isValid, []), fn_)
    nil
  end
  def validateLengthFailsWhenTooLong(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("name", "ABCDEFGHIJKLMNOPQRSTUVWXYZ")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name")}}]), :validateLength, [Temper.Orm.Tests.csid("name"), 2, 10])
    fn_ = fn ->
      "should be invalid"
    end
    TemperCore.Test.assert(test, not TemperCore.call(cs, :get_isValid, []), fn_)
    nil
  end
  def validateIntPassesForValidInteger(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("age", "30")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("age")}}]), :validateInt, [Temper.Orm.Tests.csid("age")])
    fn_ = fn ->
      "should be valid"
    end
    TemperCore.Test.assert(test, TemperCore.call(cs, :get_isValid, []), fn_)
    nil
  end
  def validateIntFailsForNonInteger(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("age", "not-a-number")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("age")}}]), :validateInt, [Temper.Orm.Tests.csid("age")])
    fn_ = fn ->
      "should be invalid"
    end
    TemperCore.Test.assert(test, not TemperCore.call(cs, :get_isValid, []), fn_)
    nil
  end
  def validateFloatPassesForValidFloat(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("score", "9.5")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("score")}}]), :validateFloat, [Temper.Orm.Tests.csid("score")])
    fn_ = fn ->
      "should be valid"
    end
    TemperCore.Test.assert(test, TemperCore.call(cs, :get_isValid, []), fn_)
    nil
  end
  def validateInt64_passesForValid64_bitInteger(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("age", "9999999999")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("age")}}]), :validateInt64, [Temper.Orm.Tests.csid("age")])
    fn_ = fn ->
      "should be valid"
    end
    TemperCore.Test.assert(test, TemperCore.call(cs, :get_isValid, []), fn_)
    nil
  end
  def validateInt64_failsForNonInteger(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("age", "not-a-number")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("age")}}]), :validateInt64, [Temper.Orm.Tests.csid("age")])
    fn_ = fn ->
      "should be invalid"
    end
    TemperCore.Test.assert(test, not TemperCore.call(cs, :get_isValid, []), fn_)
    nil
  end
  def validateBoolAcceptsTrue1_yesOn(test) do
    this = %TemperCore.Vec{t: {"true", "1", "yes", "on"}}
    n = TemperCore.List.length(this)
    i = 0
    ex_loop_1 = fn ex_loop_1, i ->
      if i < n do
        el = TemperCore.List.get(this, i)
        i = TemperCore.int32(i + 1)
        v = el
        params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("active", v)}})
        cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("active")}}]), :validateBool, [Temper.Orm.Tests.csid("active")])
        fn_ = fn ->
          "should accept: " <> v
        end
        TemperCore.Test.assert(test, TemperCore.call(cs, :get_isValid, []), fn_)
        ex_loop_1.(ex_loop_1, i)
      else
        i
      end
    end
    _i = ex_loop_1.(ex_loop_1, i)
    nil
  end
  def validateBoolAcceptsFalse0_noOff(test) do
    this = %TemperCore.Vec{t: {"false", "0", "no", "off"}}
    n = TemperCore.List.length(this)
    i = 0
    ex_loop_1 = fn ex_loop_1, i ->
      if i < n do
        el = TemperCore.List.get(this, i)
        i = TemperCore.int32(i + 1)
        v = el
        params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("active", v)}})
        cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("active")}}]), :validateBool, [Temper.Orm.Tests.csid("active")])
        fn_ = fn ->
          "should accept: " <> v
        end
        TemperCore.Test.assert(test, TemperCore.call(cs, :get_isValid, []), fn_)
        ex_loop_1.(ex_loop_1, i)
      else
        i
      end
    end
    _i = ex_loop_1.(ex_loop_1, i)
    nil
  end
  def validateBoolRejectsAmbiguousValues(test) do
    this = %TemperCore.Vec{t: {"TRUE", "Yes", "maybe", "2", "enabled"}}
    n = TemperCore.List.length(this)
    i = 0
    ex_loop_1 = fn ex_loop_1, i ->
      if i < n do
        el = TemperCore.List.get(this, i)
        i = TemperCore.int32(i + 1)
        v = el
        params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("active", v)}})
        cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("active")}}]), :validateBool, [Temper.Orm.Tests.csid("active")])
        fn_ = fn ->
          "should reject ambiguous: " <> v
        end
        TemperCore.Test.assert(test, not TemperCore.call(cs, :get_isValid, []), fn_)
        ex_loop_1.(ex_loop_1, i)
      else
        i
      end
    end
    _i = ex_loop_1.(ex_loop_1, i)
    nil
  end
  def toInsertSqlEscapesBobbyTables(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("name", "Robert'); DROP TABLE users;--"), TemperCore.Pair.new("email", "bobby@evil.com")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name"), Temper.Orm.Tests.csid("email")}}]), :validateRequired, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name"), Temper.Orm.Tests.csid("email")}}])
    _sqlFrag = nil
    sqlFrag = try do
      sqlFrag = TemperCore.call(cs, :toInsertSql, [])
      sqlFrag
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    s = Temper.Orm.SqlFragment.toString(sqlFrag)
    t = TemperCore.String.index_of(s, "''") >= 0
    fn_ = fn ->
      "single quote must be doubled: " <> s
    end
    TemperCore.Test.assert(test, t, fn_)
    nil
  end
  def toInsertSqlProducesCorrectSqlForStringField(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("name", "Alice"), TemperCore.Pair.new("email", "a@example.com")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name"), Temper.Orm.Tests.csid("email")}}]), :validateRequired, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name"), Temper.Orm.Tests.csid("email")}}])
    _sqlFrag = nil
    sqlFrag = try do
      sqlFrag = TemperCore.call(cs, :toInsertSql, [])
      sqlFrag
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    s = Temper.Orm.SqlFragment.toString(sqlFrag)
    t1 = TemperCore.String.index_of(s, "INSERT INTO users") >= 0
    fn_1 = fn ->
      "has INSERT INTO: " <> s
    end
    TemperCore.Test.assert(test, t1, fn_1)
    t2 = TemperCore.String.index_of(s, "'Alice'") >= 0
    fn_2 = fn ->
      "has quoted name: " <> s
    end
    TemperCore.Test.assert(test, t2, fn_2)
    nil
  end
  def toInsertSqlProducesCorrectSqlForIntField(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("name", "Bob"), TemperCore.Pair.new("email", "b@example.com"), TemperCore.Pair.new("age", "25")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name"), Temper.Orm.Tests.csid("email"), Temper.Orm.Tests.csid("age")}}]), :validateRequired, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name"), Temper.Orm.Tests.csid("email")}}])
    _sqlFrag = nil
    sqlFrag = try do
      sqlFrag = TemperCore.call(cs, :toInsertSql, [])
      sqlFrag
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    s = Temper.Orm.SqlFragment.toString(sqlFrag)
    t = TemperCore.String.index_of(s, "25") >= 0
    fn_ = fn ->
      "age rendered unquoted: " <> s
    end
    TemperCore.Test.assert(test, t, fn_)
    nil
  end
  def toInsertSqlBubblesOnInvalidChangeset(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name")}}]), :validateRequired, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name")}}])
    _didBubble = nil
    didBubble = try do
      TemperCore.call(cs, :toInsertSql, [])
      didBubble = false
      didBubble
    rescue
      _ in TemperCore.Bubble ->
        didBubble = true
        didBubble
    end
    fn_ = fn ->
      "invalid changeset should bubble"
    end
    TemperCore.Test.assert(test, didBubble, fn_)
    nil
  end
  def toInsertSqlEnforcesNonNullableFieldsIndependentlyOfIsValid(test) do
    strictTable = Temper.Orm.TableDef.new(Temper.Orm.Tests.csid("posts"), %TemperCore.Vec{t: {Temper.Orm.FieldDef.new(Temper.Orm.Tests.csid("title"), Temper.Orm.StringField.new(), false, nil, false), Temper.Orm.FieldDef.new(Temper.Orm.Tests.csid("body"), Temper.Orm.StringField.new(), true, nil, false)}}, nil)
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("body", "hello")}})
    cs = TemperCore.call(Temper.Orm.changeset(strictTable, params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("body")}}])
    fn_1 = fn ->
      "changeset should appear valid (no explicit validation run)"
    end
    TemperCore.Test.assert(test, TemperCore.call(cs, :get_isValid, []), fn_1)
    _didBubble = nil
    didBubble = try do
      TemperCore.call(cs, :toInsertSql, [])
      didBubble = false
      didBubble
    rescue
      _ in TemperCore.Bubble ->
        didBubble = true
        didBubble
    end
    fn_2 = fn ->
      "toInsertSql should enforce nullable regardless of isValid"
    end
    TemperCore.Test.assert(test, didBubble, fn_2)
    nil
  end
  def toUpdateSqlProducesCorrectSql(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("name", "Bob")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name")}}]), :validateRequired, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name")}}])
    _sqlFrag = nil
    sqlFrag = try do
      sqlFrag = TemperCore.call(cs, :toUpdateSql, [42])
      sqlFrag
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    s = Temper.Orm.SqlFragment.toString(sqlFrag)
    fn_ = fn ->
      "got: " <> s
    end
    TemperCore.Test.assert(test, s == "UPDATE users SET name = 'Bob' WHERE id = 42", fn_)
    nil
  end
  def toUpdateSqlBubblesOnInvalidChangeset(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name")}}]), :validateRequired, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name")}}])
    _didBubble = nil
    didBubble = try do
      TemperCore.call(cs, :toUpdateSql, [1])
      didBubble = false
      didBubble
    rescue
      _ in TemperCore.Bubble ->
        didBubble = true
        didBubble
    end
    fn_ = fn ->
      "invalid changeset should bubble"
    end
    TemperCore.Test.assert(test, didBubble, fn_)
    nil
  end
  def putChangeAddsANewField(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("name", "Alice")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name")}}]), :putChange, [Temper.Orm.Tests.csid("email"), "alice@example.com"])
    fn_1 = fn ->
      "email should be in changes"
    end
    TemperCore.Test.assert(test, TemperCore.Map.has(TemperCore.call(cs, :get_changes, []), "email"), fn_1)
    fn_2 = fn ->
      "email value"
    end
    TemperCore.Test.assert(test, TemperCore.Map.get_or(TemperCore.call(cs, :get_changes, []), "email", "") == "alice@example.com", fn_2)
    nil
  end
  def putChangeOverwritesExistingField(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("name", "Alice")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name")}}]), :putChange, [Temper.Orm.Tests.csid("name"), "Bob"])
    fn_ = fn ->
      "name should be overwritten"
    end
    TemperCore.Test.assert(test, TemperCore.Map.get_or(TemperCore.call(cs, :get_changes, []), "name", "") == "Bob", fn_)
    nil
  end
  def putChangeValueAppearsInToInsertSql(test) do
    _t1 = nil
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("name", "Alice"), TemperCore.Pair.new("email", "a@example.com")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name"), Temper.Orm.Tests.csid("email")}}]), :putChange, [Temper.Orm.Tests.csid("name"), "Bob"])
    t1 = try do
      t1 = TemperCore.call(cs, :toInsertSql, [])
      t1
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    s = Temper.Orm.SqlFragment.toString(t1)
    t2 = TemperCore.String.index_of(s, "'Bob'") >= 0
    fn_ = fn ->
      "should use putChange value: " <> s
    end
    TemperCore.Test.assert(test, t2, fn_)
    nil
  end
  def getChangeReturnsValueForExistingField(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("name", "Alice")}})
    cs = TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name")}}])
    _val = nil
    val = try do
      val = TemperCore.call(cs, :getChange, [Temper.Orm.Tests.csid("name")])
      val
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    fn_ = fn ->
      "should return Alice"
    end
    TemperCore.Test.assert(test, val == "Alice", fn_)
    nil
  end
  def getChangeBubblesOnMissingField(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("name", "Alice")}})
    cs = TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name")}}])
    _didBubble = nil
    didBubble = try do
      TemperCore.call(cs, :getChange, [Temper.Orm.Tests.csid("email")])
      didBubble = false
      didBubble
    rescue
      _ in TemperCore.Bubble ->
        didBubble = true
        didBubble
    end
    fn_ = fn ->
      "should bubble for missing field"
    end
    TemperCore.Test.assert(test, didBubble, fn_)
    nil
  end
  def deleteChangeRemovesField(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("name", "Alice"), TemperCore.Pair.new("email", "a@example.com")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name"), Temper.Orm.Tests.csid("email")}}]), :deleteChange, [Temper.Orm.Tests.csid("email")])
    fn_1 = fn ->
      "email should be removed"
    end
    TemperCore.Test.assert(test, not TemperCore.Map.has(TemperCore.call(cs, :get_changes, []), "email"), fn_1)
    fn_2 = fn ->
      "name should remain"
    end
    TemperCore.Test.assert(test, TemperCore.Map.has(TemperCore.call(cs, :get_changes, []), "name"), fn_2)
    nil
  end
  def deleteChangeOnNonexistentFieldIsNoOp(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("name", "Alice")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name")}}]), :deleteChange, [Temper.Orm.Tests.csid("email")])
    fn_1 = fn ->
      "name should still be present"
    end
    TemperCore.Test.assert(test, TemperCore.Map.has(TemperCore.call(cs, :get_changes, []), "name"), fn_1)
    fn_2 = fn ->
      "should still be valid"
    end
    TemperCore.Test.assert(test, TemperCore.call(cs, :get_isValid, []), fn_2)
    nil
  end
  def validateInclusionPassesWhenValueInList(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("name", "admin")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name")}}]), :validateInclusion, [Temper.Orm.Tests.csid("name"), %TemperCore.Vec{t: {"admin", "user", "guest"}}])
    fn_ = fn ->
      "should be valid"
    end
    TemperCore.Test.assert(test, TemperCore.call(cs, :get_isValid, []), fn_)
    nil
  end
  def validateInclusionFailsWhenValueNotInList(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("name", "hacker")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name")}}]), :validateInclusion, [Temper.Orm.Tests.csid("name"), %TemperCore.Vec{t: {"admin", "user", "guest"}}])
    fn_1 = fn ->
      "should be invalid"
    end
    TemperCore.Test.assert(test, not TemperCore.call(cs, :get_isValid, []), fn_1)
    fn_2 = fn ->
      "error on name"
    end
    TemperCore.Test.assert(test, Temper.Orm.ChangesetError.get_field(TemperCore.List.get(TemperCore.call(cs, :get_errors, []), 0)) == "name", fn_2)
    nil
  end
  def validateInclusionSkipsWhenFieldNotInChanges(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name")}}]), :validateInclusion, [Temper.Orm.Tests.csid("name"), %TemperCore.Vec{t: {"admin", "user"}}])
    fn_ = fn ->
      "should be valid when field absent"
    end
    TemperCore.Test.assert(test, TemperCore.call(cs, :get_isValid, []), fn_)
    nil
  end
  def validateExclusionPassesWhenValueNotInList(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("name", "Alice")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name")}}]), :validateExclusion, [Temper.Orm.Tests.csid("name"), %TemperCore.Vec{t: {"root", "admin", "superuser"}}])
    fn_ = fn ->
      "should be valid"
    end
    TemperCore.Test.assert(test, TemperCore.call(cs, :get_isValid, []), fn_)
    nil
  end
  def validateExclusionFailsWhenValueInList(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("name", "admin")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name")}}]), :validateExclusion, [Temper.Orm.Tests.csid("name"), %TemperCore.Vec{t: {"root", "admin", "superuser"}}])
    fn_1 = fn ->
      "should be invalid"
    end
    TemperCore.Test.assert(test, not TemperCore.call(cs, :get_isValid, []), fn_1)
    fn_2 = fn ->
      "error on name"
    end
    TemperCore.Test.assert(test, Temper.Orm.ChangesetError.get_field(TemperCore.List.get(TemperCore.call(cs, :get_errors, []), 0)) == "name", fn_2)
    nil
  end
  def validateExclusionSkipsWhenFieldNotInChanges(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name")}}]), :validateExclusion, [Temper.Orm.Tests.csid("name"), %TemperCore.Vec{t: {"root", "admin"}}])
    fn_ = fn ->
      "should be valid when field absent"
    end
    TemperCore.Test.assert(test, TemperCore.call(cs, :get_isValid, []), fn_)
    nil
  end
  def validateNumberGreaterThanPasses(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("age", "25")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("age")}}]), :validateNumber, [Temper.Orm.Tests.csid("age"), Temper.Orm.NumberValidationOpts.new(18.0, nil, nil, nil, nil)])
    fn_ = fn ->
      "25 > 18 should pass"
    end
    TemperCore.Test.assert(test, TemperCore.call(cs, :get_isValid, []), fn_)
    nil
  end
  def validateNumberGreaterThanFails(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("age", "15")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("age")}}]), :validateNumber, [Temper.Orm.Tests.csid("age"), Temper.Orm.NumberValidationOpts.new(18.0, nil, nil, nil, nil)])
    fn_ = fn ->
      "15 > 18 should fail"
    end
    TemperCore.Test.assert(test, not TemperCore.call(cs, :get_isValid, []), fn_)
    nil
  end
  def validateNumberLessThanPasses(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("score", "8.5")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("score")}}]), :validateNumber, [Temper.Orm.Tests.csid("score"), Temper.Orm.NumberValidationOpts.new(nil, 10.0, nil, nil, nil)])
    fn_ = fn ->
      "8.5 < 10 should pass"
    end
    TemperCore.Test.assert(test, TemperCore.call(cs, :get_isValid, []), fn_)
    nil
  end
  def validateNumberLessThanFails(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("score", "12.0")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("score")}}]), :validateNumber, [Temper.Orm.Tests.csid("score"), Temper.Orm.NumberValidationOpts.new(nil, 10.0, nil, nil, nil)])
    fn_ = fn ->
      "12 < 10 should fail"
    end
    TemperCore.Test.assert(test, not TemperCore.call(cs, :get_isValid, []), fn_)
    nil
  end
  def validateNumberGreaterThanOrEqualBoundary(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("age", "18")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("age")}}]), :validateNumber, [Temper.Orm.Tests.csid("age"), Temper.Orm.NumberValidationOpts.new(nil, nil, 18.0, nil, nil)])
    fn_ = fn ->
      "18 >= 18 should pass"
    end
    TemperCore.Test.assert(test, TemperCore.call(cs, :get_isValid, []), fn_)
    nil
  end
  def validateNumberCombinedOptions(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("score", "5.0")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("score")}}]), :validateNumber, [Temper.Orm.Tests.csid("score"), Temper.Orm.NumberValidationOpts.new(0.0, 10.0, nil, nil, nil)])
    fn_ = fn ->
      "5 > 0 and < 10 should pass"
    end
    TemperCore.Test.assert(test, TemperCore.call(cs, :get_isValid, []), fn_)
    nil
  end
  def validateNumberNonNumericValue(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("age", "abc")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("age")}}]), :validateNumber, [Temper.Orm.Tests.csid("age"), Temper.Orm.NumberValidationOpts.new(0.0, nil, nil, nil, nil)])
    fn_1 = fn ->
      "non-numeric should fail"
    end
    TemperCore.Test.assert(test, not TemperCore.call(cs, :get_isValid, []), fn_1)
    fn_2 = fn ->
      "correct error message"
    end
    TemperCore.Test.assert(test, Temper.Orm.ChangesetError.get_message(TemperCore.List.get(TemperCore.call(cs, :get_errors, []), 0)) == "must be a number", fn_2)
    nil
  end
  def validateNumberSkipsWhenFieldNotInChanges(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("age")}}]), :validateNumber, [Temper.Orm.Tests.csid("age"), Temper.Orm.NumberValidationOpts.new(0.0, nil, nil, nil, nil)])
    fn_ = fn ->
      "should be valid when field absent"
    end
    TemperCore.Test.assert(test, TemperCore.call(cs, :get_isValid, []), fn_)
    nil
  end
  def validateAcceptancePassesForTrueValues(test) do
    this = %TemperCore.Vec{t: {"true", "1", "yes", "on"}}
    n = TemperCore.List.length(this)
    i = 0
    ex_loop_1 = fn ex_loop_1, i ->
      if i < n do
        el = TemperCore.List.get(this, i)
        i = TemperCore.int32(i + 1)
        v = el
        params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("active", v)}})
        cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("active")}}]), :validateAcceptance, [Temper.Orm.Tests.csid("active")])
        fn_ = fn ->
          "should accept: " <> v
        end
        TemperCore.Test.assert(test, TemperCore.call(cs, :get_isValid, []), fn_)
        ex_loop_1.(ex_loop_1, i)
      else
        i
      end
    end
    _i = ex_loop_1.(ex_loop_1, i)
    nil
  end
  def validateAcceptanceFailsForNonTrueValues(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("active", "false")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("active")}}]), :validateAcceptance, [Temper.Orm.Tests.csid("active")])
    fn_1 = fn ->
      "false should not be accepted"
    end
    TemperCore.Test.assert(test, not TemperCore.call(cs, :get_isValid, []), fn_1)
    fn_2 = fn ->
      "correct message"
    end
    TemperCore.Test.assert(test, Temper.Orm.ChangesetError.get_message(TemperCore.List.get(TemperCore.call(cs, :get_errors, []), 0)) == "must be accepted", fn_2)
    nil
  end
  def validateConfirmationPassesWhenFieldsMatch(test) do
    tbl = Temper.Orm.TableDef.new(Temper.Orm.Tests.csid("users"), %TemperCore.Vec{t: {Temper.Orm.FieldDef.new(Temper.Orm.Tests.csid("password"), Temper.Orm.StringField.new(), false, nil, false), Temper.Orm.FieldDef.new(Temper.Orm.Tests.csid("password_confirmation"), Temper.Orm.StringField.new(), true, nil, false)}}, nil)
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("password", "secret123"), TemperCore.Pair.new("password_confirmation", "secret123")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(tbl, params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("password"), Temper.Orm.Tests.csid("password_confirmation")}}]), :validateConfirmation, [Temper.Orm.Tests.csid("password"), Temper.Orm.Tests.csid("password_confirmation")])
    fn_ = fn ->
      "matching fields should pass"
    end
    TemperCore.Test.assert(test, TemperCore.call(cs, :get_isValid, []), fn_)
    nil
  end
  def validateConfirmationFailsWhenFieldsDiffer(test) do
    tbl = Temper.Orm.TableDef.new(Temper.Orm.Tests.csid("users"), %TemperCore.Vec{t: {Temper.Orm.FieldDef.new(Temper.Orm.Tests.csid("password"), Temper.Orm.StringField.new(), false, nil, false), Temper.Orm.FieldDef.new(Temper.Orm.Tests.csid("password_confirmation"), Temper.Orm.StringField.new(), true, nil, false)}}, nil)
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("password", "secret123"), TemperCore.Pair.new("password_confirmation", "wrong456")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(tbl, params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("password"), Temper.Orm.Tests.csid("password_confirmation")}}]), :validateConfirmation, [Temper.Orm.Tests.csid("password"), Temper.Orm.Tests.csid("password_confirmation")])
    fn_1 = fn ->
      "mismatched fields should fail"
    end
    TemperCore.Test.assert(test, not TemperCore.call(cs, :get_isValid, []), fn_1)
    fn_2 = fn ->
      "error on confirmation field"
    end
    TemperCore.Test.assert(test, Temper.Orm.ChangesetError.get_field(TemperCore.List.get(TemperCore.call(cs, :get_errors, []), 0)) == "password_confirmation", fn_2)
    nil
  end
  def validateConfirmationFailsWhenConfirmationMissing(test) do
    tbl = Temper.Orm.TableDef.new(Temper.Orm.Tests.csid("users"), %TemperCore.Vec{t: {Temper.Orm.FieldDef.new(Temper.Orm.Tests.csid("password"), Temper.Orm.StringField.new(), false, nil, false), Temper.Orm.FieldDef.new(Temper.Orm.Tests.csid("password_confirmation"), Temper.Orm.StringField.new(), true, nil, false)}}, nil)
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("password", "secret123")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(tbl, params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("password")}}]), :validateConfirmation, [Temper.Orm.Tests.csid("password"), Temper.Orm.Tests.csid("password_confirmation")])
    fn_ = fn ->
      "missing confirmation should fail"
    end
    TemperCore.Test.assert(test, not TemperCore.call(cs, :get_isValid, []), fn_)
    nil
  end
  def validateContainsPassesWhenSubstringFound(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("email", "alice@example.com")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("email")}}]), :validateContains, [Temper.Orm.Tests.csid("email"), "@"])
    fn_ = fn ->
      "should pass when @ present"
    end
    TemperCore.Test.assert(test, TemperCore.call(cs, :get_isValid, []), fn_)
    nil
  end
  def validateContainsFailsWhenSubstringNotFound(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("email", "alice-example.com")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("email")}}]), :validateContains, [Temper.Orm.Tests.csid("email"), "@"])
    fn_ = fn ->
      "should fail when @ absent"
    end
    TemperCore.Test.assert(test, not TemperCore.call(cs, :get_isValid, []), fn_)
    nil
  end
  def validateContainsSkipsWhenFieldNotInChanges(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("email")}}]), :validateContains, [Temper.Orm.Tests.csid("email"), "@"])
    fn_ = fn ->
      "should be valid when field absent"
    end
    TemperCore.Test.assert(test, TemperCore.call(cs, :get_isValid, []), fn_)
    nil
  end
  def validateStartsWithPasses(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("name", "Dr. Smith")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name")}}]), :validateStartsWith, [Temper.Orm.Tests.csid("name"), "Dr."])
    fn_ = fn ->
      "should pass for Dr. prefix"
    end
    TemperCore.Test.assert(test, TemperCore.call(cs, :get_isValid, []), fn_)
    nil
  end
  def validateStartsWithFails(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("name", "Mr. Smith")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name")}}]), :validateStartsWith, [Temper.Orm.Tests.csid("name"), "Dr."])
    fn_ = fn ->
      "should fail for Mr. prefix"
    end
    TemperCore.Test.assert(test, not TemperCore.call(cs, :get_isValid, []), fn_)
    nil
  end
  def validateEndsWithPasses(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("email", "alice@example.com")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("email")}}]), :validateEndsWith, [Temper.Orm.Tests.csid("email"), ".com"])
    fn_ = fn ->
      "should pass for .com suffix"
    end
    TemperCore.Test.assert(test, TemperCore.call(cs, :get_isValid, []), fn_)
    nil
  end
  def validateEndsWithFails(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("email", "alice@example.org")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("email")}}]), :validateEndsWith, [Temper.Orm.Tests.csid("email"), ".com"])
    fn_ = fn ->
      "should fail for .org when expecting .com"
    end
    TemperCore.Test.assert(test, not TemperCore.call(cs, :get_isValid, []), fn_)
    nil
  end
  def validateEndsWithHandlesRepeatedSuffixCorrectly(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("name", "abcabc")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name")}}]), :validateEndsWith, [Temper.Orm.Tests.csid("name"), "abc"])
    fn_ = fn ->
      "abcabc should end with abc"
    end
    TemperCore.Test.assert(test, TemperCore.call(cs, :get_isValid, []), fn_)
    nil
  end
  def toInsertSqlUsesDefaultValueWhenFieldNotInChanges(test) do
    _t1 = nil
    tbl = Temper.Orm.TableDef.new(Temper.Orm.Tests.csid("posts"), %TemperCore.Vec{t: {Temper.Orm.FieldDef.new(Temper.Orm.Tests.csid("title"), Temper.Orm.StringField.new(), false, nil, false), Temper.Orm.FieldDef.new(Temper.Orm.Tests.csid("status"), Temper.Orm.StringField.new(), false, Temper.Orm.SqlDefault.new(), false)}}, nil)
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("title", "Hello")}})
    cs = TemperCore.call(Temper.Orm.changeset(tbl, params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("title")}}])
    t1 = try do
      t1 = TemperCore.call(cs, :toInsertSql, [])
      t1
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    s = Temper.Orm.SqlFragment.toString(t1)
    t2 = TemperCore.String.index_of(s, "INSERT INTO posts") >= 0
    fn_1 = fn ->
      "has INSERT INTO: " <> s
    end
    TemperCore.Test.assert(test, t2, fn_1)
    t3 = TemperCore.String.index_of(s, "'Hello'") >= 0
    fn_2 = fn ->
      "has title value: " <> s
    end
    TemperCore.Test.assert(test, t3, fn_2)
    t4 = TemperCore.String.index_of(s, "DEFAULT") >= 0
    fn_3 = fn ->
      "status should use DEFAULT: " <> s
    end
    TemperCore.Test.assert(test, t4, fn_3)
    nil
  end
  def toInsertSqlChangeOverridesDefaultValue(test) do
    _t1 = nil
    tbl = Temper.Orm.TableDef.new(Temper.Orm.Tests.csid("posts"), %TemperCore.Vec{t: {Temper.Orm.FieldDef.new(Temper.Orm.Tests.csid("title"), Temper.Orm.StringField.new(), false, nil, false), Temper.Orm.FieldDef.new(Temper.Orm.Tests.csid("status"), Temper.Orm.StringField.new(), false, Temper.Orm.SqlDefault.new(), false)}}, nil)
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("title", "Hello"), TemperCore.Pair.new("status", "published")}})
    cs = TemperCore.call(Temper.Orm.changeset(tbl, params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("title"), Temper.Orm.Tests.csid("status")}}])
    t1 = try do
      t1 = TemperCore.call(cs, :toInsertSql, [])
      t1
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    s = Temper.Orm.SqlFragment.toString(t1)
    t2 = TemperCore.String.index_of(s, "'published'") >= 0
    fn_ = fn ->
      "should use provided value: " <> s
    end
    TemperCore.Test.assert(test, t2, fn_)
    nil
  end
  def toInsertSqlWithTimestampsUsesDefault(test) do
    _t1 = nil
    _ts = nil
    ts = try do
      ts = Temper.Orm.timestamps()
      ts
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    fields = TemperCore.List.builder()
    TemperCore.List.add(fields, Temper.Orm.FieldDef.new(Temper.Orm.Tests.csid("title"), Temper.Orm.StringField.new(), false, nil, false))
    this = ts
    n = TemperCore.List.length(this)
    i = 0
    ex_loop_1 = fn ex_loop_1, i ->
      if i < n do
        el = TemperCore.List.get(this, i)
        i = TemperCore.int32(i + 1)
        t5 = el
        TemperCore.List.add(fields, t5)
        ex_loop_1.(ex_loop_1, i)
      else
        i
      end
    end
    _i = ex_loop_1.(ex_loop_1, i)
    tbl = Temper.Orm.TableDef.new(Temper.Orm.Tests.csid("articles"), TemperCore.List.to_list(fields), nil)
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("title", "News")}})
    cs = TemperCore.call(Temper.Orm.changeset(tbl, params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("title")}}])
    t1 = try do
      t1 = TemperCore.call(cs, :toInsertSql, [])
      t1
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    s = Temper.Orm.SqlFragment.toString(t1)
    t2 = TemperCore.String.index_of(s, "inserted_at") >= 0
    fn_1 = fn ->
      "should include inserted_at: " <> s
    end
    TemperCore.Test.assert(test, t2, fn_1)
    t3 = TemperCore.String.index_of(s, "updated_at") >= 0
    fn_2 = fn ->
      "should include updated_at: " <> s
    end
    TemperCore.Test.assert(test, t3, fn_2)
    t4 = TemperCore.String.index_of(s, "DEFAULT") >= 0
    fn_3 = fn ->
      "timestamps should use DEFAULT: " <> s
    end
    TemperCore.Test.assert(test, t4, fn_3)
    nil
  end
  def toInsertSqlSkipsVirtualFields(test) do
    _t1 = nil
    tbl = Temper.Orm.TableDef.new(Temper.Orm.Tests.csid("users"), %TemperCore.Vec{t: {Temper.Orm.FieldDef.new(Temper.Orm.Tests.csid("name"), Temper.Orm.StringField.new(), false, nil, false), Temper.Orm.FieldDef.new(Temper.Orm.Tests.csid("full_name"), Temper.Orm.StringField.new(), true, nil, true)}}, nil)
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("name", "Alice"), TemperCore.Pair.new("full_name", "Alice Smith")}})
    cs = TemperCore.call(Temper.Orm.changeset(tbl, params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name"), Temper.Orm.Tests.csid("full_name")}}])
    t1 = try do
      t1 = TemperCore.call(cs, :toInsertSql, [])
      t1
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    s = Temper.Orm.SqlFragment.toString(t1)
    t2 = TemperCore.String.index_of(s, "'Alice'") >= 0
    fn_1 = fn ->
      "name should be included: " <> s
    end
    TemperCore.Test.assert(test, t2, fn_1)
    t3 = TemperCore.String.index_of(s, "full_name") >= 0
    fn_2 = fn ->
      "virtual field should be excluded: " <> s
    end
    TemperCore.Test.assert(test, not t3, fn_2)
    nil
  end
  def toInsertSqlAllowsMissingNonNullableVirtualField(test) do
    _t1 = nil
    tbl = Temper.Orm.TableDef.new(Temper.Orm.Tests.csid("users"), %TemperCore.Vec{t: {Temper.Orm.FieldDef.new(Temper.Orm.Tests.csid("name"), Temper.Orm.StringField.new(), false, nil, false), Temper.Orm.FieldDef.new(Temper.Orm.Tests.csid("computed"), Temper.Orm.StringField.new(), false, nil, true)}}, nil)
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("name", "Alice")}})
    cs = TemperCore.call(Temper.Orm.changeset(tbl, params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name")}}])
    t1 = try do
      t1 = TemperCore.call(cs, :toInsertSql, [])
      t1
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    s = Temper.Orm.SqlFragment.toString(t1)
    t2 = TemperCore.String.index_of(s, "'Alice'") >= 0
    fn_ = fn ->
      "should succeed: " <> s
    end
    TemperCore.Test.assert(test, t2, fn_)
    nil
  end
  def toUpdateSqlSkipsVirtualFields(test) do
    _t1 = nil
    tbl = Temper.Orm.TableDef.new(Temper.Orm.Tests.csid("users"), %TemperCore.Vec{t: {Temper.Orm.FieldDef.new(Temper.Orm.Tests.csid("name"), Temper.Orm.StringField.new(), false, nil, false), Temper.Orm.FieldDef.new(Temper.Orm.Tests.csid("display"), Temper.Orm.StringField.new(), true, nil, true)}}, nil)
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("name", "Bob"), TemperCore.Pair.new("display", "Bobby")}})
    cs = TemperCore.call(Temper.Orm.changeset(tbl, params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name"), Temper.Orm.Tests.csid("display")}}])
    t1 = try do
      t1 = TemperCore.call(cs, :toUpdateSql, [1])
      t1
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    s = Temper.Orm.SqlFragment.toString(t1)
    t2 = TemperCore.String.index_of(s, "name = 'Bob'") >= 0
    fn_1 = fn ->
      "name should be in SET: " <> s
    end
    TemperCore.Test.assert(test, t2, fn_1)
    t3 = TemperCore.String.index_of(s, "display") >= 0
    fn_2 = fn ->
      "virtual field excluded from UPDATE: " <> s
    end
    TemperCore.Test.assert(test, not t3, fn_2)
    nil
  end
  def toUpdateSqlUsesCustomPrimaryKey(test) do
    _t = nil
    tbl = Temper.Orm.TableDef.new(Temper.Orm.Tests.csid("posts"), %TemperCore.Vec{t: {Temper.Orm.FieldDef.new(Temper.Orm.Tests.csid("title"), Temper.Orm.StringField.new(), false, nil, false)}}, Temper.Orm.Tests.csid("post_id"))
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("title", "Updated")}})
    cs = TemperCore.call(Temper.Orm.changeset(tbl, params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("title")}}])
    t = try do
      t = TemperCore.call(cs, :toUpdateSql, [99])
      t
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    s = Temper.Orm.SqlFragment.toString(t)
    fn_ = fn ->
      "got: " <> s
    end
    TemperCore.Test.assert(test, s == "UPDATE posts SET title = 'Updated' WHERE post_id = 99", fn_)
    nil
  end
  def deleteSqlUsesCustomPrimaryKey(test) do
    tbl = Temper.Orm.TableDef.new(Temper.Orm.Tests.csid("posts"), %TemperCore.Vec{t: {Temper.Orm.FieldDef.new(Temper.Orm.Tests.csid("title"), Temper.Orm.StringField.new(), false, nil, false)}}, Temper.Orm.Tests.csid("post_id"))
    s = Temper.Orm.SqlFragment.toString(Temper.Orm.deleteSql(tbl, 42))
    fn_ = fn ->
      "got: " <> s
    end
    TemperCore.Test.assert(test, s == "DELETE FROM posts WHERE post_id = 42", fn_)
    nil
  end
  def deleteSqlUsesDefaultIdWhenPrimaryKeyNull(test) do
    tbl = Temper.Orm.TableDef.new(Temper.Orm.Tests.csid("users"), %TemperCore.Vec{t: {Temper.Orm.FieldDef.new(Temper.Orm.Tests.csid("name"), Temper.Orm.StringField.new(), false, nil, false)}}, nil)
    s = Temper.Orm.SqlFragment.toString(Temper.Orm.deleteSql(tbl, 7))
    fn_ = fn ->
      "got: " <> s
    end
    TemperCore.Test.assert(test, s == "DELETE FROM users WHERE id = 7", fn_)
    nil
  end
  def alreadyInvalidChangesetSkipsSubsequentValidators(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("name", "A"), TemperCore.Pair.new("email", "alice@example.com")}})
    cs = TemperCore.call(TemperCore.call(TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name"), Temper.Orm.Tests.csid("email")}}]), :validateLength, [Temper.Orm.Tests.csid("name"), 3, 50]), :validateRequired, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name"), Temper.Orm.Tests.csid("email")}}]), :validateContains, [Temper.Orm.Tests.csid("email"), "@"])
    fn_1 = fn ->
      "should be invalid from validateLength"
    end
    TemperCore.Test.assert(test, not TemperCore.call(cs, :get_isValid, []), fn_1)
    fn_2 = fn ->
      "should have exactly 1 error, not accumulate: " <> TemperCore.int_to_string(TemperCore.List.length(TemperCore.call(cs, :get_errors, [])))
    end
    TemperCore.Test.assert(test, TemperCore.List.length(TemperCore.call(cs, :get_errors, [])) == 1, fn_2)
    fn_3 = fn ->
      "error should be on name"
    end
    TemperCore.Test.assert(test, Temper.Orm.ChangesetError.get_field(TemperCore.List.get(TemperCore.call(cs, :get_errors, []), 0)) == "name", fn_3)
    nil
  end
  def validateNumberLessThanOrEqualPassesAtBoundary(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("score", "10.0")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("score")}}]), :validateNumber, [Temper.Orm.Tests.csid("score"), Temper.Orm.NumberValidationOpts.new(nil, nil, nil, 10.0, nil)])
    fn_ = fn ->
      "10.0 <= 10.0 should pass"
    end
    TemperCore.Test.assert(test, TemperCore.call(cs, :get_isValid, []), fn_)
    nil
  end
  def validateNumberLessThanOrEqualFailsAboveBoundary(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("score", "10.1")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("score")}}]), :validateNumber, [Temper.Orm.Tests.csid("score"), Temper.Orm.NumberValidationOpts.new(nil, nil, nil, 10.0, nil)])
    fn_1 = fn ->
      "10.1 <= 10.0 should fail"
    end
    TemperCore.Test.assert(test, not TemperCore.call(cs, :get_isValid, []), fn_1)
    fn_2 = fn ->
      "correct message"
    end
    TemperCore.Test.assert(test, Temper.Orm.ChangesetError.get_message(TemperCore.List.get(TemperCore.call(cs, :get_errors, []), 0)) == "must be less than or equal to 10.0", fn_2)
    nil
  end
  def validateNumberEqualToPassesWhenEqual(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("score", "42.0")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("score")}}]), :validateNumber, [Temper.Orm.Tests.csid("score"), Temper.Orm.NumberValidationOpts.new(nil, nil, nil, nil, 42.0)])
    fn_ = fn ->
      "42.0 == 42.0 should pass"
    end
    TemperCore.Test.assert(test, TemperCore.call(cs, :get_isValid, []), fn_)
    nil
  end
  def validateNumberEqualToFailsWhenNotEqual(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("score", "41.9")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("score")}}]), :validateNumber, [Temper.Orm.Tests.csid("score"), Temper.Orm.NumberValidationOpts.new(nil, nil, nil, nil, 42.0)])
    fn_1 = fn ->
      "41.9 == 42.0 should fail"
    end
    TemperCore.Test.assert(test, not TemperCore.call(cs, :get_isValid, []), fn_1)
    fn_2 = fn ->
      "correct message"
    end
    TemperCore.Test.assert(test, Temper.Orm.ChangesetError.get_message(TemperCore.List.get(TemperCore.call(cs, :get_errors, []), 0)) == "must be equal to 42.0", fn_2)
    nil
  end
  def validateNumberGreaterThanFailsAtExactThreshold(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("age", "18")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("age")}}]), :validateNumber, [Temper.Orm.Tests.csid("age"), Temper.Orm.NumberValidationOpts.new(18.0, nil, nil, nil, nil)])
    fn_ = fn ->
      "18 > 18 should fail (strict greater than)"
    end
    TemperCore.Test.assert(test, not TemperCore.call(cs, :get_isValid, []), fn_)
    nil
  end
  def validateNumberLessThanFailsAtExactThreshold(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("score", "10.0")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("score")}}]), :validateNumber, [Temper.Orm.Tests.csid("score"), Temper.Orm.NumberValidationOpts.new(nil, 10.0, nil, nil, nil)])
    fn_ = fn ->
      "10.0 < 10.0 should fail (strict less than)"
    end
    TemperCore.Test.assert(test, not TemperCore.call(cs, :get_isValid, []), fn_)
    nil
  end
  def validateFloatFailsForNonFloatString(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("score", "abc")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("score")}}]), :validateFloat, [Temper.Orm.Tests.csid("score")])
    fn_1 = fn ->
      "abc should not parse as float"
    end
    TemperCore.Test.assert(test, not TemperCore.call(cs, :get_isValid, []), fn_1)
    fn_2 = fn ->
      "correct message"
    end
    TemperCore.Test.assert(test, Temper.Orm.ChangesetError.get_message(TemperCore.List.get(TemperCore.call(cs, :get_errors, []), 0)) == "must be a number", fn_2)
    nil
  end
  def toInsertSqlWithAllSixFieldTypes(test) do
    _t1 = nil
    tbl = Temper.Orm.TableDef.new(Temper.Orm.Tests.csid("records"), %TemperCore.Vec{t: {Temper.Orm.FieldDef.new(Temper.Orm.Tests.csid("name"), Temper.Orm.StringField.new(), false, nil, false), Temper.Orm.FieldDef.new(Temper.Orm.Tests.csid("count"), Temper.Orm.IntField.new(), false, nil, false), Temper.Orm.FieldDef.new(Temper.Orm.Tests.csid("big_id"), Temper.Orm.Int64Field.new(), false, nil, false), Temper.Orm.FieldDef.new(Temper.Orm.Tests.csid("rating"), Temper.Orm.FloatField.new(), false, nil, false), Temper.Orm.FieldDef.new(Temper.Orm.Tests.csid("active"), Temper.Orm.BoolField.new(), false, nil, false), Temper.Orm.FieldDef.new(Temper.Orm.Tests.csid("birthday"), Temper.Orm.DateField.new(), false, nil, false)}}, nil)
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("name", "Alice"), TemperCore.Pair.new("count", "42"), TemperCore.Pair.new("big_id", "9999999999"), TemperCore.Pair.new("rating", "3.14"), TemperCore.Pair.new("active", "true"), TemperCore.Pair.new("birthday", "2000-01-15")}})
    cs = TemperCore.call(Temper.Orm.changeset(tbl, params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name"), Temper.Orm.Tests.csid("count"), Temper.Orm.Tests.csid("big_id"), Temper.Orm.Tests.csid("rating"), Temper.Orm.Tests.csid("active"), Temper.Orm.Tests.csid("birthday")}}])
    t1 = try do
      t1 = TemperCore.call(cs, :toInsertSql, [])
      t1
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    s = Temper.Orm.SqlFragment.toString(t1)
    t2 = TemperCore.String.index_of(s, "'Alice'") >= 0
    fn_1 = fn ->
      "string field: " <> s
    end
    TemperCore.Test.assert(test, t2, fn_1)
    t3 = TemperCore.String.index_of(s, "42") >= 0
    fn_2 = fn ->
      "int field: " <> s
    end
    TemperCore.Test.assert(test, t3, fn_2)
    t4 = TemperCore.String.index_of(s, "9999999999") >= 0
    fn_3 = fn ->
      "int64 field: " <> s
    end
    TemperCore.Test.assert(test, t4, fn_3)
    t5 = TemperCore.String.index_of(s, "3.14") >= 0
    fn_4 = fn ->
      "float field: " <> s
    end
    TemperCore.Test.assert(test, t5, fn_4)
    t6 = TemperCore.String.index_of(s, "TRUE") >= 0
    fn_5 = fn ->
      "bool field: " <> s
    end
    TemperCore.Test.assert(test, t6, fn_5)
    t7 = TemperCore.String.index_of(s, "'2000-01-15'") >= 0
    fn_6 = fn ->
      "date field: " <> s
    end
    TemperCore.Test.assert(test, t7, fn_6)
    nil
  end
  def deleteChangeOnNonNullableFieldCausesToInsertSqlToBubble(test) do
    tbl = Temper.Orm.TableDef.new(Temper.Orm.Tests.csid("users"), %TemperCore.Vec{t: {Temper.Orm.FieldDef.new(Temper.Orm.Tests.csid("name"), Temper.Orm.StringField.new(), false, nil, false), Temper.Orm.FieldDef.new(Temper.Orm.Tests.csid("email"), Temper.Orm.StringField.new(), false, nil, false)}}, nil)
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("name", "Alice"), TemperCore.Pair.new("email", "a@b.com")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(tbl, params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name"), Temper.Orm.Tests.csid("email")}}]), :deleteChange, [Temper.Orm.Tests.csid("email")])
    _didBubble = nil
    didBubble = try do
      TemperCore.call(cs, :toInsertSql, [])
      didBubble = false
      didBubble
    rescue
      _ in TemperCore.Bubble ->
        didBubble = true
        didBubble
    end
    fn_ = fn ->
      "removing non-nullable field should make toInsertSql bubble"
    end
    TemperCore.Test.assert(test, didBubble, fn_)
    nil
  end
  def validateLengthPassesAtExactMin(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("name", "abc")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name")}}]), :validateLength, [Temper.Orm.Tests.csid("name"), 3, 10])
    fn_ = fn ->
      "length 3 should pass for min 3"
    end
    TemperCore.Test.assert(test, TemperCore.call(cs, :get_isValid, []), fn_)
    nil
  end
  def validateLengthPassesAtExactMax(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("name", "abcdefghij")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name")}}]), :validateLength, [Temper.Orm.Tests.csid("name"), 1, 10])
    fn_ = fn ->
      "length 10 should pass for max 10"
    end
    TemperCore.Test.assert(test, TemperCore.call(cs, :get_isValid, []), fn_)
    nil
  end
  def validateAcceptanceSkipsWhenFieldNotInChanges(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("active")}}]), :validateAcceptance, [Temper.Orm.Tests.csid("active")])
    fn_ = fn ->
      "should be valid when field absent"
    end
    TemperCore.Test.assert(test, TemperCore.call(cs, :get_isValid, []), fn_)
    nil
  end
  def multipleValidatorsChainCorrectlyOnValidChangeset(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("name", "Alice"), TemperCore.Pair.new("email", "alice@example.com"), TemperCore.Pair.new("age", "25")}})
    cs = TemperCore.call(TemperCore.call(TemperCore.call(TemperCore.call(TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name"), Temper.Orm.Tests.csid("email"), Temper.Orm.Tests.csid("age")}}]), :validateRequired, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name"), Temper.Orm.Tests.csid("email")}}]), :validateLength, [Temper.Orm.Tests.csid("name"), 2, 50]), :validateContains, [Temper.Orm.Tests.csid("email"), "@"]), :validateInt, [Temper.Orm.Tests.csid("age")]), :validateNumber, [Temper.Orm.Tests.csid("age"), Temper.Orm.NumberValidationOpts.new(0.0, 150.0, nil, nil, nil)])
    fn_1 = fn ->
      "all validators should pass"
    end
    TemperCore.Test.assert(test, TemperCore.call(cs, :get_isValid, []), fn_1)
    fn_2 = fn ->
      "no errors expected"
    end
    TemperCore.Test.assert(test, TemperCore.List.length(TemperCore.call(cs, :get_errors, [])) == 0, fn_2)
    nil
  end
  def toUpdateSqlWithMultipleNonVirtualFields(test) do
    _t1 = nil
    tbl = Temper.Orm.TableDef.new(Temper.Orm.Tests.csid("users"), %TemperCore.Vec{t: {Temper.Orm.FieldDef.new(Temper.Orm.Tests.csid("name"), Temper.Orm.StringField.new(), false, nil, false), Temper.Orm.FieldDef.new(Temper.Orm.Tests.csid("email"), Temper.Orm.StringField.new(), false, nil, false)}}, nil)
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("name", "Bob"), TemperCore.Pair.new("email", "bob@example.com")}})
    cs = TemperCore.call(Temper.Orm.changeset(tbl, params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name"), Temper.Orm.Tests.csid("email")}}])
    t1 = try do
      t1 = TemperCore.call(cs, :toUpdateSql, [5])
      t1
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    s = Temper.Orm.SqlFragment.toString(t1)
    t2 = TemperCore.String.index_of(s, "name = 'Bob'") >= 0
    fn_1 = fn ->
      "name in SET: " <> s
    end
    TemperCore.Test.assert(test, t2, fn_1)
    t3 = TemperCore.String.index_of(s, "email = 'bob@example.com'") >= 0
    fn_2 = fn ->
      "email in SET: " <> s
    end
    TemperCore.Test.assert(test, t3, fn_2)
    t4 = TemperCore.String.index_of(s, "WHERE id = 5") >= 0
    fn_3 = fn ->
      "WHERE clause: " <> s
    end
    TemperCore.Test.assert(test, t4, fn_3)
    nil
  end
  def toUpdateSqlBubblesWhenAllChangesAreVirtualFields(test) do
    tbl = Temper.Orm.TableDef.new(Temper.Orm.Tests.csid("users"), %TemperCore.Vec{t: {Temper.Orm.FieldDef.new(Temper.Orm.Tests.csid("name"), Temper.Orm.StringField.new(), false, nil, false), Temper.Orm.FieldDef.new(Temper.Orm.Tests.csid("computed"), Temper.Orm.StringField.new(), true, nil, true)}}, nil)
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("name", "Alice"), TemperCore.Pair.new("computed", "derived")}})
    cs = TemperCore.call(Temper.Orm.changeset(tbl, params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("computed")}}])
    _didBubble = nil
    didBubble = try do
      TemperCore.call(cs, :toUpdateSql, [1])
      didBubble = false
      didBubble
    rescue
      _ in TemperCore.Bubble ->
        didBubble = true
        didBubble
    end
    fn_ = fn ->
      "should bubble when all changes are virtual"
    end
    TemperCore.Test.assert(test, didBubble, fn_)
    nil
  end
  def putChangeSatisfiesSubsequentValidateRequired(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {}})
    cs = TemperCore.call(TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name")}}]), :putChange, [Temper.Orm.Tests.csid("name"), "Injected"]), :validateRequired, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name")}}])
    fn_ = fn ->
      "putChange should satisfy required"
    end
    TemperCore.Test.assert(test, TemperCore.call(cs, :get_isValid, []), fn_)
    nil
  end
  def validateStartsWithSkipsWhenFieldNotInChanges(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name")}}]), :validateStartsWith, [Temper.Orm.Tests.csid("name"), "Dr."])
    fn_ = fn ->
      "should be valid when field absent"
    end
    TemperCore.Test.assert(test, TemperCore.call(cs, :get_isValid, []), fn_)
    nil
  end
  def validateEndsWithSkipsWhenFieldNotInChanges(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name")}}]), :validateEndsWith, [Temper.Orm.Tests.csid("name"), ".com"])
    fn_ = fn ->
      "should be valid when field absent"
    end
    TemperCore.Test.assert(test, TemperCore.call(cs, :get_isValid, []), fn_)
    nil
  end
  def validateIntAcceptsZero(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("age", "0")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("age")}}]), :validateInt, [Temper.Orm.Tests.csid("age")])
    fn_ = fn ->
      "0 should be a valid int"
    end
    TemperCore.Test.assert(test, TemperCore.call(cs, :get_isValid, []), fn_)
    nil
  end
  def validateIntAcceptsNegative(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("age", "-5")}})
    cs = TemperCore.call(TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("age")}}]), :validateInt, [Temper.Orm.Tests.csid("age")])
    fn_ = fn ->
      "-5 should be a valid int"
    end
    TemperCore.Test.assert(test, TemperCore.call(cs, :get_isValid, []), fn_)
    nil
  end
  def changesetImmutabilityValidatorsDoNotMutateBase(test) do
    params = TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("name", "A"), TemperCore.Pair.new("email", "alice@example.com")}})
    base = TemperCore.call(Temper.Orm.changeset(Temper.Orm.Tests.userTable(), params), :cast, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name"), Temper.Orm.Tests.csid("email")}}])
    failed = TemperCore.call(base, :validateLength, [Temper.Orm.Tests.csid("name"), 3, 50])
    passed = TemperCore.call(base, :validateRequired, [%TemperCore.Vec{t: {Temper.Orm.Tests.csid("name"), Temper.Orm.Tests.csid("email")}}])
    fn_1 = fn ->
      "failed branch should be invalid"
    end
    TemperCore.Test.assert(test, not TemperCore.call(failed, :get_isValid, []), fn_1)
    fn_2 = fn ->
      "passed branch should still be valid"
    end
    TemperCore.Test.assert(test, TemperCore.call(passed, :get_isValid, []), fn_2)
    nil
  end
  def sid(name) do
    try do
      try do
        throw({:temper_return, :ex_return_0, Temper.Orm.safeIdentifier(name)})
      rescue
        _ in TemperCore.Bubble ->
          throw({:temper_return, :ex_return_0, raise(TemperCore.Panic)})
      end
      nil
    catch
      {:temper_return, :ex_return_0, ex_value_1} ->
        ex_value_1
    end
  end
  def bareFromProducesSelect(test) do
    q = Temper.Orm.from(Temper.Orm.Tests.sid("users"))
    fn_ = fn ->
      "bare query"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT * FROM users", fn_)
    nil
  end
  def selectRestrictsColumns(test) do
    q = Temper.Orm.Query.select(Temper.Orm.from(Temper.Orm.Tests.sid("users")), %TemperCore.Vec{t: {Temper.Orm.Tests.sid("id"), Temper.Orm.Tests.sid("name")}})
    fn_ = fn ->
      "select columns"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT id, name FROM users", fn_)
    nil
  end
  def whereAddsConditionWithIntValue(test) do
    t = Temper.Orm.from(Temper.Orm.Tests.sid("users"))
    accumulator = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator, "age > ")
    Temper.Orm.SqlBuilder.appendInt32(accumulator, 18)
    q = Temper.Orm.Query.where(t, Temper.Orm.SqlBuilder.get_accumulated(accumulator))
    fn_ = fn ->
      "where int"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT * FROM users WHERE age > 18", fn_)
    nil
  end
  def whereAddsConditionWithBoolValue(test) do
    t = Temper.Orm.from(Temper.Orm.Tests.sid("users"))
    accumulator = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator, "active = ")
    Temper.Orm.SqlBuilder.appendBoolean(accumulator, true)
    q = Temper.Orm.Query.where(t, Temper.Orm.SqlBuilder.get_accumulated(accumulator))
    fn_ = fn ->
      "where bool"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT * FROM users WHERE active = TRUE", fn_)
    nil
  end
  def chainedWhereUsesAnd(test) do
    t1 = Temper.Orm.from(Temper.Orm.Tests.sid("users"))
    accumulator1 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator1, "age > ")
    Temper.Orm.SqlBuilder.appendInt32(accumulator1, 18)
    t2 = Temper.Orm.Query.where(t1, Temper.Orm.SqlBuilder.get_accumulated(accumulator1))
    accumulator2 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator2, "active = ")
    Temper.Orm.SqlBuilder.appendBoolean(accumulator2, true)
    q = Temper.Orm.Query.where(t2, Temper.Orm.SqlBuilder.get_accumulated(accumulator2))
    fn_ = fn ->
      "chained where"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT * FROM users WHERE age > 18 AND active = TRUE", fn_)
    nil
  end
  def orderByAsc(test) do
    q = Temper.Orm.Query.orderBy(Temper.Orm.from(Temper.Orm.Tests.sid("users")), Temper.Orm.Tests.sid("name"), true)
    fn_ = fn ->
      "order asc"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT * FROM users ORDER BY name ASC", fn_)
    nil
  end
  def orderByDesc(test) do
    q = Temper.Orm.Query.orderBy(Temper.Orm.from(Temper.Orm.Tests.sid("users")), Temper.Orm.Tests.sid("created_at"), false)
    fn_ = fn ->
      "order desc"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT * FROM users ORDER BY created_at DESC", fn_)
    nil
  end
  def limitAndOffset(test) do
    _q = nil
    q = try do
      t = Temper.Orm.Query.limit(Temper.Orm.from(Temper.Orm.Tests.sid("users")), 10)
      q = Temper.Orm.Query.offset(t, 20)
      q
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    fn_ = fn ->
      "limit/offset"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT * FROM users LIMIT 10 OFFSET 20", fn_)
    nil
  end
  def limitBubblesOnNegative(test) do
    _didBubble = nil
    didBubble = try do
      Temper.Orm.Query.limit(Temper.Orm.from(Temper.Orm.Tests.sid("users")), -1)
      didBubble = false
      didBubble
    rescue
      _ in TemperCore.Bubble ->
        didBubble = true
        didBubble
    end
    fn_ = fn ->
      "negative limit should bubble"
    end
    TemperCore.Test.assert(test, didBubble, fn_)
    nil
  end
  def offsetBubblesOnNegative(test) do
    _didBubble = nil
    didBubble = try do
      Temper.Orm.Query.offset(Temper.Orm.from(Temper.Orm.Tests.sid("users")), -1)
      didBubble = false
      didBubble
    rescue
      _ in TemperCore.Bubble ->
        didBubble = true
        didBubble
    end
    fn_ = fn ->
      "negative offset should bubble"
    end
    TemperCore.Test.assert(test, didBubble, fn_)
    nil
  end
  def complexComposedQuery(test) do
    _minAge = 21
    _q = nil
    q = try do
      t1 = Temper.Orm.Query.select(Temper.Orm.from(Temper.Orm.Tests.sid("users")), %TemperCore.Vec{t: {Temper.Orm.Tests.sid("id"), Temper.Orm.Tests.sid("name"), Temper.Orm.Tests.sid("email")}})
      accumulator1 = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(accumulator1, "age >= ")
      Temper.Orm.SqlBuilder.appendInt32(accumulator1, 21)
      t2 = Temper.Orm.Query.where(t1, Temper.Orm.SqlBuilder.get_accumulated(accumulator1))
      accumulator2 = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(accumulator2, "active = ")
      Temper.Orm.SqlBuilder.appendBoolean(accumulator2, true)
      t3 = Temper.Orm.Query.limit(Temper.Orm.Query.orderBy(Temper.Orm.Query.where(t2, Temper.Orm.SqlBuilder.get_accumulated(accumulator2)), Temper.Orm.Tests.sid("name"), true), 25)
      q = Temper.Orm.Query.offset(t3, 0)
      q
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    fn_ = fn ->
      "complex query"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT id, name, email FROM users WHERE age >= 21 AND active = TRUE ORDER BY name ASC LIMIT 25 OFFSET 0", fn_)
    nil
  end
  def safeToSqlAppliesDefaultLimitWhenNoneSet(test) do
    _t = nil
    q = Temper.Orm.from(Temper.Orm.Tests.sid("users"))
    t = try do
      t = Temper.Orm.Query.safeToSql(q, 100)
      t
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    s = Temper.Orm.SqlFragment.toString(t)
    fn_ = fn ->
      "should have limit: " <> s
    end
    TemperCore.Test.assert(test, s == "SELECT * FROM users LIMIT 100", fn_)
    nil
  end
  def safeToSqlRespectsExplicitLimit(test) do
    _t = nil
    _q = nil
    q = try do
      q = Temper.Orm.Query.limit(Temper.Orm.from(Temper.Orm.Tests.sid("users")), 5)
      q
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    t = try do
      t = Temper.Orm.Query.safeToSql(q, 100)
      t
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    s = Temper.Orm.SqlFragment.toString(t)
    fn_ = fn ->
      "explicit limit preserved: " <> s
    end
    TemperCore.Test.assert(test, s == "SELECT * FROM users LIMIT 5", fn_)
    nil
  end
  def safeToSqlBubblesOnNegativeDefaultLimit(test) do
    _didBubble = nil
    didBubble = try do
      Temper.Orm.Query.safeToSql(Temper.Orm.from(Temper.Orm.Tests.sid("users")), -1)
      didBubble = false
      didBubble
    rescue
      _ in TemperCore.Bubble ->
        didBubble = true
        didBubble
    end
    fn_ = fn ->
      "negative defaultLimit should bubble"
    end
    TemperCore.Test.assert(test, didBubble, fn_)
    nil
  end
  def whereWithInjectionAttemptInStringValueIsEscaped(test) do
    _evil = "'; DROP TABLE users; --"
    t1 = Temper.Orm.from(Temper.Orm.Tests.sid("users"))
    accumulator = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator, "name = ")
    Temper.Orm.SqlBuilder.appendString(accumulator, "'; DROP TABLE users; --")
    q = Temper.Orm.Query.where(t1, Temper.Orm.SqlBuilder.get_accumulated(accumulator))
    s = Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q))
    t2 = TemperCore.String.index_of(s, "''") >= 0
    fn_1 = fn ->
      "quotes must be doubled: " <> s
    end
    TemperCore.Test.assert(test, t2, fn_1)
    t3 = TemperCore.String.index_of(s, "SELECT * FROM users WHERE name =") >= 0
    fn_2 = fn ->
      "structure intact: " <> s
    end
    TemperCore.Test.assert(test, t3, fn_2)
    nil
  end
  def safeIdentifierRejectsUserSuppliedTableNameWithMetacharacters(test) do
    _attack = "users; DROP TABLE users; --"
    _didBubble = nil
    didBubble = try do
      Temper.Orm.safeIdentifier("users; DROP TABLE users; --")
      didBubble = false
      didBubble
    rescue
      _ in TemperCore.Bubble ->
        didBubble = true
        didBubble
    end
    fn_ = fn ->
      "metacharacter-containing name must be rejected at construction"
    end
    TemperCore.Test.assert(test, didBubble, fn_)
    nil
  end
  def innerJoinProducesInnerJoin(test) do
    t1 = Temper.Orm.from(Temper.Orm.Tests.sid("users"))
    t2 = Temper.Orm.Tests.sid("orders")
    accumulator = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator, "users.id = orders.user_id")
    q = Temper.Orm.Query.innerJoin(t1, t2, Temper.Orm.SqlBuilder.get_accumulated(accumulator))
    fn_ = fn ->
      "inner join"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT * FROM users INNER JOIN orders ON users.id = orders.user_id", fn_)
    nil
  end
  def leftJoinProducesLeftJoin(test) do
    t1 = Temper.Orm.from(Temper.Orm.Tests.sid("users"))
    t2 = Temper.Orm.Tests.sid("profiles")
    accumulator = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator, "users.id = profiles.user_id")
    q = Temper.Orm.Query.leftJoin(t1, t2, Temper.Orm.SqlBuilder.get_accumulated(accumulator))
    fn_ = fn ->
      "left join"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT * FROM users LEFT JOIN profiles ON users.id = profiles.user_id", fn_)
    nil
  end
  def rightJoinProducesRightJoin(test) do
    t1 = Temper.Orm.from(Temper.Orm.Tests.sid("orders"))
    t2 = Temper.Orm.Tests.sid("users")
    accumulator = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator, "orders.user_id = users.id")
    q = Temper.Orm.Query.rightJoin(t1, t2, Temper.Orm.SqlBuilder.get_accumulated(accumulator))
    fn_ = fn ->
      "right join"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT * FROM orders RIGHT JOIN users ON orders.user_id = users.id", fn_)
    nil
  end
  def fullJoinProducesFullOuterJoin(test) do
    t1 = Temper.Orm.from(Temper.Orm.Tests.sid("users"))
    t2 = Temper.Orm.Tests.sid("orders")
    accumulator = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator, "users.id = orders.user_id")
    q = Temper.Orm.Query.fullJoin(t1, t2, Temper.Orm.SqlBuilder.get_accumulated(accumulator))
    fn_ = fn ->
      "full join"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT * FROM users FULL OUTER JOIN orders ON users.id = orders.user_id", fn_)
    nil
  end
  def chainedJoins(test) do
    t1 = Temper.Orm.from(Temper.Orm.Tests.sid("users"))
    t2 = Temper.Orm.Tests.sid("orders")
    accumulator1 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator1, "users.id = orders.user_id")
    t3 = Temper.Orm.Query.innerJoin(t1, t2, Temper.Orm.SqlBuilder.get_accumulated(accumulator1))
    t4 = Temper.Orm.Tests.sid("profiles")
    accumulator2 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator2, "users.id = profiles.user_id")
    q = Temper.Orm.Query.leftJoin(t3, t4, Temper.Orm.SqlBuilder.get_accumulated(accumulator2))
    fn_ = fn ->
      "chained joins"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT * FROM users INNER JOIN orders ON users.id = orders.user_id LEFT JOIN profiles ON users.id = profiles.user_id", fn_)
    nil
  end
  def joinWithWhereAndOrderBy(test) do
    _q = nil
    q = try do
      t1 = Temper.Orm.from(Temper.Orm.Tests.sid("users"))
      t2 = Temper.Orm.Tests.sid("orders")
      accumulator1 = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(accumulator1, "users.id = orders.user_id")
      t3 = Temper.Orm.Query.innerJoin(t1, t2, Temper.Orm.SqlBuilder.get_accumulated(accumulator1))
      accumulator2 = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(accumulator2, "orders.total > ")
      Temper.Orm.SqlBuilder.appendInt32(accumulator2, 100)
      q = Temper.Orm.Query.limit(Temper.Orm.Query.orderBy(Temper.Orm.Query.where(t3, Temper.Orm.SqlBuilder.get_accumulated(accumulator2)), Temper.Orm.Tests.sid("name"), true), 10)
      q
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    fn_ = fn ->
      "join with where/order/limit"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT * FROM users INNER JOIN orders ON users.id = orders.user_id WHERE orders.total > 100 ORDER BY name ASC LIMIT 10", fn_)
    nil
  end
  def colHelperProducesQualifiedReference(test) do
    c = Temper.Orm.col(Temper.Orm.Tests.sid("users"), Temper.Orm.Tests.sid("id"))
    fn_ = fn ->
      "col helper"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(c) == "users.id", fn_)
    nil
  end
  def joinWithColHelper(test) do
    onCond = Temper.Orm.col(Temper.Orm.Tests.sid("users"), Temper.Orm.Tests.sid("id"))
    b = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendFragment(b, onCond)
    Temper.Orm.SqlBuilder.appendSafe(b, " = ")
    Temper.Orm.SqlBuilder.appendFragment(b, Temper.Orm.col(Temper.Orm.Tests.sid("orders"), Temper.Orm.Tests.sid("user_id")))
    q = Temper.Orm.Query.innerJoin(Temper.Orm.from(Temper.Orm.Tests.sid("users")), Temper.Orm.Tests.sid("orders"), Temper.Orm.SqlBuilder.get_accumulated(b))
    fn_ = fn ->
      "join with col"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT * FROM users INNER JOIN orders ON users.id = orders.user_id", fn_)
    nil
  end
  def orWhereBasic(test) do
    t = Temper.Orm.from(Temper.Orm.Tests.sid("users"))
    accumulator = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator, "status = ")
    Temper.Orm.SqlBuilder.appendString(accumulator, "active")
    q = Temper.Orm.Query.orWhere(t, Temper.Orm.SqlBuilder.get_accumulated(accumulator))
    fn_ = fn ->
      "orWhere basic"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT * FROM users WHERE status = 'active'", fn_)
    nil
  end
  def whereThenOrWhere(test) do
    t1 = Temper.Orm.from(Temper.Orm.Tests.sid("users"))
    accumulator1 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator1, "age > ")
    Temper.Orm.SqlBuilder.appendInt32(accumulator1, 18)
    t2 = Temper.Orm.Query.where(t1, Temper.Orm.SqlBuilder.get_accumulated(accumulator1))
    accumulator2 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator2, "vip = ")
    Temper.Orm.SqlBuilder.appendBoolean(accumulator2, true)
    q = Temper.Orm.Query.orWhere(t2, Temper.Orm.SqlBuilder.get_accumulated(accumulator2))
    fn_ = fn ->
      "where then orWhere"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT * FROM users WHERE age > 18 OR vip = TRUE", fn_)
    nil
  end
  def multipleOrWhere(test) do
    t1 = Temper.Orm.from(Temper.Orm.Tests.sid("users"))
    accumulator1 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator1, "active = ")
    Temper.Orm.SqlBuilder.appendBoolean(accumulator1, true)
    t2 = Temper.Orm.Query.where(t1, Temper.Orm.SqlBuilder.get_accumulated(accumulator1))
    accumulator2 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator2, "role = ")
    Temper.Orm.SqlBuilder.appendString(accumulator2, "admin")
    t3 = Temper.Orm.Query.orWhere(t2, Temper.Orm.SqlBuilder.get_accumulated(accumulator2))
    accumulator3 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator3, "role = ")
    Temper.Orm.SqlBuilder.appendString(accumulator3, "moderator")
    q = Temper.Orm.Query.orWhere(t3, Temper.Orm.SqlBuilder.get_accumulated(accumulator3))
    fn_ = fn ->
      "multiple orWhere"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT * FROM users WHERE active = TRUE OR role = 'admin' OR role = 'moderator'", fn_)
    nil
  end
  def mixedWhereAndOrWhere(test) do
    t1 = Temper.Orm.from(Temper.Orm.Tests.sid("users"))
    accumulator1 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator1, "age > ")
    Temper.Orm.SqlBuilder.appendInt32(accumulator1, 18)
    t2 = Temper.Orm.Query.where(t1, Temper.Orm.SqlBuilder.get_accumulated(accumulator1))
    accumulator2 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator2, "active = ")
    Temper.Orm.SqlBuilder.appendBoolean(accumulator2, true)
    t3 = Temper.Orm.Query.where(t2, Temper.Orm.SqlBuilder.get_accumulated(accumulator2))
    accumulator3 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator3, "vip = ")
    Temper.Orm.SqlBuilder.appendBoolean(accumulator3, true)
    q = Temper.Orm.Query.orWhere(t3, Temper.Orm.SqlBuilder.get_accumulated(accumulator3))
    fn_ = fn ->
      "mixed where and orWhere"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT * FROM users WHERE age > 18 AND active = TRUE OR vip = TRUE", fn_)
    nil
  end
  def whereNull(test) do
    q = Temper.Orm.Query.whereNull(Temper.Orm.from(Temper.Orm.Tests.sid("users")), Temper.Orm.Tests.sid("deleted_at"))
    fn_ = fn ->
      "whereNull"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT * FROM users WHERE deleted_at IS NULL", fn_)
    nil
  end
  def whereNotNull(test) do
    q = Temper.Orm.Query.whereNotNull(Temper.Orm.from(Temper.Orm.Tests.sid("users")), Temper.Orm.Tests.sid("email"))
    fn_ = fn ->
      "whereNotNull"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT * FROM users WHERE email IS NOT NULL", fn_)
    nil
  end
  def whereNullChainedWithWhere(test) do
    t = Temper.Orm.from(Temper.Orm.Tests.sid("users"))
    accumulator = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator, "active = ")
    Temper.Orm.SqlBuilder.appendBoolean(accumulator, true)
    q = Temper.Orm.Query.whereNull(Temper.Orm.Query.where(t, Temper.Orm.SqlBuilder.get_accumulated(accumulator)), Temper.Orm.Tests.sid("deleted_at"))
    fn_ = fn ->
      "whereNull chained"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT * FROM users WHERE active = TRUE AND deleted_at IS NULL", fn_)
    nil
  end
  def whereNotNullChainedWithOrWhere(test) do
    t = Temper.Orm.Query.whereNull(Temper.Orm.from(Temper.Orm.Tests.sid("users")), Temper.Orm.Tests.sid("deleted_at"))
    accumulator = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator, "role = ")
    Temper.Orm.SqlBuilder.appendString(accumulator, "admin")
    q = Temper.Orm.Query.orWhere(t, Temper.Orm.SqlBuilder.get_accumulated(accumulator))
    fn_ = fn ->
      "whereNotNull with orWhere"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT * FROM users WHERE deleted_at IS NULL OR role = 'admin'", fn_)
    nil
  end
  def whereInWithIntValues(test) do
    q = Temper.Orm.Query.whereIn(Temper.Orm.from(Temper.Orm.Tests.sid("users")), Temper.Orm.Tests.sid("id"), %TemperCore.Vec{t: {Temper.Orm.SqlInt32.new(1), Temper.Orm.SqlInt32.new(2), Temper.Orm.SqlInt32.new(3)}})
    fn_ = fn ->
      "whereIn ints"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT * FROM users WHERE id IN (1, 2, 3)", fn_)
    nil
  end
  def whereInWithStringValuesEscaping(test) do
    q = Temper.Orm.Query.whereIn(Temper.Orm.from(Temper.Orm.Tests.sid("users")), Temper.Orm.Tests.sid("name"), %TemperCore.Vec{t: {Temper.Orm.SqlString.new("Alice"), Temper.Orm.SqlString.new("Bob's")}})
    fn_ = fn ->
      "whereIn strings"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT * FROM users WHERE name IN ('Alice', 'Bob''s')", fn_)
    nil
  end
  def whereInWithEmptyListProduces1_0(test) do
    q = Temper.Orm.Query.whereIn(Temper.Orm.from(Temper.Orm.Tests.sid("users")), Temper.Orm.Tests.sid("id"), %TemperCore.Vec{t: {}})
    fn_ = fn ->
      "whereIn empty"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT * FROM users WHERE 1 = 0", fn_)
    nil
  end
  def whereInChained(test) do
    t = Temper.Orm.from(Temper.Orm.Tests.sid("users"))
    accumulator = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator, "active = ")
    Temper.Orm.SqlBuilder.appendBoolean(accumulator, true)
    q = Temper.Orm.Query.whereIn(Temper.Orm.Query.where(t, Temper.Orm.SqlBuilder.get_accumulated(accumulator)), Temper.Orm.Tests.sid("role"), %TemperCore.Vec{t: {Temper.Orm.SqlString.new("admin"), Temper.Orm.SqlString.new("user")}})
    fn_ = fn ->
      "whereIn chained"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT * FROM users WHERE active = TRUE AND role IN ('admin', 'user')", fn_)
    nil
  end
  def whereInSingleElement(test) do
    q = Temper.Orm.Query.whereIn(Temper.Orm.from(Temper.Orm.Tests.sid("users")), Temper.Orm.Tests.sid("id"), %TemperCore.Vec{t: {Temper.Orm.SqlInt32.new(42)}})
    fn_ = fn ->
      "whereIn single"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT * FROM users WHERE id IN (42)", fn_)
    nil
  end
  def whereNotBasic(test) do
    t = Temper.Orm.from(Temper.Orm.Tests.sid("users"))
    accumulator = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator, "active = ")
    Temper.Orm.SqlBuilder.appendBoolean(accumulator, true)
    q = Temper.Orm.Query.whereNot(t, Temper.Orm.SqlBuilder.get_accumulated(accumulator))
    fn_ = fn ->
      "whereNot"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT * FROM users WHERE NOT (active = TRUE)", fn_)
    nil
  end
  def whereNotChained(test) do
    t1 = Temper.Orm.from(Temper.Orm.Tests.sid("users"))
    accumulator1 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator1, "age > ")
    Temper.Orm.SqlBuilder.appendInt32(accumulator1, 18)
    t2 = Temper.Orm.Query.where(t1, Temper.Orm.SqlBuilder.get_accumulated(accumulator1))
    accumulator2 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator2, "banned = ")
    Temper.Orm.SqlBuilder.appendBoolean(accumulator2, true)
    q = Temper.Orm.Query.whereNot(t2, Temper.Orm.SqlBuilder.get_accumulated(accumulator2))
    fn_ = fn ->
      "whereNot chained"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT * FROM users WHERE age > 18 AND NOT (banned = TRUE)", fn_)
    nil
  end
  def whereBetweenIntegers(test) do
    q = Temper.Orm.Query.whereBetween(Temper.Orm.from(Temper.Orm.Tests.sid("users")), Temper.Orm.Tests.sid("age"), Temper.Orm.SqlInt32.new(18), Temper.Orm.SqlInt32.new(65))
    fn_ = fn ->
      "whereBetween ints"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT * FROM users WHERE age BETWEEN 18 AND 65", fn_)
    nil
  end
  def whereBetweenChained(test) do
    t = Temper.Orm.from(Temper.Orm.Tests.sid("users"))
    accumulator = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator, "active = ")
    Temper.Orm.SqlBuilder.appendBoolean(accumulator, true)
    q = Temper.Orm.Query.whereBetween(Temper.Orm.Query.where(t, Temper.Orm.SqlBuilder.get_accumulated(accumulator)), Temper.Orm.Tests.sid("age"), Temper.Orm.SqlInt32.new(21), Temper.Orm.SqlInt32.new(30))
    fn_ = fn ->
      "whereBetween chained"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT * FROM users WHERE active = TRUE AND age BETWEEN 21 AND 30", fn_)
    nil
  end
  def whereLikeBasic(test) do
    q = Temper.Orm.Query.whereLike(Temper.Orm.from(Temper.Orm.Tests.sid("users")), Temper.Orm.Tests.sid("name"), "John%")
    fn_ = fn ->
      "whereLike"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT * FROM users WHERE name LIKE 'John%'", fn_)
    nil
  end
  def whereIlikeBasic(test) do
    q = Temper.Orm.Query.whereILike(Temper.Orm.from(Temper.Orm.Tests.sid("users")), Temper.Orm.Tests.sid("email"), "%@gmail.com")
    fn_ = fn ->
      "whereILike"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT * FROM users WHERE email ILIKE '%@gmail.com'", fn_)
    nil
  end
  def whereLikeWithInjectionAttempt(test) do
    q = Temper.Orm.Query.whereLike(Temper.Orm.from(Temper.Orm.Tests.sid("users")), Temper.Orm.Tests.sid("name"), "'; DROP TABLE users; --")
    s = Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q))
    t1 = TemperCore.String.index_of(s, "''") >= 0
    fn_1 = fn ->
      "like injection escaped: " <> s
    end
    TemperCore.Test.assert(test, t1, fn_1)
    t2 = TemperCore.String.index_of(s, "LIKE") >= 0
    fn_2 = fn ->
      "like structure intact: " <> s
    end
    TemperCore.Test.assert(test, t2, fn_2)
    nil
  end
  def whereLikeWildcardPatterns(test) do
    q = Temper.Orm.Query.whereLike(Temper.Orm.from(Temper.Orm.Tests.sid("users")), Temper.Orm.Tests.sid("name"), "%son%")
    fn_ = fn ->
      "whereLike wildcard"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT * FROM users WHERE name LIKE '%son%'", fn_)
    nil
  end
  def countAllProducesCount(test) do
    f = Temper.Orm.countAll()
    fn_ = fn ->
      "countAll"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(f) == "COUNT(*)", fn_)
    nil
  end
  def countColProducesCountField(test) do
    f = Temper.Orm.countCol(Temper.Orm.Tests.sid("id"))
    fn_ = fn ->
      "countCol"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(f) == "COUNT(id)", fn_)
    nil
  end
  def sumColProducesSumField(test) do
    f = Temper.Orm.sumCol(Temper.Orm.Tests.sid("amount"))
    fn_ = fn ->
      "sumCol"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(f) == "SUM(amount)", fn_)
    nil
  end
  def avgColProducesAvgField(test) do
    f = Temper.Orm.avgCol(Temper.Orm.Tests.sid("price"))
    fn_ = fn ->
      "avgCol"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(f) == "AVG(price)", fn_)
    nil
  end
  def minColProducesMinField(test) do
    f = Temper.Orm.minCol(Temper.Orm.Tests.sid("created_at"))
    fn_ = fn ->
      "minCol"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(f) == "MIN(created_at)", fn_)
    nil
  end
  def maxColProducesMaxField(test) do
    f = Temper.Orm.maxCol(Temper.Orm.Tests.sid("score"))
    fn_ = fn ->
      "maxCol"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(f) == "MAX(score)", fn_)
    nil
  end
  def selectExprWithAggregate(test) do
    q = Temper.Orm.Query.selectExpr(Temper.Orm.from(Temper.Orm.Tests.sid("orders")), %TemperCore.Vec{t: {Temper.Orm.countAll()}})
    fn_ = fn ->
      "selectExpr count"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT COUNT(*) FROM orders", fn_)
    nil
  end
  def selectExprWithMultipleExpressions(test) do
    nameFrag = Temper.Orm.col(Temper.Orm.Tests.sid("users"), Temper.Orm.Tests.sid("name"))
    q = Temper.Orm.Query.selectExpr(Temper.Orm.from(Temper.Orm.Tests.sid("users")), %TemperCore.Vec{t: {nameFrag, Temper.Orm.countAll()}})
    fn_ = fn ->
      "selectExpr multi"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT users.name, COUNT(*) FROM users", fn_)
    nil
  end
  def selectExprOverridesSelectedFields(test) do
    q = Temper.Orm.Query.selectExpr(Temper.Orm.Query.select(Temper.Orm.from(Temper.Orm.Tests.sid("users")), %TemperCore.Vec{t: {Temper.Orm.Tests.sid("id"), Temper.Orm.Tests.sid("name")}}), %TemperCore.Vec{t: {Temper.Orm.countAll()}})
    fn_ = fn ->
      "selectExpr overrides select"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT COUNT(*) FROM users", fn_)
    nil
  end
  def groupBySingleField(test) do
    q = Temper.Orm.Query.groupBy(Temper.Orm.Query.selectExpr(Temper.Orm.from(Temper.Orm.Tests.sid("orders")), %TemperCore.Vec{t: {Temper.Orm.col(Temper.Orm.Tests.sid("orders"), Temper.Orm.Tests.sid("status")), Temper.Orm.countAll()}}), Temper.Orm.Tests.sid("status"))
    fn_ = fn ->
      "groupBy single"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT orders.status, COUNT(*) FROM orders GROUP BY status", fn_)
    nil
  end
  def groupByMultipleFields(test) do
    q = Temper.Orm.Query.groupBy(Temper.Orm.Query.groupBy(Temper.Orm.from(Temper.Orm.Tests.sid("orders")), Temper.Orm.Tests.sid("status")), Temper.Orm.Tests.sid("category"))
    fn_ = fn ->
      "groupBy multiple"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT * FROM orders GROUP BY status, category", fn_)
    nil
  end
  def havingBasic(test) do
    t = Temper.Orm.Query.groupBy(Temper.Orm.Query.selectExpr(Temper.Orm.from(Temper.Orm.Tests.sid("orders")), %TemperCore.Vec{t: {Temper.Orm.col(Temper.Orm.Tests.sid("orders"), Temper.Orm.Tests.sid("status")), Temper.Orm.countAll()}}), Temper.Orm.Tests.sid("status"))
    accumulator = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator, "COUNT(*) > ")
    Temper.Orm.SqlBuilder.appendInt32(accumulator, 5)
    q = Temper.Orm.Query.having(t, Temper.Orm.SqlBuilder.get_accumulated(accumulator))
    fn_ = fn ->
      "having basic"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT orders.status, COUNT(*) FROM orders GROUP BY status HAVING COUNT(*) > 5", fn_)
    nil
  end
  def orHaving(test) do
    t1 = Temper.Orm.Query.groupBy(Temper.Orm.from(Temper.Orm.Tests.sid("orders")), Temper.Orm.Tests.sid("status"))
    accumulator1 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator1, "COUNT(*) > ")
    Temper.Orm.SqlBuilder.appendInt32(accumulator1, 5)
    t2 = Temper.Orm.Query.having(t1, Temper.Orm.SqlBuilder.get_accumulated(accumulator1))
    accumulator2 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator2, "SUM(total) > ")
    Temper.Orm.SqlBuilder.appendInt32(accumulator2, 1000)
    q = Temper.Orm.Query.orHaving(t2, Temper.Orm.SqlBuilder.get_accumulated(accumulator2))
    fn_ = fn ->
      "orHaving"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT * FROM orders GROUP BY status HAVING COUNT(*) > 5 OR SUM(total) > 1000", fn_)
    nil
  end
  def distinctBasic(test) do
    q = Temper.Orm.Query.distinct(Temper.Orm.Query.select(Temper.Orm.from(Temper.Orm.Tests.sid("users")), %TemperCore.Vec{t: {Temper.Orm.Tests.sid("name")}}))
    fn_ = fn ->
      "distinct"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT DISTINCT name FROM users", fn_)
    nil
  end
  def distinctWithWhere(test) do
    t = Temper.Orm.Query.select(Temper.Orm.from(Temper.Orm.Tests.sid("users")), %TemperCore.Vec{t: {Temper.Orm.Tests.sid("email")}})
    accumulator = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator, "active = ")
    Temper.Orm.SqlBuilder.appendBoolean(accumulator, true)
    q = Temper.Orm.Query.distinct(Temper.Orm.Query.where(t, Temper.Orm.SqlBuilder.get_accumulated(accumulator)))
    fn_ = fn ->
      "distinct with where"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT DISTINCT email FROM users WHERE active = TRUE", fn_)
    nil
  end
  def countSqlBare(test) do
    q = Temper.Orm.from(Temper.Orm.Tests.sid("users"))
    fn_ = fn ->
      "countSql bare"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.countSql(q)) == "SELECT COUNT(*) FROM users", fn_)
    nil
  end
  def countSqlWithWhere(test) do
    t = Temper.Orm.from(Temper.Orm.Tests.sid("users"))
    accumulator = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator, "active = ")
    Temper.Orm.SqlBuilder.appendBoolean(accumulator, true)
    q = Temper.Orm.Query.where(t, Temper.Orm.SqlBuilder.get_accumulated(accumulator))
    fn_ = fn ->
      "countSql with where"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.countSql(q)) == "SELECT COUNT(*) FROM users WHERE active = TRUE", fn_)
    nil
  end
  def countSqlWithJoin(test) do
    t1 = Temper.Orm.from(Temper.Orm.Tests.sid("users"))
    t2 = Temper.Orm.Tests.sid("orders")
    accumulator1 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator1, "users.id = orders.user_id")
    t3 = Temper.Orm.Query.innerJoin(t1, t2, Temper.Orm.SqlBuilder.get_accumulated(accumulator1))
    accumulator2 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator2, "orders.total > ")
    Temper.Orm.SqlBuilder.appendInt32(accumulator2, 100)
    q = Temper.Orm.Query.where(t3, Temper.Orm.SqlBuilder.get_accumulated(accumulator2))
    fn_ = fn ->
      "countSql with join"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.countSql(q)) == "SELECT COUNT(*) FROM users INNER JOIN orders ON users.id = orders.user_id WHERE orders.total > 100", fn_)
    nil
  end
  def countSqlDropsOrderByLimitOffset(test) do
    _q = nil
    q = try do
      t1 = Temper.Orm.from(Temper.Orm.Tests.sid("users"))
      accumulator = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(accumulator, "active = ")
      Temper.Orm.SqlBuilder.appendBoolean(accumulator, true)
      t2 = Temper.Orm.Query.limit(Temper.Orm.Query.orderBy(Temper.Orm.Query.where(t1, Temper.Orm.SqlBuilder.get_accumulated(accumulator)), Temper.Orm.Tests.sid("name"), true), 10)
      q = Temper.Orm.Query.offset(t2, 20)
      q
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    s = Temper.Orm.SqlFragment.toString(Temper.Orm.Query.countSql(q))
    fn_ = fn ->
      "countSql drops extras: " <> s
    end
    TemperCore.Test.assert(test, s == "SELECT COUNT(*) FROM users WHERE active = TRUE", fn_)
    nil
  end
  def fullAggregationQuery(test) do
    t1 = Temper.Orm.Query.selectExpr(Temper.Orm.from(Temper.Orm.Tests.sid("orders")), %TemperCore.Vec{t: {Temper.Orm.col(Temper.Orm.Tests.sid("orders"), Temper.Orm.Tests.sid("status")), Temper.Orm.countAll(), Temper.Orm.sumCol(Temper.Orm.Tests.sid("total"))}})
    t2 = Temper.Orm.Tests.sid("users")
    accumulator1 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator1, "orders.user_id = users.id")
    t3 = Temper.Orm.Query.innerJoin(t1, t2, Temper.Orm.SqlBuilder.get_accumulated(accumulator1))
    accumulator2 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator2, "users.active = ")
    Temper.Orm.SqlBuilder.appendBoolean(accumulator2, true)
    t4 = Temper.Orm.Query.groupBy(Temper.Orm.Query.where(t3, Temper.Orm.SqlBuilder.get_accumulated(accumulator2)), Temper.Orm.Tests.sid("status"))
    accumulator3 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator3, "COUNT(*) > ")
    Temper.Orm.SqlBuilder.appendInt32(accumulator3, 3)
    q = Temper.Orm.Query.orderBy(Temper.Orm.Query.having(t4, Temper.Orm.SqlBuilder.get_accumulated(accumulator3)), Temper.Orm.Tests.sid("status"), true)
    _expected = "SELECT orders.status, COUNT(*), SUM(total) FROM orders INNER JOIN users ON orders.user_id = users.id WHERE users.active = TRUE GROUP BY status HAVING COUNT(*) > 3 ORDER BY status ASC"
    fn_ = fn ->
      "full aggregation"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT orders.status, COUNT(*), SUM(total) FROM orders INNER JOIN users ON orders.user_id = users.id WHERE users.active = TRUE GROUP BY status HAVING COUNT(*) > 3 ORDER BY status ASC", fn_)
    nil
  end
  def unionSql__2(test) do
    t1 = Temper.Orm.from(Temper.Orm.Tests.sid("users"))
    accumulator1 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator1, "role = ")
    Temper.Orm.SqlBuilder.appendString(accumulator1, "admin")
    a = Temper.Orm.Query.where(t1, Temper.Orm.SqlBuilder.get_accumulated(accumulator1))
    t2 = Temper.Orm.from(Temper.Orm.Tests.sid("users"))
    accumulator2 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator2, "role = ")
    Temper.Orm.SqlBuilder.appendString(accumulator2, "moderator")
    b = Temper.Orm.Query.where(t2, Temper.Orm.SqlBuilder.get_accumulated(accumulator2))
    s = Temper.Orm.SqlFragment.toString(Temper.Orm.unionSql(a, b))
    fn_ = fn ->
      "unionSql: " <> s
    end
    TemperCore.Test.assert(test, s == "(SELECT * FROM users WHERE role = 'admin') UNION (SELECT * FROM users WHERE role = 'moderator')", fn_)
    nil
  end
  def unionAllSql__2(test) do
    a = Temper.Orm.Query.select(Temper.Orm.from(Temper.Orm.Tests.sid("users")), %TemperCore.Vec{t: {Temper.Orm.Tests.sid("name")}})
    b = Temper.Orm.Query.select(Temper.Orm.from(Temper.Orm.Tests.sid("contacts")), %TemperCore.Vec{t: {Temper.Orm.Tests.sid("name")}})
    s = Temper.Orm.SqlFragment.toString(Temper.Orm.unionAllSql(a, b))
    fn_ = fn ->
      "unionAllSql: " <> s
    end
    TemperCore.Test.assert(test, s == "(SELECT name FROM users) UNION ALL (SELECT name FROM contacts)", fn_)
    nil
  end
  def intersectSql__2(test) do
    a = Temper.Orm.Query.select(Temper.Orm.from(Temper.Orm.Tests.sid("users")), %TemperCore.Vec{t: {Temper.Orm.Tests.sid("email")}})
    b = Temper.Orm.Query.select(Temper.Orm.from(Temper.Orm.Tests.sid("subscribers")), %TemperCore.Vec{t: {Temper.Orm.Tests.sid("email")}})
    s = Temper.Orm.SqlFragment.toString(Temper.Orm.intersectSql(a, b))
    fn_ = fn ->
      "intersectSql: " <> s
    end
    TemperCore.Test.assert(test, s == "(SELECT email FROM users) INTERSECT (SELECT email FROM subscribers)", fn_)
    nil
  end
  def exceptSql__2(test) do
    a = Temper.Orm.Query.select(Temper.Orm.from(Temper.Orm.Tests.sid("users")), %TemperCore.Vec{t: {Temper.Orm.Tests.sid("id")}})
    b = Temper.Orm.Query.select(Temper.Orm.from(Temper.Orm.Tests.sid("banned")), %TemperCore.Vec{t: {Temper.Orm.Tests.sid("id")}})
    s = Temper.Orm.SqlFragment.toString(Temper.Orm.exceptSql(a, b))
    fn_ = fn ->
      "exceptSql: " <> s
    end
    TemperCore.Test.assert(test, s == "(SELECT id FROM users) EXCEPT (SELECT id FROM banned)", fn_)
    nil
  end
  def subqueryWithAlias(test) do
    t = Temper.Orm.Query.select(Temper.Orm.from(Temper.Orm.Tests.sid("orders")), %TemperCore.Vec{t: {Temper.Orm.Tests.sid("user_id")}})
    accumulator = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator, "total > ")
    Temper.Orm.SqlBuilder.appendInt32(accumulator, 100)
    inner = Temper.Orm.Query.where(t, Temper.Orm.SqlBuilder.get_accumulated(accumulator))
    s = Temper.Orm.SqlFragment.toString(Temper.Orm.subquery(inner, Temper.Orm.Tests.sid("big_orders")))
    fn_ = fn ->
      "subquery: " <> s
    end
    TemperCore.Test.assert(test, s == "(SELECT user_id FROM orders WHERE total > 100) AS big_orders", fn_)
    nil
  end
  def existsSql__2(test) do
    t = Temper.Orm.from(Temper.Orm.Tests.sid("orders"))
    accumulator = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator, "orders.user_id = users.id")
    inner = Temper.Orm.Query.where(t, Temper.Orm.SqlBuilder.get_accumulated(accumulator))
    s = Temper.Orm.SqlFragment.toString(Temper.Orm.existsSql(inner))
    fn_ = fn ->
      "existsSql: " <> s
    end
    TemperCore.Test.assert(test, s == "EXISTS (SELECT * FROM orders WHERE orders.user_id = users.id)", fn_)
    nil
  end
  def whereInSubquery(test) do
    t = Temper.Orm.Query.select(Temper.Orm.from(Temper.Orm.Tests.sid("orders")), %TemperCore.Vec{t: {Temper.Orm.Tests.sid("user_id")}})
    accumulator = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator, "total > ")
    Temper.Orm.SqlBuilder.appendInt32(accumulator, 1000)
    sub = Temper.Orm.Query.where(t, Temper.Orm.SqlBuilder.get_accumulated(accumulator))
    q = Temper.Orm.Query.whereInSubquery(Temper.Orm.from(Temper.Orm.Tests.sid("users")), Temper.Orm.Tests.sid("id"), sub)
    s = Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q))
    fn_ = fn ->
      "whereInSubquery: " <> s
    end
    TemperCore.Test.assert(test, s == "SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE total > 1000)", fn_)
    nil
  end
  def setOperationWithWhereOnEachSide(test) do
    t1 = Temper.Orm.from(Temper.Orm.Tests.sid("users"))
    accumulator1 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator1, "age > ")
    Temper.Orm.SqlBuilder.appendInt32(accumulator1, 18)
    t2 = Temper.Orm.Query.where(t1, Temper.Orm.SqlBuilder.get_accumulated(accumulator1))
    accumulator2 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator2, "active = ")
    Temper.Orm.SqlBuilder.appendBoolean(accumulator2, true)
    a = Temper.Orm.Query.where(t2, Temper.Orm.SqlBuilder.get_accumulated(accumulator2))
    t3 = Temper.Orm.from(Temper.Orm.Tests.sid("users"))
    accumulator3 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator3, "role = ")
    Temper.Orm.SqlBuilder.appendString(accumulator3, "vip")
    b = Temper.Orm.Query.where(t3, Temper.Orm.SqlBuilder.get_accumulated(accumulator3))
    s = Temper.Orm.SqlFragment.toString(Temper.Orm.unionSql(a, b))
    fn_ = fn ->
      "union with where: " <> s
    end
    TemperCore.Test.assert(test, s == "(SELECT * FROM users WHERE age > 18 AND active = TRUE) UNION (SELECT * FROM users WHERE role = 'vip')", fn_)
    nil
  end
  def whereInSubqueryChainedWithWhere(test) do
    sub = Temper.Orm.Query.select(Temper.Orm.from(Temper.Orm.Tests.sid("orders")), %TemperCore.Vec{t: {Temper.Orm.Tests.sid("user_id")}})
    t = Temper.Orm.from(Temper.Orm.Tests.sid("users"))
    accumulator = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator, "active = ")
    Temper.Orm.SqlBuilder.appendBoolean(accumulator, true)
    q = Temper.Orm.Query.whereInSubquery(Temper.Orm.Query.where(t, Temper.Orm.SqlBuilder.get_accumulated(accumulator)), Temper.Orm.Tests.sid("id"), sub)
    s = Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q))
    fn_ = fn ->
      "whereInSubquery chained: " <> s
    end
    TemperCore.Test.assert(test, s == "SELECT * FROM users WHERE active = TRUE AND id IN (SELECT user_id FROM orders)", fn_)
    nil
  end
  def existsSqlUsedInWhere(test) do
    t = Temper.Orm.from(Temper.Orm.Tests.sid("orders"))
    accumulator = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator, "orders.user_id = users.id")
    sub = Temper.Orm.Query.where(t, Temper.Orm.SqlBuilder.get_accumulated(accumulator))
    q = Temper.Orm.Query.where(Temper.Orm.from(Temper.Orm.Tests.sid("users")), Temper.Orm.existsSql(sub))
    s = Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q))
    fn_ = fn ->
      "exists in where: " <> s
    end
    TemperCore.Test.assert(test, s == "SELECT * FROM users WHERE EXISTS (SELECT * FROM orders WHERE orders.user_id = users.id)", fn_)
    nil
  end
  def updateQueryBasic(test) do
    _q = nil
    q = try do
      t = Temper.Orm.UpdateQuery.set(Temper.Orm.update(Temper.Orm.Tests.sid("users")), Temper.Orm.Tests.sid("name"), Temper.Orm.SqlString.new("Alice"))
      accumulator = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(accumulator, "id = ")
      Temper.Orm.SqlBuilder.appendInt32(accumulator, 1)
      q = Temper.Orm.UpdateQuery.toSql(Temper.Orm.UpdateQuery.where(t, Temper.Orm.SqlBuilder.get_accumulated(accumulator)))
      q
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    fn_ = fn ->
      "update basic"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(q) == "UPDATE users SET name = 'Alice' WHERE id = 1", fn_)
    nil
  end
  def updateQueryMultipleSet(test) do
    _q = nil
    q = try do
      t = Temper.Orm.UpdateQuery.set(Temper.Orm.UpdateQuery.set(Temper.Orm.update(Temper.Orm.Tests.sid("users")), Temper.Orm.Tests.sid("name"), Temper.Orm.SqlString.new("Bob")), Temper.Orm.Tests.sid("age"), Temper.Orm.SqlInt32.new(30))
      accumulator = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(accumulator, "id = ")
      Temper.Orm.SqlBuilder.appendInt32(accumulator, 2)
      q = Temper.Orm.UpdateQuery.toSql(Temper.Orm.UpdateQuery.where(t, Temper.Orm.SqlBuilder.get_accumulated(accumulator)))
      q
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    fn_ = fn ->
      "update multi set"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(q) == "UPDATE users SET name = 'Bob', age = 30 WHERE id = 2", fn_)
    nil
  end
  def updateQueryMultipleWhere(test) do
    _q = nil
    q = try do
      t1 = Temper.Orm.UpdateQuery.set(Temper.Orm.update(Temper.Orm.Tests.sid("users")), Temper.Orm.Tests.sid("active"), Temper.Orm.SqlBoolean.new(false))
      accumulator1 = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(accumulator1, "age < ")
      Temper.Orm.SqlBuilder.appendInt32(accumulator1, 18)
      t2 = Temper.Orm.UpdateQuery.where(t1, Temper.Orm.SqlBuilder.get_accumulated(accumulator1))
      accumulator2 = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(accumulator2, "role = ")
      Temper.Orm.SqlBuilder.appendString(accumulator2, "guest")
      q = Temper.Orm.UpdateQuery.toSql(Temper.Orm.UpdateQuery.where(t2, Temper.Orm.SqlBuilder.get_accumulated(accumulator2)))
      q
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    fn_ = fn ->
      "update multi where"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(q) == "UPDATE users SET active = FALSE WHERE age < 18 AND role = 'guest'", fn_)
    nil
  end
  def updateQueryOrWhere(test) do
    _q = nil
    q = try do
      t1 = Temper.Orm.UpdateQuery.set(Temper.Orm.update(Temper.Orm.Tests.sid("users")), Temper.Orm.Tests.sid("status"), Temper.Orm.SqlString.new("banned"))
      accumulator1 = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(accumulator1, "spam_count > ")
      Temper.Orm.SqlBuilder.appendInt32(accumulator1, 10)
      t2 = Temper.Orm.UpdateQuery.where(t1, Temper.Orm.SqlBuilder.get_accumulated(accumulator1))
      accumulator2 = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(accumulator2, "reported = ")
      Temper.Orm.SqlBuilder.appendBoolean(accumulator2, true)
      q = Temper.Orm.UpdateQuery.toSql(Temper.Orm.UpdateQuery.orWhere(t2, Temper.Orm.SqlBuilder.get_accumulated(accumulator2)))
      q
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    fn_ = fn ->
      "update orWhere"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(q) == "UPDATE users SET status = 'banned' WHERE spam_count > 10 OR reported = TRUE", fn_)
    nil
  end
  def updateQueryBubblesWithoutWhere(test) do
    _didBubble = nil
    didBubble = try do
      Temper.Orm.UpdateQuery.toSql(Temper.Orm.UpdateQuery.set(Temper.Orm.update(Temper.Orm.Tests.sid("users")), Temper.Orm.Tests.sid("x"), Temper.Orm.SqlInt32.new(1)))
      didBubble = false
      didBubble
    rescue
      _ in TemperCore.Bubble ->
        didBubble = true
        didBubble
    end
    fn_ = fn ->
      "update without WHERE should bubble"
    end
    TemperCore.Test.assert(test, didBubble, fn_)
    nil
  end
  def updateQueryBubblesWithoutSet(test) do
    _didBubble = nil
    didBubble = try do
      t = Temper.Orm.update(Temper.Orm.Tests.sid("users"))
      accumulator = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(accumulator, "id = ")
      Temper.Orm.SqlBuilder.appendInt32(accumulator, 1)
      Temper.Orm.UpdateQuery.toSql(Temper.Orm.UpdateQuery.where(t, Temper.Orm.SqlBuilder.get_accumulated(accumulator)))
      didBubble = false
      didBubble
    rescue
      _ in TemperCore.Bubble ->
        didBubble = true
        didBubble
    end
    fn_ = fn ->
      "update without SET should bubble"
    end
    TemperCore.Test.assert(test, didBubble, fn_)
    nil
  end
  def updateQueryWithLimit(test) do
    _q = nil
    q = try do
      t1 = Temper.Orm.UpdateQuery.set(Temper.Orm.update(Temper.Orm.Tests.sid("users")), Temper.Orm.Tests.sid("active"), Temper.Orm.SqlBoolean.new(false))
      accumulator = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(accumulator, "last_login < ")
      Temper.Orm.SqlBuilder.appendString(accumulator, "2024-01-01")
      t2 = Temper.Orm.UpdateQuery.limit(Temper.Orm.UpdateQuery.where(t1, Temper.Orm.SqlBuilder.get_accumulated(accumulator)), 100)
      q = Temper.Orm.UpdateQuery.toSql(t2)
      q
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    fn_ = fn ->
      "update limit"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(q) == "UPDATE users SET active = FALSE WHERE last_login < '2024-01-01' LIMIT 100", fn_)
    nil
  end
  def updateQueryEscaping(test) do
    _q = nil
    q = try do
      t = Temper.Orm.UpdateQuery.set(Temper.Orm.update(Temper.Orm.Tests.sid("users")), Temper.Orm.Tests.sid("bio"), Temper.Orm.SqlString.new("It's a test"))
      accumulator = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(accumulator, "id = ")
      Temper.Orm.SqlBuilder.appendInt32(accumulator, 1)
      q = Temper.Orm.UpdateQuery.toSql(Temper.Orm.UpdateQuery.where(t, Temper.Orm.SqlBuilder.get_accumulated(accumulator)))
      q
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    fn_ = fn ->
      "update escaping"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(q) == "UPDATE users SET bio = 'It''s a test' WHERE id = 1", fn_)
    nil
  end
  def deleteQueryBasic(test) do
    _q = nil
    q = try do
      t = Temper.Orm.deleteFrom(Temper.Orm.Tests.sid("users"))
      accumulator = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(accumulator, "id = ")
      Temper.Orm.SqlBuilder.appendInt32(accumulator, 1)
      q = Temper.Orm.DeleteQuery.toSql(Temper.Orm.DeleteQuery.where(t, Temper.Orm.SqlBuilder.get_accumulated(accumulator)))
      q
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    fn_ = fn ->
      "delete basic"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(q) == "DELETE FROM users WHERE id = 1", fn_)
    nil
  end
  def deleteQueryMultipleWhere(test) do
    _q = nil
    q = try do
      t1 = Temper.Orm.deleteFrom(Temper.Orm.Tests.sid("logs"))
      accumulator1 = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(accumulator1, "created_at < ")
      Temper.Orm.SqlBuilder.appendString(accumulator1, "2024-01-01")
      t2 = Temper.Orm.DeleteQuery.where(t1, Temper.Orm.SqlBuilder.get_accumulated(accumulator1))
      accumulator2 = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(accumulator2, "level = ")
      Temper.Orm.SqlBuilder.appendString(accumulator2, "debug")
      q = Temper.Orm.DeleteQuery.toSql(Temper.Orm.DeleteQuery.where(t2, Temper.Orm.SqlBuilder.get_accumulated(accumulator2)))
      q
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    fn_ = fn ->
      "delete multi where"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(q) == "DELETE FROM logs WHERE created_at < '2024-01-01' AND level = 'debug'", fn_)
    nil
  end
  def deleteQueryBubblesWithoutWhere(test) do
    _didBubble = nil
    didBubble = try do
      Temper.Orm.DeleteQuery.toSql(Temper.Orm.deleteFrom(Temper.Orm.Tests.sid("users")))
      didBubble = false
      didBubble
    rescue
      _ in TemperCore.Bubble ->
        didBubble = true
        didBubble
    end
    fn_ = fn ->
      "delete without WHERE should bubble"
    end
    TemperCore.Test.assert(test, didBubble, fn_)
    nil
  end
  def deleteQueryOrWhere(test) do
    _q = nil
    q = try do
      t1 = Temper.Orm.deleteFrom(Temper.Orm.Tests.sid("sessions"))
      accumulator1 = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(accumulator1, "expired = ")
      Temper.Orm.SqlBuilder.appendBoolean(accumulator1, true)
      t2 = Temper.Orm.DeleteQuery.where(t1, Temper.Orm.SqlBuilder.get_accumulated(accumulator1))
      accumulator2 = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(accumulator2, "created_at < ")
      Temper.Orm.SqlBuilder.appendString(accumulator2, "2023-01-01")
      q = Temper.Orm.DeleteQuery.toSql(Temper.Orm.DeleteQuery.orWhere(t2, Temper.Orm.SqlBuilder.get_accumulated(accumulator2)))
      q
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    fn_ = fn ->
      "delete orWhere"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(q) == "DELETE FROM sessions WHERE expired = TRUE OR created_at < '2023-01-01'", fn_)
    nil
  end
  def deleteQueryWithLimit(test) do
    _q = nil
    q = try do
      t1 = Temper.Orm.deleteFrom(Temper.Orm.Tests.sid("logs"))
      accumulator = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(accumulator, "level = ")
      Temper.Orm.SqlBuilder.appendString(accumulator, "debug")
      t2 = Temper.Orm.DeleteQuery.limit(Temper.Orm.DeleteQuery.where(t1, Temper.Orm.SqlBuilder.get_accumulated(accumulator)), 1000)
      q = Temper.Orm.DeleteQuery.toSql(t2)
      q
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    fn_ = fn ->
      "delete limit"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(q) == "DELETE FROM logs WHERE level = 'debug' LIMIT 1000", fn_)
    nil
  end
  def orderByNullsNullsFirst(test) do
    q = Temper.Orm.Query.orderByNulls(Temper.Orm.from(Temper.Orm.Tests.sid("users")), Temper.Orm.Tests.sid("email"), true, Temper.Orm.NullsFirst.new())
    fn_ = fn ->
      "nulls first"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT * FROM users ORDER BY email ASC NULLS FIRST", fn_)
    nil
  end
  def orderByNullsNullsLast(test) do
    q = Temper.Orm.Query.orderByNulls(Temper.Orm.from(Temper.Orm.Tests.sid("users")), Temper.Orm.Tests.sid("score"), false, Temper.Orm.NullsLast.new())
    fn_ = fn ->
      "nulls last"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT * FROM users ORDER BY score DESC NULLS LAST", fn_)
    nil
  end
  def mixedOrderByAndOrderByNulls(test) do
    q = Temper.Orm.Query.orderByNulls(Temper.Orm.Query.orderBy(Temper.Orm.from(Temper.Orm.Tests.sid("users")), Temper.Orm.Tests.sid("name"), true), Temper.Orm.Tests.sid("email"), true, Temper.Orm.NullsFirst.new())
    fn_ = fn ->
      "mixed order"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT * FROM users ORDER BY name ASC, email ASC NULLS FIRST", fn_)
    nil
  end
  def crossJoin(test) do
    q = Temper.Orm.Query.crossJoin(Temper.Orm.from(Temper.Orm.Tests.sid("users")), Temper.Orm.Tests.sid("colors"))
    fn_ = fn ->
      "cross join"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT * FROM users CROSS JOIN colors", fn_)
    nil
  end
  def crossJoinCombinedWithOtherJoins(test) do
    t1 = Temper.Orm.from(Temper.Orm.Tests.sid("users"))
    t2 = Temper.Orm.Tests.sid("orders")
    accumulator = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator, "users.id = orders.user_id")
    q = Temper.Orm.Query.crossJoin(Temper.Orm.Query.innerJoin(t1, t2, Temper.Orm.SqlBuilder.get_accumulated(accumulator)), Temper.Orm.Tests.sid("colors"))
    fn_ = fn ->
      "cross + inner join"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT * FROM users INNER JOIN orders ON users.id = orders.user_id CROSS JOIN colors", fn_)
    nil
  end
  def lockForUpdate(test) do
    t = Temper.Orm.from(Temper.Orm.Tests.sid("users"))
    accumulator = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator, "id = ")
    Temper.Orm.SqlBuilder.appendInt32(accumulator, 1)
    q = Temper.Orm.Query.lock(Temper.Orm.Query.where(t, Temper.Orm.SqlBuilder.get_accumulated(accumulator)), Temper.Orm.ForUpdate.new())
    fn_ = fn ->
      "for update"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT * FROM users WHERE id = 1 FOR UPDATE", fn_)
    nil
  end
  def lockForShare(test) do
    q = Temper.Orm.Query.lock(Temper.Orm.Query.select(Temper.Orm.from(Temper.Orm.Tests.sid("users")), %TemperCore.Vec{t: {Temper.Orm.Tests.sid("name")}}), Temper.Orm.ForShare.new())
    fn_ = fn ->
      "for share"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT name FROM users FOR SHARE", fn_)
    nil
  end
  def lockWithFullQuery(test) do
    _q = nil
    q = try do
      t1 = Temper.Orm.from(Temper.Orm.Tests.sid("accounts"))
      accumulator = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(accumulator, "id = ")
      Temper.Orm.SqlBuilder.appendInt32(accumulator, 42)
      t2 = Temper.Orm.Query.limit(Temper.Orm.Query.where(t1, Temper.Orm.SqlBuilder.get_accumulated(accumulator)), 1)
      q = Temper.Orm.Query.lock(t2, Temper.Orm.ForUpdate.new())
      q
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    fn_ = fn ->
      "lock full query"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT * FROM accounts WHERE id = 42 LIMIT 1 FOR UPDATE", fn_)
    nil
  end
  def queryBuilderImmutabilityTwoQueriesFromSameBase(test) do
    t = Temper.Orm.from(Temper.Orm.Tests.sid("users"))
    accumulator = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator, "active = ")
    Temper.Orm.SqlBuilder.appendBoolean(accumulator, true)
    base = Temper.Orm.Query.where(t, Temper.Orm.SqlBuilder.get_accumulated(accumulator))
    _q1 = nil
    q1 = try do
      q1 = Temper.Orm.Query.limit(base, 10)
      q1
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    _q2 = nil
    q2 = try do
      q2 = Temper.Orm.Query.limit(base, 20)
      q2
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    fn_1 = fn ->
      "q1"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q1)) == "SELECT * FROM users WHERE active = TRUE LIMIT 10", fn_1)
    fn_2 = fn ->
      "q2"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q2)) == "SELECT * FROM users WHERE active = TRUE LIMIT 20", fn_2)
    nil
  end
  def limitZeroProducesLimit0(test) do
    _q = nil
    q = try do
      q = Temper.Orm.Query.limit(Temper.Orm.from(Temper.Orm.Tests.sid("users")), 0)
      q
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    fn_ = fn ->
      "limit 0"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.Query.toSql(q)) == "SELECT * FROM users LIMIT 0", fn_)
    nil
  end
  def safeToSqlWithZeroDefaultLimit(test) do
    q = Temper.Orm.from(Temper.Orm.Tests.sid("users"))
    _s = nil
    s = try do
      s = Temper.Orm.Query.safeToSql(q, 0)
      s
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    fn_ = fn ->
      "safeToSql 0"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(s) == "SELECT * FROM users LIMIT 0", fn_)
    nil
  end
  def updateQueryLimitBubblesOnNegative(test) do
    _didBubble = nil
    didBubble = try do
      t = Temper.Orm.UpdateQuery.set(Temper.Orm.update(Temper.Orm.Tests.sid("users")), Temper.Orm.Tests.sid("name"), Temper.Orm.SqlString.new("x"))
      accumulator = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(accumulator, "id = ")
      Temper.Orm.SqlBuilder.appendInt32(accumulator, 1)
      Temper.Orm.UpdateQuery.limit(Temper.Orm.UpdateQuery.where(t, Temper.Orm.SqlBuilder.get_accumulated(accumulator)), -1)
      didBubble = false
      didBubble
    rescue
      _ in TemperCore.Bubble ->
        didBubble = true
        didBubble
    end
    fn_ = fn ->
      "UpdateQuery negative limit should bubble"
    end
    TemperCore.Test.assert(test, didBubble, fn_)
    nil
  end
  def deleteQueryLimitBubblesOnNegative(test) do
    _didBubble = nil
    didBubble = try do
      t = Temper.Orm.deleteFrom(Temper.Orm.Tests.sid("users"))
      accumulator = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(accumulator, "id = ")
      Temper.Orm.SqlBuilder.appendInt32(accumulator, 1)
      Temper.Orm.DeleteQuery.limit(Temper.Orm.DeleteQuery.where(t, Temper.Orm.SqlBuilder.get_accumulated(accumulator)), -1)
      didBubble = false
      didBubble
    rescue
      _ in TemperCore.Bubble ->
        didBubble = true
        didBubble
    end
    fn_ = fn ->
      "DeleteQuery negative limit should bubble"
    end
    TemperCore.Test.assert(test, didBubble, fn_)
    nil
  end
  def updateQueryImmutabilityTwoFromSameBase(test) do
    _t1 = nil
    _t2 = nil
    t3 = Temper.Orm.UpdateQuery.set(Temper.Orm.update(Temper.Orm.Tests.sid("users")), Temper.Orm.Tests.sid("name"), Temper.Orm.SqlString.new("Alice"))
    accumulator = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator, "id = ")
    Temper.Orm.SqlBuilder.appendInt32(accumulator, 1)
    base = Temper.Orm.UpdateQuery.where(t3, Temper.Orm.SqlBuilder.get_accumulated(accumulator))
    q1 = Temper.Orm.UpdateQuery.set(base, Temper.Orm.Tests.sid("age"), Temper.Orm.SqlInt32.new(25))
    q2 = Temper.Orm.UpdateQuery.set(base, Temper.Orm.Tests.sid("age"), Temper.Orm.SqlInt32.new(30))
    t1 = try do
      t1 = Temper.Orm.UpdateQuery.toSql(q1)
      t1
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    s1 = Temper.Orm.SqlFragment.toString(t1)
    t2 = try do
      t2 = Temper.Orm.UpdateQuery.toSql(q2)
      t2
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    s2 = Temper.Orm.SqlFragment.toString(t2)
    t4 = TemperCore.String.index_of(s1, "25") >= 0
    fn_1 = fn ->
      "q1 should have 25: " <> s1
    end
    TemperCore.Test.assert(test, t4, fn_1)
    t5 = TemperCore.String.index_of(s2, "30") >= 0
    fn_2 = fn ->
      "q2 should have 30: " <> s2
    end
    TemperCore.Test.assert(test, t5, fn_2)
    t6 = TemperCore.String.index_of(s1, "30") >= 0
    fn_3 = fn ->
      "q1 should NOT have 30: " <> s1
    end
    TemperCore.Test.assert(test, not t6, fn_3)
    nil
  end
  def deleteQueryImmutability(test) do
    _t1 = nil
    _t2 = nil
    t3 = Temper.Orm.deleteFrom(Temper.Orm.Tests.sid("users"))
    accumulator1 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator1, "active = ")
    Temper.Orm.SqlBuilder.appendBoolean(accumulator1, false)
    base = Temper.Orm.DeleteQuery.where(t3, Temper.Orm.SqlBuilder.get_accumulated(accumulator1))
    accumulator2 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator2, "age < ")
    Temper.Orm.SqlBuilder.appendInt32(accumulator2, 18)
    q1 = Temper.Orm.DeleteQuery.where(base, Temper.Orm.SqlBuilder.get_accumulated(accumulator2))
    accumulator3 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator3, "age > ")
    Temper.Orm.SqlBuilder.appendInt32(accumulator3, 65)
    q2 = Temper.Orm.DeleteQuery.where(base, Temper.Orm.SqlBuilder.get_accumulated(accumulator3))
    t1 = try do
      t1 = Temper.Orm.DeleteQuery.toSql(q1)
      t1
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    s1 = Temper.Orm.SqlFragment.toString(t1)
    t2 = try do
      t2 = Temper.Orm.DeleteQuery.toSql(q2)
      t2
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    s2 = Temper.Orm.SqlFragment.toString(t2)
    t4 = TemperCore.String.index_of(s1, "age < 18") >= 0
    fn_1 = fn ->
      "q1: " <> s1
    end
    TemperCore.Test.assert(test, t4, fn_1)
    t5 = TemperCore.String.index_of(s2, "age > 65") >= 0
    fn_2 = fn ->
      "q2: " <> s2
    end
    TemperCore.Test.assert(test, t5, fn_2)
    t6 = TemperCore.String.index_of(s1, "age > 65") >= 0
    fn_3 = fn ->
      "q1 should not have q2 condition: " <> s1
    end
    TemperCore.Test.assert(test, not t6, fn_3)
    nil
  end
  def safeIdentifierAcceptsValidNames(test) do
    _id = nil
    id = try do
      id = Temper.Orm.safeIdentifier("user_name")
      id
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    fn_ = fn ->
      "value should round-trip"
    end
    TemperCore.Test.assert(test, TemperCore.call(id, :get_sqlValue, []) == "user_name", fn_)
    nil
  end
  def safeIdentifierRejectsEmptyString(test) do
    _didBubble = nil
    didBubble = try do
      Temper.Orm.safeIdentifier("")
      didBubble = false
      didBubble
    rescue
      _ in TemperCore.Bubble ->
        didBubble = true
        didBubble
    end
    fn_ = fn ->
      "empty string should bubble"
    end
    TemperCore.Test.assert(test, didBubble, fn_)
    nil
  end
  def safeIdentifierRejectsLeadingDigit(test) do
    _didBubble = nil
    didBubble = try do
      Temper.Orm.safeIdentifier("1col")
      didBubble = false
      didBubble
    rescue
      _ in TemperCore.Bubble ->
        didBubble = true
        didBubble
    end
    fn_ = fn ->
      "leading digit should bubble"
    end
    TemperCore.Test.assert(test, didBubble, fn_)
    nil
  end
  def safeIdentifierRejectsSqlMetacharacters(test) do
    cases = %TemperCore.Vec{t: {"name); DROP TABLE", "col'", "a b", "a-b", "a.b", "a;b"}}
    this = cases
    n = TemperCore.List.length(this)
    i = 0
    ex_loop_1 = fn ex_loop_1, i ->
      if i < n do
        el = TemperCore.List.get(this, i)
        i = TemperCore.int32(i + 1)
        c = el
        _didBubble = nil
        didBubble = try do
          Temper.Orm.safeIdentifier(c)
          didBubble = false
          didBubble
        rescue
          _ in TemperCore.Bubble ->
            didBubble = true
            didBubble
        end
        fn_ = fn ->
          "should reject: " <> c
        end
        TemperCore.Test.assert(test, didBubble, fn_)
        ex_loop_1.(ex_loop_1, i)
      else
        i
      end
    end
    _i = ex_loop_1.(ex_loop_1, i)
    nil
  end
  def tableDefFieldLookupFound(test) do
    _t1 = nil
    _t2 = nil
    _t3 = nil
    t1 = try do
      t1 = Temper.Orm.safeIdentifier("users")
      t1
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    t2 = try do
      t2 = Temper.Orm.safeIdentifier("name")
      t2
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    t3 = try do
      t3 = Temper.Orm.safeIdentifier("age")
      t3
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    td = Temper.Orm.TableDef.new(t1, %TemperCore.Vec{t: {Temper.Orm.FieldDef.new(t2, Temper.Orm.StringField.new(), false, nil, false), Temper.Orm.FieldDef.new(t3, Temper.Orm.IntField.new(), false, nil, false)}}, nil)
    _f = nil
    f = try do
      f = Temper.Orm.TableDef.field(td, "age")
      f
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    fn_ = fn ->
      "should find age field"
    end
    TemperCore.Test.assert(test, TemperCore.call(Temper.Orm.FieldDef.get_name(f), :get_sqlValue, []) == "age", fn_)
    nil
  end
  def tableDefFieldLookupNotFoundBubbles(test) do
    _t1 = nil
    _t2 = nil
    t1 = try do
      t1 = Temper.Orm.safeIdentifier("users")
      t1
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    t2 = try do
      t2 = Temper.Orm.safeIdentifier("name")
      t2
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    td = Temper.Orm.TableDef.new(t1, %TemperCore.Vec{t: {Temper.Orm.FieldDef.new(t2, Temper.Orm.StringField.new(), false, nil, false)}}, nil)
    _didBubble = nil
    didBubble = try do
      Temper.Orm.TableDef.field(td, "nonexistent")
      didBubble = false
      didBubble
    rescue
      _ in TemperCore.Bubble ->
        didBubble = true
        didBubble
    end
    fn_ = fn ->
      "unknown field should bubble"
    end
    TemperCore.Test.assert(test, didBubble, fn_)
    nil
  end
  def fieldDefNullableFlag(test) do
    _t1 = nil
    _t2 = nil
    t1 = try do
      t1 = Temper.Orm.safeIdentifier("email")
      t1
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    required = Temper.Orm.FieldDef.new(t1, Temper.Orm.StringField.new(), false, nil, false)
    t2 = try do
      t2 = Temper.Orm.safeIdentifier("bio")
      t2
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    optional = Temper.Orm.FieldDef.new(t2, Temper.Orm.StringField.new(), true, nil, false)
    fn_1 = fn ->
      "required field should not be nullable"
    end
    TemperCore.Test.assert(test, not Temper.Orm.FieldDef.get_nullable(required), fn_1)
    fn_2 = fn ->
      "optional field should be nullable"
    end
    TemperCore.Test.assert(test, Temper.Orm.FieldDef.get_nullable(optional), fn_2)
    nil
  end
  def pkNameDefaultsToIdWhenPrimaryKeyIsNull(test) do
    _t1 = nil
    _t2 = nil
    t1 = try do
      t1 = Temper.Orm.safeIdentifier("users")
      t1
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    t2 = try do
      t2 = Temper.Orm.safeIdentifier("name")
      t2
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    td = Temper.Orm.TableDef.new(t1, %TemperCore.Vec{t: {Temper.Orm.FieldDef.new(t2, Temper.Orm.StringField.new(), false, nil, false)}}, nil)
    fn_ = fn ->
      "default pk should be id"
    end
    TemperCore.Test.assert(test, Temper.Orm.TableDef.pkName(td) == "id", fn_)
    nil
  end
  def pkNameReturnsCustomPrimaryKey(test) do
    _t1 = nil
    _t2 = nil
    _t3 = nil
    t1 = try do
      t1 = Temper.Orm.safeIdentifier("users")
      t1
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    t2 = try do
      t2 = Temper.Orm.safeIdentifier("user_id")
      t2
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    t4 = %TemperCore.Vec{t: {Temper.Orm.FieldDef.new(t2, Temper.Orm.IntField.new(), false, nil, false)}}
    t3 = try do
      t3 = Temper.Orm.safeIdentifier("user_id")
      t3
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    td = Temper.Orm.TableDef.new(t1, t4, t3)
    fn_ = fn ->
      "custom pk should be user_id"
    end
    TemperCore.Test.assert(test, Temper.Orm.TableDef.pkName(td) == "user_id", fn_)
    nil
  end
  def timestampsReturnsTwoDateFieldDefs(test) do
    _ts = nil
    ts = try do
      ts = Temper.Orm.timestamps()
      ts
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    fn_1 = fn ->
      "should return 2 fields"
    end
    TemperCore.Test.assert(test, TemperCore.List.length(ts) == 2, fn_1)
    fn_2 = fn ->
      "first should be inserted_at"
    end
    TemperCore.Test.assert(test, TemperCore.call(Temper.Orm.FieldDef.get_name(TemperCore.List.get(ts, 0)), :get_sqlValue, []) == "inserted_at", fn_2)
    fn_3 = fn ->
      "second should be updated_at"
    end
    TemperCore.Test.assert(test, TemperCore.call(Temper.Orm.FieldDef.get_name(TemperCore.List.get(ts, 1)), :get_sqlValue, []) == "updated_at", fn_3)
    fn_4 = fn ->
      "inserted_at should be nullable"
    end
    TemperCore.Test.assert(test, Temper.Orm.FieldDef.get_nullable(TemperCore.List.get(ts, 0)), fn_4)
    fn_5 = fn ->
      "updated_at should be nullable"
    end
    TemperCore.Test.assert(test, Temper.Orm.FieldDef.get_nullable(TemperCore.List.get(ts, 1)), fn_5)
    fn_6 = fn ->
      "inserted_at should have default"
    end
    TemperCore.Test.assert(test, not (Temper.Orm.FieldDef.get_defaultValue(TemperCore.List.get(ts, 0)) === nil), fn_6)
    fn_7 = fn ->
      "updated_at should have default"
    end
    TemperCore.Test.assert(test, not (Temper.Orm.FieldDef.get_defaultValue(TemperCore.List.get(ts, 1)) === nil), fn_7)
    nil
  end
  def fieldDefDefaultValueField(test) do
    _t1 = nil
    _t2 = nil
    t1 = try do
      t1 = Temper.Orm.safeIdentifier("status")
      t1
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    withDefault = Temper.Orm.FieldDef.new(t1, Temper.Orm.StringField.new(), false, Temper.Orm.SqlDefault.new(), false)
    t2 = try do
      t2 = Temper.Orm.safeIdentifier("name")
      t2
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    withoutDefault = Temper.Orm.FieldDef.new(t2, Temper.Orm.StringField.new(), false, nil, false)
    fn_1 = fn ->
      "should have default"
    end
    TemperCore.Test.assert(test, not (Temper.Orm.FieldDef.get_defaultValue(withDefault) === nil), fn_1)
    fn_2 = fn ->
      "should not have default"
    end
    TemperCore.Test.assert(test, Temper.Orm.FieldDef.get_defaultValue(withoutDefault) === nil, fn_2)
    nil
  end
  def fieldDefVirtualFlag(test) do
    _t1 = nil
    _t2 = nil
    t1 = try do
      t1 = Temper.Orm.safeIdentifier("name")
      t1
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    normal = Temper.Orm.FieldDef.new(t1, Temper.Orm.StringField.new(), false, nil, false)
    t2 = try do
      t2 = Temper.Orm.safeIdentifier("full_name")
      t2
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    virt = Temper.Orm.FieldDef.new(t2, Temper.Orm.StringField.new(), true, nil, true)
    fn_1 = fn ->
      "normal field should not be virtual"
    end
    TemperCore.Test.assert(test, not Temper.Orm.FieldDef.get_virtual(normal), fn_1)
    fn_2 = fn ->
      "virtual field should be virtual"
    end
    TemperCore.Test.assert(test, Temper.Orm.FieldDef.get_virtual(virt), fn_2)
    nil
  end
  def safeIdentifierAcceptsSingleCharacterNames(test) do
    _a = nil
    a = try do
      a = Temper.Orm.safeIdentifier("a")
      a
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    fn_1 = fn ->
      "single letter should work"
    end
    TemperCore.Test.assert(test, TemperCore.call(a, :get_sqlValue, []) == "a", fn_1)
    _u = nil
    u = try do
      u = Temper.Orm.safeIdentifier("_")
      u
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    fn_2 = fn ->
      "single underscore should work"
    end
    TemperCore.Test.assert(test, TemperCore.call(u, :get_sqlValue, []) == "_", fn_2)
    nil
  end
  def safeIdentifierAcceptsAllUnderscoreNames(test) do
    _id = nil
    id = try do
      id = Temper.Orm.safeIdentifier("___")
      id
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    fn_ = fn ->
      "all underscores should work"
    end
    TemperCore.Test.assert(test, TemperCore.call(id, :get_sqlValue, []) == "___", fn_)
    nil
  end
  def tableDefWithEmptyFieldList(test) do
    _t = nil
    t = try do
      t = Temper.Orm.safeIdentifier("empty")
      t
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    tbl = Temper.Orm.TableDef.new(t, %TemperCore.Vec{t: {}}, nil)
    _didBubble = nil
    didBubble = try do
      Temper.Orm.TableDef.field(tbl, "anything")
      didBubble = false
      didBubble
    rescue
      _ in TemperCore.Bubble ->
        didBubble = true
        didBubble
    end
    fn_ = fn ->
      "field lookup on empty table should bubble"
    end
    TemperCore.Test.assert(test, didBubble, fn_)
    nil
  end
  def stringEscaping(test) do
    _build = fn name1 ->
      accumulator = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(accumulator, "select * from hi where name = ")
      Temper.Orm.SqlBuilder.appendString(accumulator, name1)
      Temper.Orm.SqlFragment.toString(Temper.Orm.SqlBuilder.get_accumulated(accumulator))
    end
    _buildWrong = fn name2 ->
      "select * from hi where name = '" <> name2 <> "'"
    end
    fn_1 = fn ->
      "expected build(\"world\") == (select * from hi where name = 'world') not (select * from hi where name = 'world')"
    end
    TemperCore.Test.assert(test, true, fn_1)
    _bobbyTables = "Robert'); drop table hi;--"
    fn_2 = fn ->
      "expected build(bobbyTables) == (select * from hi where name = 'Robert''); drop table hi;--') not (select * from hi where name = 'Robert''); drop table hi;--')"
    end
    TemperCore.Test.assert(test, true, fn_2)
    fn_3 = fn ->
      "expected buildWrong(bobbyTables) == (select * from hi where name = 'Robert'); drop table hi;--') not (select * from hi where name = 'Robert'); drop table hi;--')"
    end
    TemperCore.Test.assert(test, true, fn_3)
    nil
  end
  def stringEdgeCases(test) do
    accumulator1 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator1, "v = ")
    Temper.Orm.SqlBuilder.appendString(accumulator1, "")
    actual1 = Temper.Orm.SqlFragment.toString(Temper.Orm.SqlBuilder.get_accumulated(accumulator1))
    fn_1 = fn ->
      "expected stringExpr(`-work/alloy//src/`.sql, true, \"v = \", \\interpolate, \"\").toString() == (" <> "v = ''" <> ") not (" <> actual1 <> ")"
    end
    TemperCore.Test.assert(test, actual1 == "v = ''", fn_1)
    accumulator2 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator2, "v = ")
    Temper.Orm.SqlBuilder.appendString(accumulator2, "a''b")
    actual2 = Temper.Orm.SqlFragment.toString(Temper.Orm.SqlBuilder.get_accumulated(accumulator2))
    fn_2 = fn ->
      "expected stringExpr(`-work/alloy//src/`.sql, true, \"v = \", \\interpolate, \"a''b\").toString() == (" <> "v = 'a''''b'" <> ") not (" <> actual2 <> ")"
    end
    TemperCore.Test.assert(test, actual2 == "v = 'a''''b'", fn_2)
    accumulator3 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator3, "v = ")
    Temper.Orm.SqlBuilder.appendString(accumulator3, "Hello 世界")
    actual3 = Temper.Orm.SqlFragment.toString(Temper.Orm.SqlBuilder.get_accumulated(accumulator3))
    fn_3 = fn ->
      "expected stringExpr(`-work/alloy//src/`.sql, true, \"v = \", \\interpolate, \"Hello 世界\").toString() == (" <> "v = 'Hello 世界'" <> ") not (" <> actual3 <> ")"
    end
    TemperCore.Test.assert(test, actual3 == "v = 'Hello 世界'", fn_3)
    accumulator4 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator4, "v = ")
    Temper.Orm.SqlBuilder.appendString(accumulator4, "Line1\nLine2")
    actual4 = Temper.Orm.SqlFragment.toString(Temper.Orm.SqlBuilder.get_accumulated(accumulator4))
    fn_4 = fn ->
      "expected stringExpr(`-work/alloy//src/`.sql, true, \"v = \", \\interpolate, \"Line1\\nLine2\").toString() == (" <> "v = 'Line1\nLine2'" <> ") not (" <> actual4 <> ")"
    end
    TemperCore.Test.assert(test, actual4 == "v = 'Line1\nLine2'", fn_4)
    nil
  end
  def numbersAndBooleans(test) do
    accumulator1 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator1, "select ")
    Temper.Orm.SqlBuilder.appendInt32(accumulator1, 42)
    Temper.Orm.SqlBuilder.appendSafe(accumulator1, ", ")
    Temper.Orm.SqlBuilder.appendInt64(accumulator1, 43)
    Temper.Orm.SqlBuilder.appendSafe(accumulator1, ", ")
    Temper.Orm.SqlBuilder.appendFloat64(accumulator1, 19.99)
    Temper.Orm.SqlBuilder.appendSafe(accumulator1, ", ")
    Temper.Orm.SqlBuilder.appendBoolean(accumulator1, true)
    Temper.Orm.SqlBuilder.appendSafe(accumulator1, ", ")
    Temper.Orm.SqlBuilder.appendBoolean(accumulator1, false)
    actual1 = Temper.Orm.SqlFragment.toString(Temper.Orm.SqlBuilder.get_accumulated(accumulator1))
    fn_1 = fn ->
      "expected stringExpr(`-work/alloy//src/`.sql, true, \"select \", \\interpolate, 42, \", \", \\interpolate, 43, \", \", \\interpolate, 19.99, \", \", \\interpolate, true, \", \", \\interpolate, false).toString() == (" <> "select 42, 43, 19.99, TRUE, FALSE" <> ") not (" <> actual1 <> ")"
    end
    TemperCore.Test.assert(test, actual1 == "select 42, 43, 19.99, TRUE, FALSE", fn_1)
    _date = nil
    date = try do
      date = Temper.Std.Date.new(2024, 12, 25)
      date
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    accumulator2 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator2, "insert into t values (")
    Temper.Orm.SqlBuilder.appendDate(accumulator2, date)
    Temper.Orm.SqlBuilder.appendSafe(accumulator2, ")")
    actual2 = Temper.Orm.SqlFragment.toString(Temper.Orm.SqlBuilder.get_accumulated(accumulator2))
    fn_2 = fn ->
      "expected stringExpr(`-work/alloy//src/`.sql, true, \"insert into t values (\", \\interpolate, date, \")\").toString() == (" <> "insert into t values ('2024-12-25')" <> ") not (" <> actual2 <> ")"
    end
    TemperCore.Test.assert(test, actual2 == "insert into t values ('2024-12-25')", fn_2)
    nil
  end
  def lists(test) do
    _t1 = nil
    _t2 = nil
    accumulator1 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator1, "v IN (")
    Temper.Orm.SqlBuilder.appendStringList(accumulator1, %TemperCore.Vec{t: {"a", "b", "c'd"}})
    Temper.Orm.SqlBuilder.appendSafe(accumulator1, ")")
    actual1 = Temper.Orm.SqlFragment.toString(Temper.Orm.SqlBuilder.get_accumulated(accumulator1))
    fn_1 = fn ->
      "expected stringExpr(`-work/alloy//src/`.sql, true, \"v IN (\", \\interpolate, list(\"a\", \"b\", \"c'd\"), \")\").toString() == (" <> "v IN ('a', 'b', 'c''d')" <> ") not (" <> actual1 <> ")"
    end
    TemperCore.Test.assert(test, actual1 == "v IN ('a', 'b', 'c''d')", fn_1)
    accumulator2 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator2, "v IN (")
    Temper.Orm.SqlBuilder.appendInt32List(accumulator2, %TemperCore.Vec{t: {1, 2, 3}})
    Temper.Orm.SqlBuilder.appendSafe(accumulator2, ")")
    actual2 = Temper.Orm.SqlFragment.toString(Temper.Orm.SqlBuilder.get_accumulated(accumulator2))
    fn_2 = fn ->
      "expected stringExpr(`-work/alloy//src/`.sql, true, \"v IN (\", \\interpolate, list(1, 2, 3), \")\").toString() == (" <> "v IN (1, 2, 3)" <> ") not (" <> actual2 <> ")"
    end
    TemperCore.Test.assert(test, actual2 == "v IN (1, 2, 3)", fn_2)
    accumulator3 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator3, "v IN (")
    Temper.Orm.SqlBuilder.appendInt64List(accumulator3, %TemperCore.Vec{t: {1, 2}})
    Temper.Orm.SqlBuilder.appendSafe(accumulator3, ")")
    actual3 = Temper.Orm.SqlFragment.toString(Temper.Orm.SqlBuilder.get_accumulated(accumulator3))
    fn_3 = fn ->
      "expected stringExpr(`-work/alloy//src/`.sql, true, \"v IN (\", \\interpolate, list(1, 2), \")\").toString() == (" <> "v IN (1, 2)" <> ") not (" <> actual3 <> ")"
    end
    TemperCore.Test.assert(test, actual3 == "v IN (1, 2)", fn_3)
    accumulator4 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator4, "v IN (")
    Temper.Orm.SqlBuilder.appendFloat64List(accumulator4, %TemperCore.Vec{t: {1.0, 2.0}})
    Temper.Orm.SqlBuilder.appendSafe(accumulator4, ")")
    actual4 = Temper.Orm.SqlFragment.toString(Temper.Orm.SqlBuilder.get_accumulated(accumulator4))
    fn_4 = fn ->
      "expected stringExpr(`-work/alloy//src/`.sql, true, \"v IN (\", \\interpolate, list(1.0, 2.0), \")\").toString() == (" <> "v IN (1.0, 2.0)" <> ") not (" <> actual4 <> ")"
    end
    TemperCore.Test.assert(test, actual4 == "v IN (1.0, 2.0)", fn_4)
    accumulator5 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator5, "v IN (")
    Temper.Orm.SqlBuilder.appendBooleanList(accumulator5, %TemperCore.Vec{t: {true, false}})
    Temper.Orm.SqlBuilder.appendSafe(accumulator5, ")")
    actual5 = Temper.Orm.SqlFragment.toString(Temper.Orm.SqlBuilder.get_accumulated(accumulator5))
    fn_5 = fn ->
      "expected stringExpr(`-work/alloy//src/`.sql, true, \"v IN (\", \\interpolate, list(true, false), \")\").toString() == (" <> "v IN (TRUE, FALSE)" <> ") not (" <> actual5 <> ")"
    end
    TemperCore.Test.assert(test, actual5 == "v IN (TRUE, FALSE)", fn_5)
    t1 = try do
      t1 = Temper.Std.Date.new(2024, 1, 1)
      t1
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    t2 = try do
      t2 = Temper.Std.Date.new(2024, 12, 25)
      t2
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    dates = %TemperCore.Vec{t: {t1, t2}}
    accumulator6 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator6, "v IN (")
    Temper.Orm.SqlBuilder.appendDateList(accumulator6, dates)
    Temper.Orm.SqlBuilder.appendSafe(accumulator6, ")")
    actual6 = Temper.Orm.SqlFragment.toString(Temper.Orm.SqlBuilder.get_accumulated(accumulator6))
    fn_6 = fn ->
      "expected stringExpr(`-work/alloy//src/`.sql, true, \"v IN (\", \\interpolate, dates, \")\").toString() == (" <> "v IN ('2024-01-01', '2024-12-25')" <> ") not (" <> actual6 <> ")"
    end
    TemperCore.Test.assert(test, actual6 == "v IN ('2024-01-01', '2024-12-25')", fn_6)
    nil
  end
  def sqlFloat64_naNRendersAsNull(test) do
    _nan = :nan
    accumulator = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator, "v = ")
    Temper.Orm.SqlBuilder.appendFloat64(accumulator, :nan)
    actual = Temper.Orm.SqlFragment.toString(Temper.Orm.SqlBuilder.get_accumulated(accumulator))
    fn_ = fn ->
      "expected stringExpr(`-work/alloy//src/`.sql, true, \"v = \", \\interpolate, nan).toString() == (" <> "v = NULL" <> ") not (" <> actual <> ")"
    end
    TemperCore.Test.assert(test, actual == "v = NULL", fn_)
    nil
  end
  def sqlFloat64_infinityRendersAsNull(test) do
    _inf = :infinity
    accumulator = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator, "v = ")
    Temper.Orm.SqlBuilder.appendFloat64(accumulator, :infinity)
    actual = Temper.Orm.SqlFragment.toString(Temper.Orm.SqlBuilder.get_accumulated(accumulator))
    fn_ = fn ->
      "expected stringExpr(`-work/alloy//src/`.sql, true, \"v = \", \\interpolate, inf).toString() == (" <> "v = NULL" <> ") not (" <> actual <> ")"
    end
    TemperCore.Test.assert(test, actual == "v = NULL", fn_)
    nil
  end
  def sqlFloat64_negativeInfinityRendersAsNull(test) do
    _ninf = :neg_infinity
    accumulator = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator, "v = ")
    Temper.Orm.SqlBuilder.appendFloat64(accumulator, :neg_infinity)
    actual = Temper.Orm.SqlFragment.toString(Temper.Orm.SqlBuilder.get_accumulated(accumulator))
    fn_ = fn ->
      "expected stringExpr(`-work/alloy//src/`.sql, true, \"v = \", \\interpolate, ninf).toString() == (" <> "v = NULL" <> ") not (" <> actual <> ")"
    end
    TemperCore.Test.assert(test, actual == "v = NULL", fn_)
    nil
  end
  def sqlFloat64_normalValuesStillWork(test) do
    accumulator1 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator1, "v = ")
    Temper.Orm.SqlBuilder.appendFloat64(accumulator1, 3.14)
    actual1 = Temper.Orm.SqlFragment.toString(Temper.Orm.SqlBuilder.get_accumulated(accumulator1))
    fn_1 = fn ->
      "expected stringExpr(`-work/alloy//src/`.sql, true, \"v = \", \\interpolate, 3.14).toString() == (" <> "v = 3.14" <> ") not (" <> actual1 <> ")"
    end
    TemperCore.Test.assert(test, actual1 == "v = 3.14", fn_1)
    accumulator2 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator2, "v = ")
    Temper.Orm.SqlBuilder.appendFloat64(accumulator2, 0.0)
    actual2 = Temper.Orm.SqlFragment.toString(Temper.Orm.SqlBuilder.get_accumulated(accumulator2))
    fn_2 = fn ->
      "expected stringExpr(`-work/alloy//src/`.sql, true, \"v = \", \\interpolate, 0.0).toString() == (" <> "v = 0.0" <> ") not (" <> actual2 <> ")"
    end
    TemperCore.Test.assert(test, actual2 == "v = 0.0", fn_2)
    accumulator3 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator3, "v = ")
    Temper.Orm.SqlBuilder.appendFloat64(accumulator3, -42.5)
    actual3 = Temper.Orm.SqlFragment.toString(Temper.Orm.SqlBuilder.get_accumulated(accumulator3))
    fn_3 = fn ->
      "expected stringExpr(`-work/alloy//src/`.sql, true, \"v = \", \\interpolate, -42.5).toString() == (" <> "v = -42.5" <> ") not (" <> actual3 <> ")"
    end
    TemperCore.Test.assert(test, actual3 == "v = -42.5", fn_3)
    nil
  end
  def sqlDateRendersWithQuotes(test) do
    _d = nil
    d = try do
      d = Temper.Std.Date.new(2024, 6, 15)
      d
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    accumulator = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator, "v = ")
    Temper.Orm.SqlBuilder.appendDate(accumulator, d)
    actual = Temper.Orm.SqlFragment.toString(Temper.Orm.SqlBuilder.get_accumulated(accumulator))
    fn_ = fn ->
      "expected stringExpr(`-work/alloy//src/`.sql, true, \"v = \", \\interpolate, d).toString() == (" <> "v = '2024-06-15'" <> ") not (" <> actual <> ")"
    end
    TemperCore.Test.assert(test, actual == "v = '2024-06-15'", fn_)
    nil
  end
  def nesting(test) do
    _name = "Someone"
    accumulator1 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator1, "where p.last_name = ")
    Temper.Orm.SqlBuilder.appendString(accumulator1, "Someone")
    condition = Temper.Orm.SqlBuilder.get_accumulated(accumulator1)
    accumulator2 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator2, "select p.id from person p ")
    Temper.Orm.SqlBuilder.appendFragment(accumulator2, condition)
    actual1 = Temper.Orm.SqlFragment.toString(Temper.Orm.SqlBuilder.get_accumulated(accumulator2))
    fn_1 = fn ->
      "expected stringExpr(`-work/alloy//src/`.sql, true, \"select p.id from person p \", \\interpolate, condition).toString() == (" <> "select p.id from person p where p.last_name = 'Someone'" <> ") not (" <> actual1 <> ")"
    end
    TemperCore.Test.assert(test, actual1 == "select p.id from person p where p.last_name = 'Someone'", fn_1)
    accumulator3 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator3, "select p.id from person p ")
    Temper.Orm.SqlBuilder.appendPart(accumulator3, Temper.Orm.SqlFragment.toSource(condition))
    actual2 = Temper.Orm.SqlFragment.toString(Temper.Orm.SqlBuilder.get_accumulated(accumulator3))
    fn_2 = fn ->
      "expected stringExpr(`-work/alloy//src/`.sql, true, \"select p.id from person p \", \\interpolate, condition.toSource()).toString() == (" <> "select p.id from person p where p.last_name = 'Someone'" <> ") not (" <> actual2 <> ")"
    end
    TemperCore.Test.assert(test, actual2 == "select p.id from person p where p.last_name = 'Someone'", fn_2)
    parts = %TemperCore.Vec{t: {Temper.Orm.SqlString.new("a'b"), Temper.Orm.SqlInt32.new(3)}}
    accumulator4 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator4, "select ")
    Temper.Orm.SqlBuilder.appendPartList(accumulator4, parts)
    actual3 = Temper.Orm.SqlFragment.toString(Temper.Orm.SqlBuilder.get_accumulated(accumulator4))
    fn_3 = fn ->
      "expected stringExpr(`-work/alloy//src/`.sql, true, \"select \", \\interpolate, parts).toString() == (" <> "select 'a''b', 3" <> ") not (" <> actual3 <> ")"
    end
    TemperCore.Test.assert(test, actual3 == "select 'a''b', 3", fn_3)
    nil
  end
  def sqlInt32_negativeAndZeroValues(test) do
    accumulator1 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator1, "v = ")
    Temper.Orm.SqlBuilder.appendInt32(accumulator1, -42)
    t1 = Temper.Orm.SqlBuilder.get_accumulated(accumulator1)
    fn_1 = fn ->
      "negative int"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(t1) == "v = -42", fn_1)
    accumulator2 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator2, "v = ")
    Temper.Orm.SqlBuilder.appendInt32(accumulator2, 0)
    t2 = Temper.Orm.SqlBuilder.get_accumulated(accumulator2)
    fn_2 = fn ->
      "zero int"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(t2) == "v = 0", fn_2)
    nil
  end
  def sqlInt64_negativeValue(test) do
    accumulator = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator, "v = ")
    Temper.Orm.SqlBuilder.appendInt64(accumulator, -99)
    t = Temper.Orm.SqlBuilder.get_accumulated(accumulator)
    fn_ = fn ->
      "negative int64"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(t) == "v = -99", fn_)
    nil
  end
  def singleElementListRendering(test) do
    accumulator1 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator1, "v IN (")
    Temper.Orm.SqlBuilder.appendInt32List(accumulator1, %TemperCore.Vec{t: {42}})
    Temper.Orm.SqlBuilder.appendSafe(accumulator1, ")")
    t1 = Temper.Orm.SqlBuilder.get_accumulated(accumulator1)
    fn_1 = fn ->
      "single int"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(t1) == "v IN (42)", fn_1)
    accumulator2 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator2, "v IN (")
    Temper.Orm.SqlBuilder.appendStringList(accumulator2, %TemperCore.Vec{t: {"only"}})
    Temper.Orm.SqlBuilder.appendSafe(accumulator2, ")")
    t2 = Temper.Orm.SqlBuilder.get_accumulated(accumulator2)
    fn_2 = fn ->
      "single string"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(t2) == "v IN ('only')", fn_2)
    nil
  end
  def sqlDefaultRendersDefaultKeyword(test) do
    b = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(b, "v = ")
    Temper.Orm.SqlBuilder.appendPart(b, Temper.Orm.SqlDefault.new())
    fn_ = fn ->
      "default keyword"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(Temper.Orm.SqlBuilder.get_accumulated(b)) == "v = DEFAULT", fn_)
    nil
  end
  def sqlStringWithBackslash(test) do
    accumulator = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator, "v = ")
    Temper.Orm.SqlBuilder.appendString(accumulator, "a\\b")
    t = Temper.Orm.SqlBuilder.get_accumulated(accumulator)
    fn_ = fn ->
      "backslash passthrough"
    end
    TemperCore.Test.assert(test, Temper.Orm.SqlFragment.toString(t) == "v = 'a\\b'", fn_)
    nil
  end
  def toParameterizedNumbersTheValuesAndKeepsThemOutOfTheText(test) do
    _name = "O'Brien; drop table people"
    accumulator = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator, "select * from people where name = ")
    Temper.Orm.SqlBuilder.appendString(accumulator, "O'Brien; drop table people")
    Temper.Orm.SqlBuilder.appendSafe(accumulator, " and age > ")
    Temper.Orm.SqlBuilder.appendInt32(accumulator, 30)
    Temper.Orm.SqlBuilder.appendSafe(accumulator, " and height < ")
    Temper.Orm.SqlBuilder.appendFloat64(accumulator, 1.5)
    p = Temper.Orm.SqlFragment.toParameterized(Temper.Orm.SqlBuilder.get_accumulated(accumulator))
    fn_1 = fn ->
      Temper.Orm.ParameterizedSql.get_text(p)
    end
    TemperCore.Test.assert(test, Temper.Orm.ParameterizedSql.get_text(p) == "select * from people where name = $1 and age > $2 and height < $3", fn_1)
    fn_2 = fn ->
      "three params"
    end
    TemperCore.Test.assert(test, TemperCore.List.length(Temper.Orm.ParameterizedSql.get_params(p)) == 3, fn_2)
    fn_3 = fn ->
      TemperCore.List.get(Temper.Orm.ParameterizedSql.get_params(p), 0)
    end
    TemperCore.Test.assert(test, TemperCore.List.get(Temper.Orm.ParameterizedSql.get_params(p), 0) == "O'Brien; drop table people", fn_3)
    fn_4 = fn ->
      TemperCore.List.get(Temper.Orm.ParameterizedSql.get_params(p), 1)
    end
    TemperCore.Test.assert(test, TemperCore.List.get(Temper.Orm.ParameterizedSql.get_params(p), 1) == "30", fn_4)
    fn_5 = fn ->
      TemperCore.List.get(Temper.Orm.ParameterizedSql.get_params(p), 2)
    end
    TemperCore.Test.assert(test, TemperCore.List.get(Temper.Orm.ParameterizedSql.get_params(p), 2) == "1.5", fn_5)
    nil
  end
  def toParameterizedLeavesWhatIsNotDataInTheText(test) do
    _t = nil
    b = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(b, "insert into t (a, b, c, d) values (")
    Temper.Orm.SqlBuilder.appendBoolean(b, true)
    Temper.Orm.SqlBuilder.appendSafe(b, ", ")
    Temper.Orm.SqlBuilder.appendPart(b, Temper.Orm.SqlDefault.new())
    Temper.Orm.SqlBuilder.appendSafe(b, ", ")
    Temper.Orm.SqlBuilder.appendFloat64(b, :nan)
    Temper.Orm.SqlBuilder.appendSafe(b, ", ")
    Temper.Orm.SqlBuilder.appendInt64(b, -7)
    Temper.Orm.SqlBuilder.appendSafe(b, ")")
    p = Temper.Orm.SqlFragment.toParameterized(Temper.Orm.SqlBuilder.get_accumulated(b))
    fn_1 = fn ->
      Temper.Orm.ParameterizedSql.get_text(p)
    end
    TemperCore.Test.assert(test, Temper.Orm.ParameterizedSql.get_text(p) == "insert into t (a, b, c, d) values (TRUE, DEFAULT, NULL, $1)", fn_1)
    t = if TemperCore.List.length(Temper.Orm.ParameterizedSql.get_params(p)) == 1 do
      t = TemperCore.List.get(Temper.Orm.ParameterizedSql.get_params(p), 0) == "-7"
      t
    else
      t = false
      t
    end
    fn_2 = fn ->
      "one param"
    end
    TemperCore.Test.assert(test, t, fn_2)
    nil
  end
  def toParameterizedWorksOnAWholeQuery(test) do
    _t1 = nil
    _t2 = nil
    t1 = try do
      t1 = Temper.Orm.safeIdentifier("users")
      t1
    rescue
      _ in TemperCore.Bubble ->
        raise(TemperCore.Panic)
    end
    t3 = Temper.Orm.from(t1)
    accumulator1 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator1, "email = ")
    Temper.Orm.SqlBuilder.appendString(accumulator1, "a@b.c")
    t4 = Temper.Orm.Query.where(t3, Temper.Orm.SqlBuilder.get_accumulated(accumulator1))
    accumulator2 = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator2, "id = ")
    Temper.Orm.SqlBuilder.appendInt32(accumulator2, 7)
    p = Temper.Orm.SqlFragment.toParameterized(Temper.Orm.Query.toSql(Temper.Orm.Query.orWhere(t4, Temper.Orm.SqlBuilder.get_accumulated(accumulator2))))
    fn_1 = fn ->
      Temper.Orm.ParameterizedSql.get_text(p)
    end
    TemperCore.Test.assert(test, Temper.Orm.ParameterizedSql.get_text(p) == "SELECT * FROM users WHERE email = $1 OR id = $2", fn_1)
    t2 = if TemperCore.List.get(Temper.Orm.ParameterizedSql.get_params(p), 0) == "a@b.c" do
      t2 = TemperCore.List.get(Temper.Orm.ParameterizedSql.get_params(p), 1) == "7"
      t2
    else
      t2 = false
      t2
    end
    fn_2 = fn ->
      "params in order"
    end
    TemperCore.Test.assert(test, t2, fn_2)
    nil
  end
  def toParameterizedWithNoValuesIsTheSameTextAsToString(test) do
    accumulator = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator, "select 1")
    f = Temper.Orm.SqlBuilder.get_accumulated(accumulator)
    actual1 = Temper.Orm.ParameterizedSql.get_text(Temper.Orm.SqlFragment.toParameterized(f))
    expected = Temper.Orm.SqlFragment.toString(f)
    fn_1 = fn ->
      "expected f.toParameterized().text == (" <> expected <> ") not (" <> actual1 <> ")"
    end
    TemperCore.Test.assert(test, actual1 == expected, fn_1)
    actual2 = TemperCore.List.length(Temper.Orm.ParameterizedSql.get_params(Temper.Orm.SqlFragment.toParameterized(f)))
    fn_2 = fn ->
      "expected f.toParameterized().params.length == (" <> TemperCore.int_to_string(0) <> ") not (" <> TemperCore.int_to_string(actual2) <> ")"
    end
    TemperCore.Test.assert(test, actual2 == 0, fn_2)
    nil
  end
  def __temper_init__() do
    TemperCore.init_once(:"Temper.Orm.Tests", fn ->
      Temper.Orm.__temper_init__()
      nil
    end)
  end
  def __temper_tests__() do
    Temper.Orm.Tests.__temper_init__()
    TemperCore.Test.run_cases([TemperCore.Pair.new("castWhitelistsAllowedFields", &Temper.Orm.Tests.castWhitelistsAllowedFields/1), TemperCore.Pair.new("castIsReplacingNotAdditiveSecondCallResetsWhitelist", &Temper.Orm.Tests.castIsReplacingNotAdditiveSecondCallResetsWhitelist/1), TemperCore.Pair.new("castIgnoresEmptyStringValues", &Temper.Orm.Tests.castIgnoresEmptyStringValues/1), TemperCore.Pair.new("validateRequiredPassesWhenFieldPresent", &Temper.Orm.Tests.validateRequiredPassesWhenFieldPresent/1), TemperCore.Pair.new("validateRequiredFailsWhenFieldMissing", &Temper.Orm.Tests.validateRequiredFailsWhenFieldMissing/1), TemperCore.Pair.new("validateLengthPassesWithinRange", &Temper.Orm.Tests.validateLengthPassesWithinRange/1), TemperCore.Pair.new("validateLengthFailsWhenTooShort", &Temper.Orm.Tests.validateLengthFailsWhenTooShort/1), TemperCore.Pair.new("validateLengthFailsWhenTooLong", &Temper.Orm.Tests.validateLengthFailsWhenTooLong/1), TemperCore.Pair.new("validateIntPassesForValidInteger", &Temper.Orm.Tests.validateIntPassesForValidInteger/1), TemperCore.Pair.new("validateIntFailsForNonInteger", &Temper.Orm.Tests.validateIntFailsForNonInteger/1), TemperCore.Pair.new("validateFloatPassesForValidFloat", &Temper.Orm.Tests.validateFloatPassesForValidFloat/1), TemperCore.Pair.new("validateInt64_passesForValid64_bitInteger", &Temper.Orm.Tests.validateInt64_passesForValid64_bitInteger/1), TemperCore.Pair.new("validateInt64_failsForNonInteger", &Temper.Orm.Tests.validateInt64_failsForNonInteger/1), TemperCore.Pair.new("validateBoolAcceptsTrue1_yesOn", &Temper.Orm.Tests.validateBoolAcceptsTrue1_yesOn/1), TemperCore.Pair.new("validateBoolAcceptsFalse0_noOff", &Temper.Orm.Tests.validateBoolAcceptsFalse0_noOff/1), TemperCore.Pair.new("validateBoolRejectsAmbiguousValues", &Temper.Orm.Tests.validateBoolRejectsAmbiguousValues/1), TemperCore.Pair.new("toInsertSqlEscapesBobbyTables", &Temper.Orm.Tests.toInsertSqlEscapesBobbyTables/1), TemperCore.Pair.new("toInsertSqlProducesCorrectSqlForStringField", &Temper.Orm.Tests.toInsertSqlProducesCorrectSqlForStringField/1), TemperCore.Pair.new("toInsertSqlProducesCorrectSqlForIntField", &Temper.Orm.Tests.toInsertSqlProducesCorrectSqlForIntField/1), TemperCore.Pair.new("toInsertSqlBubblesOnInvalidChangeset", &Temper.Orm.Tests.toInsertSqlBubblesOnInvalidChangeset/1), TemperCore.Pair.new("toInsertSqlEnforcesNonNullableFieldsIndependentlyOfIsValid", &Temper.Orm.Tests.toInsertSqlEnforcesNonNullableFieldsIndependentlyOfIsValid/1), TemperCore.Pair.new("toUpdateSqlProducesCorrectSql", &Temper.Orm.Tests.toUpdateSqlProducesCorrectSql/1), TemperCore.Pair.new("toUpdateSqlBubblesOnInvalidChangeset", &Temper.Orm.Tests.toUpdateSqlBubblesOnInvalidChangeset/1), TemperCore.Pair.new("putChangeAddsANewField", &Temper.Orm.Tests.putChangeAddsANewField/1), TemperCore.Pair.new("putChangeOverwritesExistingField", &Temper.Orm.Tests.putChangeOverwritesExistingField/1), TemperCore.Pair.new("putChangeValueAppearsInToInsertSql", &Temper.Orm.Tests.putChangeValueAppearsInToInsertSql/1), TemperCore.Pair.new("getChangeReturnsValueForExistingField", &Temper.Orm.Tests.getChangeReturnsValueForExistingField/1), TemperCore.Pair.new("getChangeBubblesOnMissingField", &Temper.Orm.Tests.getChangeBubblesOnMissingField/1), TemperCore.Pair.new("deleteChangeRemovesField", &Temper.Orm.Tests.deleteChangeRemovesField/1), TemperCore.Pair.new("deleteChangeOnNonexistentFieldIsNoOp", &Temper.Orm.Tests.deleteChangeOnNonexistentFieldIsNoOp/1), TemperCore.Pair.new("validateInclusionPassesWhenValueInList", &Temper.Orm.Tests.validateInclusionPassesWhenValueInList/1), TemperCore.Pair.new("validateInclusionFailsWhenValueNotInList", &Temper.Orm.Tests.validateInclusionFailsWhenValueNotInList/1), TemperCore.Pair.new("validateInclusionSkipsWhenFieldNotInChanges", &Temper.Orm.Tests.validateInclusionSkipsWhenFieldNotInChanges/1), TemperCore.Pair.new("validateExclusionPassesWhenValueNotInList", &Temper.Orm.Tests.validateExclusionPassesWhenValueNotInList/1), TemperCore.Pair.new("validateExclusionFailsWhenValueInList", &Temper.Orm.Tests.validateExclusionFailsWhenValueInList/1), TemperCore.Pair.new("validateExclusionSkipsWhenFieldNotInChanges", &Temper.Orm.Tests.validateExclusionSkipsWhenFieldNotInChanges/1), TemperCore.Pair.new("validateNumberGreaterThanPasses", &Temper.Orm.Tests.validateNumberGreaterThanPasses/1), TemperCore.Pair.new("validateNumberGreaterThanFails", &Temper.Orm.Tests.validateNumberGreaterThanFails/1), TemperCore.Pair.new("validateNumberLessThanPasses", &Temper.Orm.Tests.validateNumberLessThanPasses/1), TemperCore.Pair.new("validateNumberLessThanFails", &Temper.Orm.Tests.validateNumberLessThanFails/1), TemperCore.Pair.new("validateNumberGreaterThanOrEqualBoundary", &Temper.Orm.Tests.validateNumberGreaterThanOrEqualBoundary/1), TemperCore.Pair.new("validateNumberCombinedOptions", &Temper.Orm.Tests.validateNumberCombinedOptions/1), TemperCore.Pair.new("validateNumberNonNumericValue", &Temper.Orm.Tests.validateNumberNonNumericValue/1), TemperCore.Pair.new("validateNumberSkipsWhenFieldNotInChanges", &Temper.Orm.Tests.validateNumberSkipsWhenFieldNotInChanges/1), TemperCore.Pair.new("validateAcceptancePassesForTrueValues", &Temper.Orm.Tests.validateAcceptancePassesForTrueValues/1), TemperCore.Pair.new("validateAcceptanceFailsForNonTrueValues", &Temper.Orm.Tests.validateAcceptanceFailsForNonTrueValues/1), TemperCore.Pair.new("validateConfirmationPassesWhenFieldsMatch", &Temper.Orm.Tests.validateConfirmationPassesWhenFieldsMatch/1), TemperCore.Pair.new("validateConfirmationFailsWhenFieldsDiffer", &Temper.Orm.Tests.validateConfirmationFailsWhenFieldsDiffer/1), TemperCore.Pair.new("validateConfirmationFailsWhenConfirmationMissing", &Temper.Orm.Tests.validateConfirmationFailsWhenConfirmationMissing/1), TemperCore.Pair.new("validateContainsPassesWhenSubstringFound", &Temper.Orm.Tests.validateContainsPassesWhenSubstringFound/1), TemperCore.Pair.new("validateContainsFailsWhenSubstringNotFound", &Temper.Orm.Tests.validateContainsFailsWhenSubstringNotFound/1), TemperCore.Pair.new("validateContainsSkipsWhenFieldNotInChanges", &Temper.Orm.Tests.validateContainsSkipsWhenFieldNotInChanges/1), TemperCore.Pair.new("validateStartsWithPasses", &Temper.Orm.Tests.validateStartsWithPasses/1), TemperCore.Pair.new("validateStartsWithFails", &Temper.Orm.Tests.validateStartsWithFails/1), TemperCore.Pair.new("validateEndsWithPasses", &Temper.Orm.Tests.validateEndsWithPasses/1), TemperCore.Pair.new("validateEndsWithFails", &Temper.Orm.Tests.validateEndsWithFails/1), TemperCore.Pair.new("validateEndsWithHandlesRepeatedSuffixCorrectly", &Temper.Orm.Tests.validateEndsWithHandlesRepeatedSuffixCorrectly/1), TemperCore.Pair.new("toInsertSqlUsesDefaultValueWhenFieldNotInChanges", &Temper.Orm.Tests.toInsertSqlUsesDefaultValueWhenFieldNotInChanges/1), TemperCore.Pair.new("toInsertSqlChangeOverridesDefaultValue", &Temper.Orm.Tests.toInsertSqlChangeOverridesDefaultValue/1), TemperCore.Pair.new("toInsertSqlWithTimestampsUsesDefault", &Temper.Orm.Tests.toInsertSqlWithTimestampsUsesDefault/1), TemperCore.Pair.new("toInsertSqlSkipsVirtualFields", &Temper.Orm.Tests.toInsertSqlSkipsVirtualFields/1), TemperCore.Pair.new("toInsertSqlAllowsMissingNonNullableVirtualField", &Temper.Orm.Tests.toInsertSqlAllowsMissingNonNullableVirtualField/1), TemperCore.Pair.new("toUpdateSqlSkipsVirtualFields", &Temper.Orm.Tests.toUpdateSqlSkipsVirtualFields/1), TemperCore.Pair.new("toUpdateSqlUsesCustomPrimaryKey", &Temper.Orm.Tests.toUpdateSqlUsesCustomPrimaryKey/1), TemperCore.Pair.new("deleteSqlUsesCustomPrimaryKey", &Temper.Orm.Tests.deleteSqlUsesCustomPrimaryKey/1), TemperCore.Pair.new("deleteSqlUsesDefaultIdWhenPrimaryKeyNull", &Temper.Orm.Tests.deleteSqlUsesDefaultIdWhenPrimaryKeyNull/1), TemperCore.Pair.new("alreadyInvalidChangesetSkipsSubsequentValidators", &Temper.Orm.Tests.alreadyInvalidChangesetSkipsSubsequentValidators/1), TemperCore.Pair.new("validateNumberLessThanOrEqualPassesAtBoundary", &Temper.Orm.Tests.validateNumberLessThanOrEqualPassesAtBoundary/1), TemperCore.Pair.new("validateNumberLessThanOrEqualFailsAboveBoundary", &Temper.Orm.Tests.validateNumberLessThanOrEqualFailsAboveBoundary/1), TemperCore.Pair.new("validateNumberEqualToPassesWhenEqual", &Temper.Orm.Tests.validateNumberEqualToPassesWhenEqual/1), TemperCore.Pair.new("validateNumberEqualToFailsWhenNotEqual", &Temper.Orm.Tests.validateNumberEqualToFailsWhenNotEqual/1), TemperCore.Pair.new("validateNumberGreaterThanFailsAtExactThreshold", &Temper.Orm.Tests.validateNumberGreaterThanFailsAtExactThreshold/1), TemperCore.Pair.new("validateNumberLessThanFailsAtExactThreshold", &Temper.Orm.Tests.validateNumberLessThanFailsAtExactThreshold/1), TemperCore.Pair.new("validateFloatFailsForNonFloatString", &Temper.Orm.Tests.validateFloatFailsForNonFloatString/1), TemperCore.Pair.new("toInsertSqlWithAllSixFieldTypes", &Temper.Orm.Tests.toInsertSqlWithAllSixFieldTypes/1), TemperCore.Pair.new("deleteChangeOnNonNullableFieldCausesToInsertSqlToBubble", &Temper.Orm.Tests.deleteChangeOnNonNullableFieldCausesToInsertSqlToBubble/1), TemperCore.Pair.new("validateLengthPassesAtExactMin", &Temper.Orm.Tests.validateLengthPassesAtExactMin/1), TemperCore.Pair.new("validateLengthPassesAtExactMax", &Temper.Orm.Tests.validateLengthPassesAtExactMax/1), TemperCore.Pair.new("validateAcceptanceSkipsWhenFieldNotInChanges", &Temper.Orm.Tests.validateAcceptanceSkipsWhenFieldNotInChanges/1), TemperCore.Pair.new("multipleValidatorsChainCorrectlyOnValidChangeset", &Temper.Orm.Tests.multipleValidatorsChainCorrectlyOnValidChangeset/1), TemperCore.Pair.new("toUpdateSqlWithMultipleNonVirtualFields", &Temper.Orm.Tests.toUpdateSqlWithMultipleNonVirtualFields/1), TemperCore.Pair.new("toUpdateSqlBubblesWhenAllChangesAreVirtualFields", &Temper.Orm.Tests.toUpdateSqlBubblesWhenAllChangesAreVirtualFields/1), TemperCore.Pair.new("putChangeSatisfiesSubsequentValidateRequired", &Temper.Orm.Tests.putChangeSatisfiesSubsequentValidateRequired/1), TemperCore.Pair.new("validateStartsWithSkipsWhenFieldNotInChanges", &Temper.Orm.Tests.validateStartsWithSkipsWhenFieldNotInChanges/1), TemperCore.Pair.new("validateEndsWithSkipsWhenFieldNotInChanges", &Temper.Orm.Tests.validateEndsWithSkipsWhenFieldNotInChanges/1), TemperCore.Pair.new("validateIntAcceptsZero", &Temper.Orm.Tests.validateIntAcceptsZero/1), TemperCore.Pair.new("validateIntAcceptsNegative", &Temper.Orm.Tests.validateIntAcceptsNegative/1), TemperCore.Pair.new("changesetImmutabilityValidatorsDoNotMutateBase", &Temper.Orm.Tests.changesetImmutabilityValidatorsDoNotMutateBase/1), TemperCore.Pair.new("bareFromProducesSelect", &Temper.Orm.Tests.bareFromProducesSelect/1), TemperCore.Pair.new("selectRestrictsColumns", &Temper.Orm.Tests.selectRestrictsColumns/1), TemperCore.Pair.new("whereAddsConditionWithIntValue", &Temper.Orm.Tests.whereAddsConditionWithIntValue/1), TemperCore.Pair.new("whereAddsConditionWithBoolValue", &Temper.Orm.Tests.whereAddsConditionWithBoolValue/1), TemperCore.Pair.new("chainedWhereUsesAnd", &Temper.Orm.Tests.chainedWhereUsesAnd/1), TemperCore.Pair.new("orderByAsc", &Temper.Orm.Tests.orderByAsc/1), TemperCore.Pair.new("orderByDesc", &Temper.Orm.Tests.orderByDesc/1), TemperCore.Pair.new("limitAndOffset", &Temper.Orm.Tests.limitAndOffset/1), TemperCore.Pair.new("limitBubblesOnNegative", &Temper.Orm.Tests.limitBubblesOnNegative/1), TemperCore.Pair.new("offsetBubblesOnNegative", &Temper.Orm.Tests.offsetBubblesOnNegative/1), TemperCore.Pair.new("complexComposedQuery", &Temper.Orm.Tests.complexComposedQuery/1), TemperCore.Pair.new("safeToSqlAppliesDefaultLimitWhenNoneSet", &Temper.Orm.Tests.safeToSqlAppliesDefaultLimitWhenNoneSet/1), TemperCore.Pair.new("safeToSqlRespectsExplicitLimit", &Temper.Orm.Tests.safeToSqlRespectsExplicitLimit/1), TemperCore.Pair.new("safeToSqlBubblesOnNegativeDefaultLimit", &Temper.Orm.Tests.safeToSqlBubblesOnNegativeDefaultLimit/1), TemperCore.Pair.new("whereWithInjectionAttemptInStringValueIsEscaped", &Temper.Orm.Tests.whereWithInjectionAttemptInStringValueIsEscaped/1), TemperCore.Pair.new("safeIdentifierRejectsUserSuppliedTableNameWithMetacharacters", &Temper.Orm.Tests.safeIdentifierRejectsUserSuppliedTableNameWithMetacharacters/1), TemperCore.Pair.new("innerJoinProducesInnerJoin", &Temper.Orm.Tests.innerJoinProducesInnerJoin/1), TemperCore.Pair.new("leftJoinProducesLeftJoin", &Temper.Orm.Tests.leftJoinProducesLeftJoin/1), TemperCore.Pair.new("rightJoinProducesRightJoin", &Temper.Orm.Tests.rightJoinProducesRightJoin/1), TemperCore.Pair.new("fullJoinProducesFullOuterJoin", &Temper.Orm.Tests.fullJoinProducesFullOuterJoin/1), TemperCore.Pair.new("chainedJoins", &Temper.Orm.Tests.chainedJoins/1), TemperCore.Pair.new("joinWithWhereAndOrderBy", &Temper.Orm.Tests.joinWithWhereAndOrderBy/1), TemperCore.Pair.new("colHelperProducesQualifiedReference", &Temper.Orm.Tests.colHelperProducesQualifiedReference/1), TemperCore.Pair.new("joinWithColHelper", &Temper.Orm.Tests.joinWithColHelper/1), TemperCore.Pair.new("orWhereBasic", &Temper.Orm.Tests.orWhereBasic/1), TemperCore.Pair.new("whereThenOrWhere", &Temper.Orm.Tests.whereThenOrWhere/1), TemperCore.Pair.new("multipleOrWhere", &Temper.Orm.Tests.multipleOrWhere/1), TemperCore.Pair.new("mixedWhereAndOrWhere", &Temper.Orm.Tests.mixedWhereAndOrWhere/1), TemperCore.Pair.new("whereNull", &Temper.Orm.Tests.whereNull/1), TemperCore.Pair.new("whereNotNull", &Temper.Orm.Tests.whereNotNull/1), TemperCore.Pair.new("whereNullChainedWithWhere", &Temper.Orm.Tests.whereNullChainedWithWhere/1), TemperCore.Pair.new("whereNotNullChainedWithOrWhere", &Temper.Orm.Tests.whereNotNullChainedWithOrWhere/1), TemperCore.Pair.new("whereInWithIntValues", &Temper.Orm.Tests.whereInWithIntValues/1), TemperCore.Pair.new("whereInWithStringValuesEscaping", &Temper.Orm.Tests.whereInWithStringValuesEscaping/1), TemperCore.Pair.new("whereInWithEmptyListProduces1_0", &Temper.Orm.Tests.whereInWithEmptyListProduces1_0/1), TemperCore.Pair.new("whereInChained", &Temper.Orm.Tests.whereInChained/1), TemperCore.Pair.new("whereInSingleElement", &Temper.Orm.Tests.whereInSingleElement/1), TemperCore.Pair.new("whereNotBasic", &Temper.Orm.Tests.whereNotBasic/1), TemperCore.Pair.new("whereNotChained", &Temper.Orm.Tests.whereNotChained/1), TemperCore.Pair.new("whereBetweenIntegers", &Temper.Orm.Tests.whereBetweenIntegers/1), TemperCore.Pair.new("whereBetweenChained", &Temper.Orm.Tests.whereBetweenChained/1), TemperCore.Pair.new("whereLikeBasic", &Temper.Orm.Tests.whereLikeBasic/1), TemperCore.Pair.new("whereIlikeBasic", &Temper.Orm.Tests.whereIlikeBasic/1), TemperCore.Pair.new("whereLikeWithInjectionAttempt", &Temper.Orm.Tests.whereLikeWithInjectionAttempt/1), TemperCore.Pair.new("whereLikeWildcardPatterns", &Temper.Orm.Tests.whereLikeWildcardPatterns/1), TemperCore.Pair.new("countAllProducesCount", &Temper.Orm.Tests.countAllProducesCount/1), TemperCore.Pair.new("countColProducesCountField", &Temper.Orm.Tests.countColProducesCountField/1), TemperCore.Pair.new("sumColProducesSumField", &Temper.Orm.Tests.sumColProducesSumField/1), TemperCore.Pair.new("avgColProducesAvgField", &Temper.Orm.Tests.avgColProducesAvgField/1), TemperCore.Pair.new("minColProducesMinField", &Temper.Orm.Tests.minColProducesMinField/1), TemperCore.Pair.new("maxColProducesMaxField", &Temper.Orm.Tests.maxColProducesMaxField/1), TemperCore.Pair.new("selectExprWithAggregate", &Temper.Orm.Tests.selectExprWithAggregate/1), TemperCore.Pair.new("selectExprWithMultipleExpressions", &Temper.Orm.Tests.selectExprWithMultipleExpressions/1), TemperCore.Pair.new("selectExprOverridesSelectedFields", &Temper.Orm.Tests.selectExprOverridesSelectedFields/1), TemperCore.Pair.new("groupBySingleField", &Temper.Orm.Tests.groupBySingleField/1), TemperCore.Pair.new("groupByMultipleFields", &Temper.Orm.Tests.groupByMultipleFields/1), TemperCore.Pair.new("havingBasic", &Temper.Orm.Tests.havingBasic/1), TemperCore.Pair.new("orHaving", &Temper.Orm.Tests.orHaving/1), TemperCore.Pair.new("distinctBasic", &Temper.Orm.Tests.distinctBasic/1), TemperCore.Pair.new("distinctWithWhere", &Temper.Orm.Tests.distinctWithWhere/1), TemperCore.Pair.new("countSqlBare", &Temper.Orm.Tests.countSqlBare/1), TemperCore.Pair.new("countSqlWithWhere", &Temper.Orm.Tests.countSqlWithWhere/1), TemperCore.Pair.new("countSqlWithJoin", &Temper.Orm.Tests.countSqlWithJoin/1), TemperCore.Pair.new("countSqlDropsOrderByLimitOffset", &Temper.Orm.Tests.countSqlDropsOrderByLimitOffset/1), TemperCore.Pair.new("fullAggregationQuery", &Temper.Orm.Tests.fullAggregationQuery/1), TemperCore.Pair.new("unionSql__2", &Temper.Orm.Tests.unionSql__2/1), TemperCore.Pair.new("unionAllSql__2", &Temper.Orm.Tests.unionAllSql__2/1), TemperCore.Pair.new("intersectSql__2", &Temper.Orm.Tests.intersectSql__2/1), TemperCore.Pair.new("exceptSql__2", &Temper.Orm.Tests.exceptSql__2/1), TemperCore.Pair.new("subqueryWithAlias", &Temper.Orm.Tests.subqueryWithAlias/1), TemperCore.Pair.new("existsSql__2", &Temper.Orm.Tests.existsSql__2/1), TemperCore.Pair.new("whereInSubquery", &Temper.Orm.Tests.whereInSubquery/1), TemperCore.Pair.new("setOperationWithWhereOnEachSide", &Temper.Orm.Tests.setOperationWithWhereOnEachSide/1), TemperCore.Pair.new("whereInSubqueryChainedWithWhere", &Temper.Orm.Tests.whereInSubqueryChainedWithWhere/1), TemperCore.Pair.new("existsSqlUsedInWhere", &Temper.Orm.Tests.existsSqlUsedInWhere/1), TemperCore.Pair.new("updateQueryBasic", &Temper.Orm.Tests.updateQueryBasic/1), TemperCore.Pair.new("updateQueryMultipleSet", &Temper.Orm.Tests.updateQueryMultipleSet/1), TemperCore.Pair.new("updateQueryMultipleWhere", &Temper.Orm.Tests.updateQueryMultipleWhere/1), TemperCore.Pair.new("updateQueryOrWhere", &Temper.Orm.Tests.updateQueryOrWhere/1), TemperCore.Pair.new("updateQueryBubblesWithoutWhere", &Temper.Orm.Tests.updateQueryBubblesWithoutWhere/1), TemperCore.Pair.new("updateQueryBubblesWithoutSet", &Temper.Orm.Tests.updateQueryBubblesWithoutSet/1), TemperCore.Pair.new("updateQueryWithLimit", &Temper.Orm.Tests.updateQueryWithLimit/1), TemperCore.Pair.new("updateQueryEscaping", &Temper.Orm.Tests.updateQueryEscaping/1), TemperCore.Pair.new("deleteQueryBasic", &Temper.Orm.Tests.deleteQueryBasic/1), TemperCore.Pair.new("deleteQueryMultipleWhere", &Temper.Orm.Tests.deleteQueryMultipleWhere/1), TemperCore.Pair.new("deleteQueryBubblesWithoutWhere", &Temper.Orm.Tests.deleteQueryBubblesWithoutWhere/1), TemperCore.Pair.new("deleteQueryOrWhere", &Temper.Orm.Tests.deleteQueryOrWhere/1), TemperCore.Pair.new("deleteQueryWithLimit", &Temper.Orm.Tests.deleteQueryWithLimit/1), TemperCore.Pair.new("orderByNullsNullsFirst", &Temper.Orm.Tests.orderByNullsNullsFirst/1), TemperCore.Pair.new("orderByNullsNullsLast", &Temper.Orm.Tests.orderByNullsNullsLast/1), TemperCore.Pair.new("mixedOrderByAndOrderByNulls", &Temper.Orm.Tests.mixedOrderByAndOrderByNulls/1), TemperCore.Pair.new("crossJoin", &Temper.Orm.Tests.crossJoin/1), TemperCore.Pair.new("crossJoinCombinedWithOtherJoins", &Temper.Orm.Tests.crossJoinCombinedWithOtherJoins/1), TemperCore.Pair.new("lockForUpdate", &Temper.Orm.Tests.lockForUpdate/1), TemperCore.Pair.new("lockForShare", &Temper.Orm.Tests.lockForShare/1), TemperCore.Pair.new("lockWithFullQuery", &Temper.Orm.Tests.lockWithFullQuery/1), TemperCore.Pair.new("queryBuilderImmutabilityTwoQueriesFromSameBase", &Temper.Orm.Tests.queryBuilderImmutabilityTwoQueriesFromSameBase/1), TemperCore.Pair.new("limitZeroProducesLimit0", &Temper.Orm.Tests.limitZeroProducesLimit0/1), TemperCore.Pair.new("safeToSqlWithZeroDefaultLimit", &Temper.Orm.Tests.safeToSqlWithZeroDefaultLimit/1), TemperCore.Pair.new("updateQueryLimitBubblesOnNegative", &Temper.Orm.Tests.updateQueryLimitBubblesOnNegative/1), TemperCore.Pair.new("deleteQueryLimitBubblesOnNegative", &Temper.Orm.Tests.deleteQueryLimitBubblesOnNegative/1), TemperCore.Pair.new("updateQueryImmutabilityTwoFromSameBase", &Temper.Orm.Tests.updateQueryImmutabilityTwoFromSameBase/1), TemperCore.Pair.new("deleteQueryImmutability", &Temper.Orm.Tests.deleteQueryImmutability/1), TemperCore.Pair.new("safeIdentifierAcceptsValidNames", &Temper.Orm.Tests.safeIdentifierAcceptsValidNames/1), TemperCore.Pair.new("safeIdentifierRejectsEmptyString", &Temper.Orm.Tests.safeIdentifierRejectsEmptyString/1), TemperCore.Pair.new("safeIdentifierRejectsLeadingDigit", &Temper.Orm.Tests.safeIdentifierRejectsLeadingDigit/1), TemperCore.Pair.new("safeIdentifierRejectsSqlMetacharacters", &Temper.Orm.Tests.safeIdentifierRejectsSqlMetacharacters/1), TemperCore.Pair.new("tableDefFieldLookupFound", &Temper.Orm.Tests.tableDefFieldLookupFound/1), TemperCore.Pair.new("tableDefFieldLookupNotFoundBubbles", &Temper.Orm.Tests.tableDefFieldLookupNotFoundBubbles/1), TemperCore.Pair.new("fieldDefNullableFlag", &Temper.Orm.Tests.fieldDefNullableFlag/1), TemperCore.Pair.new("pkNameDefaultsToIdWhenPrimaryKeyIsNull", &Temper.Orm.Tests.pkNameDefaultsToIdWhenPrimaryKeyIsNull/1), TemperCore.Pair.new("pkNameReturnsCustomPrimaryKey", &Temper.Orm.Tests.pkNameReturnsCustomPrimaryKey/1), TemperCore.Pair.new("timestampsReturnsTwoDateFieldDefs", &Temper.Orm.Tests.timestampsReturnsTwoDateFieldDefs/1), TemperCore.Pair.new("fieldDefDefaultValueField", &Temper.Orm.Tests.fieldDefDefaultValueField/1), TemperCore.Pair.new("fieldDefVirtualFlag", &Temper.Orm.Tests.fieldDefVirtualFlag/1), TemperCore.Pair.new("safeIdentifierAcceptsSingleCharacterNames", &Temper.Orm.Tests.safeIdentifierAcceptsSingleCharacterNames/1), TemperCore.Pair.new("safeIdentifierAcceptsAllUnderscoreNames", &Temper.Orm.Tests.safeIdentifierAcceptsAllUnderscoreNames/1), TemperCore.Pair.new("tableDefWithEmptyFieldList", &Temper.Orm.Tests.tableDefWithEmptyFieldList/1), TemperCore.Pair.new("stringEscaping", &Temper.Orm.Tests.stringEscaping/1), TemperCore.Pair.new("stringEdgeCases", &Temper.Orm.Tests.stringEdgeCases/1), TemperCore.Pair.new("numbersAndBooleans", &Temper.Orm.Tests.numbersAndBooleans/1), TemperCore.Pair.new("lists", &Temper.Orm.Tests.lists/1), TemperCore.Pair.new("sqlFloat64_naNRendersAsNull", &Temper.Orm.Tests.sqlFloat64_naNRendersAsNull/1), TemperCore.Pair.new("sqlFloat64_infinityRendersAsNull", &Temper.Orm.Tests.sqlFloat64_infinityRendersAsNull/1), TemperCore.Pair.new("sqlFloat64_negativeInfinityRendersAsNull", &Temper.Orm.Tests.sqlFloat64_negativeInfinityRendersAsNull/1), TemperCore.Pair.new("sqlFloat64_normalValuesStillWork", &Temper.Orm.Tests.sqlFloat64_normalValuesStillWork/1), TemperCore.Pair.new("sqlDateRendersWithQuotes", &Temper.Orm.Tests.sqlDateRendersWithQuotes/1), TemperCore.Pair.new("nesting", &Temper.Orm.Tests.nesting/1), TemperCore.Pair.new("sqlInt32_negativeAndZeroValues", &Temper.Orm.Tests.sqlInt32_negativeAndZeroValues/1), TemperCore.Pair.new("sqlInt64_negativeValue", &Temper.Orm.Tests.sqlInt64_negativeValue/1), TemperCore.Pair.new("singleElementListRendering", &Temper.Orm.Tests.singleElementListRendering/1), TemperCore.Pair.new("sqlDefaultRendersDefaultKeyword", &Temper.Orm.Tests.sqlDefaultRendersDefaultKeyword/1), TemperCore.Pair.new("sqlStringWithBackslash", &Temper.Orm.Tests.sqlStringWithBackslash/1), TemperCore.Pair.new("toParameterizedNumbersTheValuesAndKeepsThemOutOfTheText", &Temper.Orm.Tests.toParameterizedNumbersTheValuesAndKeepsThemOutOfTheText/1), TemperCore.Pair.new("toParameterizedLeavesWhatIsNotDataInTheText", &Temper.Orm.Tests.toParameterizedLeavesWhatIsNotDataInTheText/1), TemperCore.Pair.new("toParameterizedWorksOnAWholeQuery", &Temper.Orm.Tests.toParameterizedWorksOnAWholeQuery/1), TemperCore.Pair.new("toParameterizedWithNoValuesIsTheSameTextAsToString", &Temper.Orm.Tests.toParameterizedWithNoValuesIsTheSameTextAsToString/1)])
  end
end
