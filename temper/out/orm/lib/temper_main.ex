defmodule Temper.Orm.ChangesetError do
  def __temper_supertypes__() do
    [Temper.Orm.ChangesetError]
  end
  def new(field, message) do
    Temper.Orm.__temper_init__()
    this = TemperCore.Heap.new(Temper.Orm.ChangesetError, %{:field => nil, :message => nil})
    TemperCore.Heap.put(this, :field, field)
    TemperCore.Heap.put(this, :message, message)
    this
  end
  def get_field(this) do
    TemperCore.Heap.get(this, :field)
  end
  def get_message(this) do
    TemperCore.Heap.get(this, :message)
  end
end
defmodule Temper.Orm.NumberValidationOpts do
  def __temper_supertypes__() do
    [Temper.Orm.NumberValidationOpts]
  end
  def new(greaterThan, lessThan, greaterThanOrEqual, lessThanOrEqual, equalTo) do
    Temper.Orm.__temper_init__()
    this = TemperCore.Heap.new(Temper.Orm.NumberValidationOpts, %{:greaterThan => nil, :lessThan => nil, :greaterThanOrEqual => nil, :lessThanOrEqual => nil, :equalTo => nil})
    TemperCore.Heap.put(this, :greaterThan, greaterThan)
    TemperCore.Heap.put(this, :lessThan, lessThan)
    TemperCore.Heap.put(this, :greaterThanOrEqual, greaterThanOrEqual)
    TemperCore.Heap.put(this, :lessThanOrEqual, lessThanOrEqual)
    TemperCore.Heap.put(this, :equalTo, equalTo)
    this
  end
  def get_greaterThan(this) do
    TemperCore.Heap.get(this, :greaterThan)
  end
  def get_lessThan(this) do
    TemperCore.Heap.get(this, :lessThan)
  end
  def get_greaterThanOrEqual(this) do
    TemperCore.Heap.get(this, :greaterThanOrEqual)
  end
  def get_lessThanOrEqual(this) do
    TemperCore.Heap.get(this, :lessThanOrEqual)
  end
  def get_equalTo(this) do
    TemperCore.Heap.get(this, :equalTo)
  end
end
defmodule Temper.Orm.Changeset do
  def __temper_supertypes__() do
    [Temper.Orm.Changeset]
  end
  def get_tableDef(_this) do
    raise(TemperCore.Panic)
  end
  def get_changes(_this) do
    raise(TemperCore.Panic)
  end
  def get_errors(_this) do
    raise(TemperCore.Panic)
  end
  def get_isValid(_this) do
    raise(TemperCore.Panic)
  end
  def cast(_this, _allowedFields) do
    raise(TemperCore.Panic)
  end
  def validateRequired(_this, _fields) do
    raise(TemperCore.Panic)
  end
  def validateLength(_this, _field, _min_, _max_) do
    raise(TemperCore.Panic)
  end
  def validateInt(_this, _field) do
    raise(TemperCore.Panic)
  end
  def validateInt64(_this, _field) do
    raise(TemperCore.Panic)
  end
  def validateFloat(_this, _field) do
    raise(TemperCore.Panic)
  end
  def validateBool(_this, _field) do
    raise(TemperCore.Panic)
  end
  def putChange(_this, _field, _value) do
    raise(TemperCore.Panic)
  end
  def getChange(_this, _field) do
    raise(TemperCore.Panic)
  end
  def deleteChange(_this, _field) do
    raise(TemperCore.Panic)
  end
  def validateInclusion(_this, _field, _allowed) do
    raise(TemperCore.Panic)
  end
  def validateExclusion(_this, _field, _disallowed) do
    raise(TemperCore.Panic)
  end
  def validateNumber(_this, _field, _opts) do
    raise(TemperCore.Panic)
  end
  def validateAcceptance(_this, _field) do
    raise(TemperCore.Panic)
  end
  def validateConfirmation(_this, _field, _confirmationField) do
    raise(TemperCore.Panic)
  end
  def validateContains(_this, _field, _substring) do
    raise(TemperCore.Panic)
  end
  def validateStartsWith(_this, _field, _prefix) do
    raise(TemperCore.Panic)
  end
  def validateEndsWith(_this, _field, _suffix) do
    raise(TemperCore.Panic)
  end
  def toInsertSql(_this) do
    raise(TemperCore.Panic)
  end
  def toUpdateSql(_this, _id) do
    raise(TemperCore.Panic)
  end
end
defmodule Temper.Orm.ChangesetImpl do
  def __temper_supertypes__() do
    [Temper.Orm.ChangesetImpl, Temper.Orm.Changeset]
  end
  def get_tableDef(this) do
    TemperCore.Heap.get(this, :u_tableDef)
  end
  def get_changes(this) do
    TemperCore.Heap.get(this, :u_changes)
  end
  def get_errors(this) do
    TemperCore.Heap.get(this, :u_errors)
  end
  def get_isValid(this) do
    TemperCore.Heap.get(this, :u_isValid)
  end
  def addError(this, field, message) do
    eb = TemperCore.List.to_builder(TemperCore.Heap.get(this, :u_errors))
    TemperCore.List.add(eb, Temper.Orm.ChangesetError.new(field, message))
    Temper.Orm.ChangesetImpl.new(TemperCore.Heap.get(this, :u_tableDef), TemperCore.Heap.get(this, :u_params), TemperCore.Heap.get(this, :u_changes), TemperCore.List.to_list(eb), false)
  end
  def cast(this1, allowedFields) do
    mb = TemperCore.Map.builder()
    this2 = allowedFields
    n = TemperCore.List.length(this2)
    i = 0
    ex_loop_1 = fn ex_loop_1, i ->
      if i < n do
        el = TemperCore.List.get(this2, i)
        i = TemperCore.int32(i + 1)
        f = el
        val = TemperCore.Map.get_or(TemperCore.Heap.get(this1, :u_params), TemperCore.call(f, :get_sqlValue, []), "")
        if not TemperCore.String.is_empty(val) do
          TemperCore.Map.set(mb, TemperCore.call(f, :get_sqlValue, []), val)
          ex_loop_1.(ex_loop_1, i)
        else
          ex_loop_1.(ex_loop_1, i)
        end
      else
        i
      end
    end
    _i = ex_loop_1.(ex_loop_1, i)
    Temper.Orm.ChangesetImpl.new(TemperCore.Heap.get(this1, :u_tableDef), TemperCore.Heap.get(this1, :u_params), TemperCore.Map.to_map(mb), TemperCore.Heap.get(this1, :u_errors), TemperCore.Heap.get(this1, :u_isValid))
  end
  def validateRequired(this1, fields) do
    try do
      _return = nil
      return = if true do
        if not TemperCore.Heap.get(this1, :u_isValid) do
          return = this1
          return
        else
          eb = TemperCore.List.to_builder(TemperCore.Heap.get(this1, :u_errors))
          valid = true
          this2 = fields
          n = TemperCore.List.length(this2)
          i = 0
          ex_loop_2 = fn ex_loop_2, i, valid ->
            if i < n do
              el = TemperCore.List.get(this2, i)
              i = TemperCore.int32(i + 1)
              f = el
              if not TemperCore.Map.has(TemperCore.Heap.get(this1, :u_changes), TemperCore.call(f, :get_sqlValue, [])) do
                TemperCore.List.add(eb, Temper.Orm.ChangesetError.new(TemperCore.call(f, :get_sqlValue, []), "is required"))
                valid = false
                ex_loop_2.(ex_loop_2, i, valid)
              else
                ex_loop_2.(ex_loop_2, i, valid)
              end
            else
              {i, valid}
            end
          end
          {_i, valid} = ex_loop_2.(ex_loop_2, i, valid)
          throw({:temper_return, :ex_return_0, Temper.Orm.ChangesetImpl.new(TemperCore.Heap.get(this1, :u_tableDef), TemperCore.Heap.get(this1, :u_params), TemperCore.Heap.get(this1, :u_changes), TemperCore.List.to_list(eb), valid)})
        end
      end
      return
    catch
      {:temper_return, :ex_return_0, ex_value_4} ->
        ex_value_4
    end
  end
  def validateLength(this, field, min_, max_) do
    try do
      _return = nil
      return = if true do
        if not TemperCore.Heap.get(this, :u_isValid) do
          return = this
          return
        else
          val = TemperCore.Map.get_or(TemperCore.Heap.get(this, :u_changes), TemperCore.call(field, :get_sqlValue, []), "")
          len = TemperCore.String.count_between(val, TemperCore.String.begin(), TemperCore.String.end_of(val))
          _t = nil
          t = if len < min_ do
            t = true
            t
          else
            t = len > max_
            t
          end
          if t do
            return = Temper.Orm.ChangesetImpl.addError(this, TemperCore.call(field, :get_sqlValue, []), "must be between " <> TemperCore.int_to_string(min_) <> " and " <> TemperCore.int_to_string(max_) <> " characters")
            return
          else
            throw({:temper_return, :ex_return_0, this})
          end
        end
      end
      return
    catch
      {:temper_return, :ex_return_0, ex_value_2} ->
        ex_value_2
    end
  end
  def validateInt(this, field) do
    try do
      _return = nil
      return = if true do
        if not TemperCore.Heap.get(this, :u_isValid) do
          return = this
          return
        else
          val = TemperCore.Map.get_or(TemperCore.Heap.get(this, :u_changes), TemperCore.call(field, :get_sqlValue, []), "")
          if TemperCore.String.is_empty(val) do
            return = this
            return
          else
            _parseOk = nil
            parseOk = try do
              TemperCore.String.to_int32(val)
              parseOk = true
              parseOk
            rescue
              _ in TemperCore.Bubble ->
                parseOk = false
                parseOk
            end
            if not parseOk do
              return = Temper.Orm.ChangesetImpl.addError(this, TemperCore.call(field, :get_sqlValue, []), "must be an integer")
              return
            else
              throw({:temper_return, :ex_return_0, this})
            end
          end
        end
      end
      return
    catch
      {:temper_return, :ex_return_0, ex_value_2} ->
        ex_value_2
    end
  end
  def validateInt64(this, field) do
    try do
      _return = nil
      return = if true do
        if not TemperCore.Heap.get(this, :u_isValid) do
          return = this
          return
        else
          val = TemperCore.Map.get_or(TemperCore.Heap.get(this, :u_changes), TemperCore.call(field, :get_sqlValue, []), "")
          if TemperCore.String.is_empty(val) do
            return = this
            return
          else
            _parseOk = nil
            parseOk = try do
              TemperCore.String.to_int64(val)
              parseOk = true
              parseOk
            rescue
              _ in TemperCore.Bubble ->
                parseOk = false
                parseOk
            end
            if not parseOk do
              return = Temper.Orm.ChangesetImpl.addError(this, TemperCore.call(field, :get_sqlValue, []), "must be a 64-bit integer")
              return
            else
              throw({:temper_return, :ex_return_0, this})
            end
          end
        end
      end
      return
    catch
      {:temper_return, :ex_return_0, ex_value_2} ->
        ex_value_2
    end
  end
  def validateFloat(this, field) do
    try do
      _return = nil
      return = if true do
        if not TemperCore.Heap.get(this, :u_isValid) do
          return = this
          return
        else
          val = TemperCore.Map.get_or(TemperCore.Heap.get(this, :u_changes), TemperCore.call(field, :get_sqlValue, []), "")
          if TemperCore.String.is_empty(val) do
            return = this
            return
          else
            _parseOk = nil
            parseOk = try do
              TemperCore.String.to_float64(val)
              parseOk = true
              parseOk
            rescue
              _ in TemperCore.Bubble ->
                parseOk = false
                parseOk
            end
            if not parseOk do
              return = Temper.Orm.ChangesetImpl.addError(this, TemperCore.call(field, :get_sqlValue, []), "must be a number")
              return
            else
              throw({:temper_return, :ex_return_0, this})
            end
          end
        end
      end
      return
    catch
      {:temper_return, :ex_return_0, ex_value_2} ->
        ex_value_2
    end
  end
  def validateBool(this, field) do
    try do
      _return = nil
      return = if true do
        if not TemperCore.Heap.get(this, :u_isValid) do
          return = this
          return
        else
          val = TemperCore.Map.get_or(TemperCore.Heap.get(this, :u_changes), TemperCore.call(field, :get_sqlValue, []), "")
          if TemperCore.String.is_empty(val) do
            return = this
            return
          else
            _isTrue = nil
            isTrue = cond do
              val == "true" ->
                isTrue = true
                isTrue
              val == "1" ->
                isTrue = true
                isTrue
              val == "yes" ->
                isTrue = true
                isTrue
              true ->
                isTrue = val == "on"
                isTrue
            end
            _isFalse = nil
            isFalse = cond do
              val == "false" ->
                isFalse = true
                isFalse
              val == "0" ->
                isFalse = true
                isFalse
              val == "no" ->
                isFalse = true
                isFalse
              true ->
                isFalse = val == "off"
                isFalse
            end
            _t = nil
            t = if not isTrue do
              t = not isFalse
              t
            else
              t = false
              t
            end
            if t do
              return = Temper.Orm.ChangesetImpl.addError(this, TemperCore.call(field, :get_sqlValue, []), "must be a boolean (true/false/1/0/yes/no/on/off)")
              return
            else
              throw({:temper_return, :ex_return_0, this})
            end
          end
        end
      end
      return
    catch
      {:temper_return, :ex_return_0, ex_value_2} ->
        ex_value_2
    end
  end
  def putChange(this, field, value) do
    mb = TemperCore.Map.builder()
    pairs = TemperCore.Map.to_list(TemperCore.Heap.get(this, :u_changes))
    i = 0
    ex_loop_1 = fn ex_loop_1, i ->
      if i < TemperCore.List.length(pairs) do
        TemperCore.Map.set(mb, TemperCore.Pair.get_key(TemperCore.List.get(pairs, i)), TemperCore.Pair.get_value(TemperCore.List.get(pairs, i)))
        i = TemperCore.int32(i + 1)
        ex_loop_1.(ex_loop_1, i)
      else
        i
      end
    end
    _i = ex_loop_1.(ex_loop_1, i)
    TemperCore.Map.set(mb, TemperCore.call(field, :get_sqlValue, []), value)
    Temper.Orm.ChangesetImpl.new(TemperCore.Heap.get(this, :u_tableDef), TemperCore.Heap.get(this, :u_params), TemperCore.Map.to_map(mb), TemperCore.Heap.get(this, :u_errors), TemperCore.Heap.get(this, :u_isValid))
  end
  def getChange(this, field) do
    if not TemperCore.Map.has(TemperCore.Heap.get(this, :u_changes), TemperCore.call(field, :get_sqlValue, [])) do
      raise(TemperCore.Bubble)
    else
      TemperCore.Map.get_or(TemperCore.Heap.get(this, :u_changes), TemperCore.call(field, :get_sqlValue, []), "")
    end
  end
  def deleteChange(this, field) do
    mb = TemperCore.Map.builder()
    pairs = TemperCore.Map.to_list(TemperCore.Heap.get(this, :u_changes))
    i = 0
    ex_loop_1 = fn ex_loop_1, i ->
      if i < TemperCore.List.length(pairs) do
        if TemperCore.Pair.get_key(TemperCore.List.get(pairs, i)) != TemperCore.call(field, :get_sqlValue, []) do
          TemperCore.Map.set(mb, TemperCore.Pair.get_key(TemperCore.List.get(pairs, i)), TemperCore.Pair.get_value(TemperCore.List.get(pairs, i)))
          nil
        else
          nil
        end
        i = TemperCore.int32(i + 1)
        ex_loop_1.(ex_loop_1, i)
      else
        i
      end
    end
    _i = ex_loop_1.(ex_loop_1, i)
    Temper.Orm.ChangesetImpl.new(TemperCore.Heap.get(this, :u_tableDef), TemperCore.Heap.get(this, :u_params), TemperCore.Map.to_map(mb), TemperCore.Heap.get(this, :u_errors), TemperCore.Heap.get(this, :u_isValid))
  end
  def validateInclusion(this1, field, allowed) do
    try do
      _return = nil
      return = if true do
        cond do
          not TemperCore.Heap.get(this1, :u_isValid) ->
            return = this1
            return
          not TemperCore.Map.has(TemperCore.Heap.get(this1, :u_changes), TemperCore.call(field, :get_sqlValue, [])) ->
            return = this1
            return
          true ->
            val = TemperCore.Map.get_or(TemperCore.Heap.get(this1, :u_changes), TemperCore.call(field, :get_sqlValue, []), "")
            found = false
            this2 = allowed
            n = TemperCore.List.length(this2)
            i = 0
            ex_loop_2 = fn ex_loop_2, found, i ->
              if i < n do
                el = TemperCore.List.get(this2, i)
                i = TemperCore.int32(i + 1)
                a = el
                if a == val do
                  found = true
                  ex_loop_2.(ex_loop_2, found, i)
                else
                  ex_loop_2.(ex_loop_2, found, i)
                end
              else
                {found, i}
              end
            end
            {found, _i} = ex_loop_2.(ex_loop_2, found, i)
            if not found do
              return = Temper.Orm.ChangesetImpl.addError(this1, TemperCore.call(field, :get_sqlValue, []), "is not included in the list")
              return
            else
              throw({:temper_return, :ex_return_0, this1})
            end
        end
      end
      return
    catch
      {:temper_return, :ex_return_0, ex_value_4} ->
        ex_value_4
    end
  end
  def validateExclusion(this1, field, disallowed) do
    try do
      _return = nil
      return = if true do
        cond do
          not TemperCore.Heap.get(this1, :u_isValid) ->
            return = this1
            return
          not TemperCore.Map.has(TemperCore.Heap.get(this1, :u_changes), TemperCore.call(field, :get_sqlValue, [])) ->
            return = this1
            return
          true ->
            val = TemperCore.Map.get_or(TemperCore.Heap.get(this1, :u_changes), TemperCore.call(field, :get_sqlValue, []), "")
            found = false
            this2 = disallowed
            n = TemperCore.List.length(this2)
            i = 0
            ex_loop_2 = fn ex_loop_2, found, i ->
              if i < n do
                el = TemperCore.List.get(this2, i)
                i = TemperCore.int32(i + 1)
                d = el
                if d == val do
                  found = true
                  ex_loop_2.(ex_loop_2, found, i)
                else
                  ex_loop_2.(ex_loop_2, found, i)
                end
              else
                {found, i}
              end
            end
            {found, _i} = ex_loop_2.(ex_loop_2, found, i)
            if found do
              return = Temper.Orm.ChangesetImpl.addError(this1, TemperCore.call(field, :get_sqlValue, []), "is reserved")
              return
            else
              throw({:temper_return, :ex_return_0, this1})
            end
        end
      end
      return
    catch
      {:temper_return, :ex_return_0, ex_value_4} ->
        ex_value_4
    end
  end
  def validateNumber(this, field, opts) do
    try do
      return = nil
      return = try do
        cond do
          not TemperCore.Heap.get(this, :u_isValid) ->
            return = this
            return
          not TemperCore.Map.has(TemperCore.Heap.get(this, :u_changes), TemperCore.call(field, :get_sqlValue, [])) ->
            return = this
            return
          true ->
            val = TemperCore.Map.get_or(TemperCore.Heap.get(this, :u_changes), TemperCore.call(field, :get_sqlValue, []), "")
            _parseOk = nil
            parseOk = try do
              TemperCore.String.to_float64(val)
              parseOk = true
              parseOk
            rescue
              _ in TemperCore.Bubble ->
                parseOk = false
                parseOk
            end
            if not parseOk do
              return = Temper.Orm.ChangesetImpl.addError(this, TemperCore.call(field, :get_sqlValue, []), "must be a number")
              return
            else
              _num = nil
              num = try do
                num = TemperCore.String.to_float64(val)
                num
              rescue
                _ in TemperCore.Bubble ->
                  num = 0.0
                  num
              end
              gt1 = Temper.Orm.NumberValidationOpts.get_greaterThan(opts)
              return = if not (gt1 === nil) do
                gt2 = gt1
                if not TemperCore.Float.gt(num, gt2) do
                  return = Temper.Orm.ChangesetImpl.addError(this, TemperCore.call(field, :get_sqlValue, []), "must be greater than " <> TemperCore.Float.to_string(gt2))
                  throw({:temper_break, :ex_block_1, return})
                else
                  return
                end
              else
                return
              end
              lt1 = Temper.Orm.NumberValidationOpts.get_lessThan(opts)
              return = if not (lt1 === nil) do
                lt2 = lt1
                if not TemperCore.Float.lt(num, lt2) do
                  return = Temper.Orm.ChangesetImpl.addError(this, TemperCore.call(field, :get_sqlValue, []), "must be less than " <> TemperCore.Float.to_string(lt2))
                  throw({:temper_break, :ex_block_1, return})
                else
                  return
                end
              else
                return
              end
              gte1 = Temper.Orm.NumberValidationOpts.get_greaterThanOrEqual(opts)
              return = if not (gte1 === nil) do
                gte2 = gte1
                if not TemperCore.Float.ge(num, gte2) do
                  return = Temper.Orm.ChangesetImpl.addError(this, TemperCore.call(field, :get_sqlValue, []), "must be greater than or equal to " <> TemperCore.Float.to_string(gte2))
                  throw({:temper_break, :ex_block_1, return})
                else
                  return
                end
              else
                return
              end
              lte1 = Temper.Orm.NumberValidationOpts.get_lessThanOrEqual(opts)
              return = if not (lte1 === nil) do
                lte2 = lte1
                if not TemperCore.Float.le(num, lte2) do
                  return = Temper.Orm.ChangesetImpl.addError(this, TemperCore.call(field, :get_sqlValue, []), "must be less than or equal to " <> TemperCore.Float.to_string(lte2))
                  throw({:temper_break, :ex_block_1, return})
                else
                  return
                end
              else
                return
              end
              eq1 = Temper.Orm.NumberValidationOpts.get_equalTo(opts)
              _return = if not (eq1 === nil) do
                eq2 = eq1
                if not TemperCore.Float.eq(num, eq2) do
                  return = Temper.Orm.ChangesetImpl.addError(this, TemperCore.call(field, :get_sqlValue, []), "must be equal to " <> TemperCore.Float.to_string(eq2))
                  throw({:temper_break, :ex_block_1, return})
                else
                  return
                end
              else
                return
              end
              throw({:temper_return, :ex_return_0, this})
            end
        end
      catch
        {:temper_break, :ex_block_1, ex_vars_2} ->
          ex_vars_2
      end
      return
    catch
      {:temper_return, :ex_return_0, ex_value_3} ->
        ex_value_3
    end
  end
  def validateAcceptance(this, field) do
    try do
      _return = nil
      return = if true do
        cond do
          not TemperCore.Heap.get(this, :u_isValid) ->
            return = this
            return
          not TemperCore.Map.has(TemperCore.Heap.get(this, :u_changes), TemperCore.call(field, :get_sqlValue, [])) ->
            return = this
            return
          true ->
            val = TemperCore.Map.get_or(TemperCore.Heap.get(this, :u_changes), TemperCore.call(field, :get_sqlValue, []), "")
            _accepted = nil
            accepted = cond do
              val == "true" ->
                accepted = true
                accepted
              val == "1" ->
                accepted = true
                accepted
              val == "yes" ->
                accepted = true
                accepted
              true ->
                accepted = val == "on"
                accepted
            end
            if not accepted do
              return = Temper.Orm.ChangesetImpl.addError(this, TemperCore.call(field, :get_sqlValue, []), "must be accepted")
              return
            else
              throw({:temper_return, :ex_return_0, this})
            end
        end
      end
      return
    catch
      {:temper_return, :ex_return_0, ex_value_2} ->
        ex_value_2
    end
  end
  def validateConfirmation(this, field, confirmationField) do
    try do
      _return = nil
      return = if true do
        cond do
          not TemperCore.Heap.get(this, :u_isValid) ->
            return = this
            return
          not TemperCore.Map.has(TemperCore.Heap.get(this, :u_changes), TemperCore.call(field, :get_sqlValue, [])) ->
            return = this
            return
          true ->
            val = TemperCore.Map.get_or(TemperCore.Heap.get(this, :u_changes), TemperCore.call(field, :get_sqlValue, []), "")
            conf = TemperCore.Map.get_or(TemperCore.Heap.get(this, :u_changes), TemperCore.call(confirmationField, :get_sqlValue, []), "")
            if val != conf do
              return = Temper.Orm.ChangesetImpl.addError(this, TemperCore.call(confirmationField, :get_sqlValue, []), "does not match")
              return
            else
              throw({:temper_return, :ex_return_0, this})
            end
        end
      end
      return
    catch
      {:temper_return, :ex_return_0, ex_value_2} ->
        ex_value_2
    end
  end
  def validateContains(this, field, substring) do
    try do
      _return = nil
      return = if true do
        cond do
          not TemperCore.Heap.get(this, :u_isValid) ->
            return = this
            return
          not TemperCore.Map.has(TemperCore.Heap.get(this, :u_changes), TemperCore.call(field, :get_sqlValue, [])) ->
            return = this
            return
          true ->
            val = TemperCore.Map.get_or(TemperCore.Heap.get(this, :u_changes), TemperCore.call(field, :get_sqlValue, []), "")
            if not (TemperCore.String.index_of(val, substring) >= 0) do
              return = Temper.Orm.ChangesetImpl.addError(this, TemperCore.call(field, :get_sqlValue, []), "must contain the given substring")
              return
            else
              throw({:temper_return, :ex_return_0, this})
            end
        end
      end
      return
    catch
      {:temper_return, :ex_return_0, ex_value_2} ->
        ex_value_2
    end
  end
  def validateStartsWith(this, field, prefix) do
    try do
      _return = nil
      return = if true do
        cond do
          not TemperCore.Heap.get(this, :u_isValid) ->
            return = this
            return
          not TemperCore.Map.has(TemperCore.Heap.get(this, :u_changes), TemperCore.call(field, :get_sqlValue, [])) ->
            return = this
            return
          true ->
            val = TemperCore.Map.get_or(TemperCore.Heap.get(this, :u_changes), TemperCore.call(field, :get_sqlValue, []), "")
            idx = TemperCore.String.index_of(val, prefix)
            _starts = nil
            starts = if idx >= 0 do
              starts = TemperCore.String.count_between(val, TemperCore.String.begin(), idx) == 0
              starts
            else
              starts = false
              starts
            end
            if not starts do
              return = Temper.Orm.ChangesetImpl.addError(this, TemperCore.call(field, :get_sqlValue, []), "must start with the given prefix")
              return
            else
              throw({:temper_return, :ex_return_0, this})
            end
        end
      end
      return
    catch
      {:temper_return, :ex_return_0, ex_value_2} ->
        ex_value_2
    end
  end
  def validateEndsWith(this, field, suffix) do
    try do
      _return = nil
      return = if true do
        cond do
          not TemperCore.Heap.get(this, :u_isValid) ->
            return = this
            return
          not TemperCore.Map.has(TemperCore.Heap.get(this, :u_changes), TemperCore.call(field, :get_sqlValue, [])) ->
            return = this
            return
          true ->
            val = TemperCore.Map.get_or(TemperCore.Heap.get(this, :u_changes), TemperCore.call(field, :get_sqlValue, []), "")
            valLen = TemperCore.String.count_between(val, TemperCore.String.begin(), TemperCore.String.end_of(val))
            suffixLen = TemperCore.String.count_between(suffix, TemperCore.String.begin(), TemperCore.String.end_of(suffix))
            if valLen < suffixLen do
              return = Temper.Orm.ChangesetImpl.addError(this, TemperCore.call(field, :get_sqlValue, []), "must end with the given suffix")
              return
            else
              skipCount = TemperCore.int32(valLen - suffixLen)
              strIdx = TemperCore.String.begin()
              i = 0
              ex_loop_2 = fn ex_loop_2, i, strIdx ->
                if i < skipCount do
                  strIdx = TemperCore.String.next(val, strIdx)
                  i = TemperCore.int32(i + 1)
                  ex_loop_2.(ex_loop_2, i, strIdx)
                else
                  {i, strIdx}
                end
              end
              {_i, strIdx} = ex_loop_2.(ex_loop_2, i, strIdx)
              sufIdx = TemperCore.String.begin()
              matches = true
              ex_loop_4 = fn ex_loop_4, matches, strIdx, sufIdx ->
                if true do
                  _t = nil
                  t = if matches do
                    t = TemperCore.String.has_index(suffix, sufIdx)
                    t
                  else
                    t = false
                    t
                  end
                  cond do
                    not t ->
                      {matches, strIdx, sufIdx}
                    not TemperCore.String.has_index(val, strIdx) ->
                      matches = false
                      ex_loop_4.(ex_loop_4, matches, strIdx, sufIdx)
                    TemperCore.String.get(val, strIdx) != TemperCore.String.get(suffix, sufIdx) ->
                      matches = false
                      ex_loop_4.(ex_loop_4, matches, strIdx, sufIdx)
                    true ->
                      strIdx = TemperCore.String.next(val, strIdx)
                      sufIdx = TemperCore.String.next(suffix, sufIdx)
                      ex_loop_4.(ex_loop_4, matches, strIdx, sufIdx)
                  end
                else
                  {matches, strIdx, sufIdx}
                end
              end
              {matches, _strIdx, _sufIdx} = ex_loop_4.(ex_loop_4, matches, strIdx, sufIdx)
              if not matches do
                return = Temper.Orm.ChangesetImpl.addError(this, TemperCore.call(field, :get_sqlValue, []), "must end with the given suffix")
                return
              else
                throw({:temper_return, :ex_return_0, this})
              end
            end
        end
      end
      return
    catch
      {:temper_return, :ex_return_0, ex_value_6} ->
        ex_value_6
    end
  end
  def parseBoolSqlPart(_this, val) do
    _return = nil
    return = if true do
      _t1 = nil
      t1 = cond do
        val == "true" ->
          t1 = true
          t1
        val == "1" ->
          t1 = true
          t1
        val == "yes" ->
          t1 = true
          t1
        true ->
          t1 = val == "on"
          t1
      end
      if t1 do
        return = Temper.Orm.SqlBoolean.new(true)
        return
      else
        _t2 = nil
        t2 = cond do
          val == "false" ->
            t2 = true
            t2
          val == "0" ->
            t2 = true
            t2
          val == "no" ->
            t2 = true
            t2
          true ->
            t2 = val == "off"
            t2
        end
        if t2 do
          return = Temper.Orm.SqlBoolean.new(false)
          return
        else
          raise(TemperCore.Bubble)
        end
      end
    end
    return
  end
  def valueToSqlPart(this, fieldDef, val) do
    _return = nil
    return = if true do
      ft = Temper.Orm.FieldDef.get_fieldType(fieldDef)
      cond do
        TemperCore.is_a(ft, Temper.Orm.StringField) ->
          return = Temper.Orm.SqlString.new(val)
          return
        TemperCore.is_a(ft, Temper.Orm.IntField) ->
          t1 = TemperCore.String.to_int32(val)
          return = Temper.Orm.SqlInt32.new(t1)
          return
        TemperCore.is_a(ft, Temper.Orm.Int64Field) ->
          t2 = TemperCore.String.to_int64(val)
          return = Temper.Orm.SqlInt64.new(t2)
          return
        TemperCore.is_a(ft, Temper.Orm.FloatField) ->
          t3 = TemperCore.String.to_float64(val)
          return = Temper.Orm.SqlFloat64.new(t3)
          return
        TemperCore.is_a(ft, Temper.Orm.BoolField) ->
          return = Temper.Orm.ChangesetImpl.parseBoolSqlPart(this, val)
          return
        TemperCore.is_a(ft, Temper.Orm.DateField) ->
          t4 = Temper.Std.Date.fromIsoString(val)
          return = Temper.Orm.SqlDate.new(t4)
          return
        true ->
          raise(TemperCore.Bubble)
      end
    end
    return
  end
  def toInsertSql(this) do
    if not TemperCore.Heap.get(this, :u_isValid) do
      raise(TemperCore.Bubble)
    else
      i1 = 0
      ex_loop_1 = fn ex_loop_1, i1 ->
        if i1 < TemperCore.List.length(Temper.Orm.TableDef.get_fields(TemperCore.Heap.get(this, :u_tableDef))) do
          if true do
            f1 = TemperCore.List.get(Temper.Orm.TableDef.get_fields(TemperCore.Heap.get(this, :u_tableDef)), i1)
            if Temper.Orm.FieldDef.get_virtual(f1) do
              nil
            else
              dv1 = Temper.Orm.FieldDef.get_defaultValue(f1)
              _t1 = nil
              t1 = if not Temper.Orm.FieldDef.get_nullable(f1) do
                if not TemperCore.Map.has(TemperCore.Heap.get(this, :u_changes), TemperCore.call(Temper.Orm.FieldDef.get_name(f1), :get_sqlValue, [])) do
                  t1 = dv1 === nil
                  t1
                else
                  t1 = false
                  t1
                end
              else
                t1 = false
                t1
              end
              if t1 do
                raise(TemperCore.Bubble)
              else
                nil
              end
            end
          end
          i1 = TemperCore.int32(i1 + 1)
          ex_loop_1.(ex_loop_1, i1)
        else
          i1
        end
      end
      _i1 = ex_loop_1.(ex_loop_1, i1)
      colNames = TemperCore.List.builder()
      valParts = TemperCore.List.builder()
      pairs = TemperCore.Map.to_list(TemperCore.Heap.get(this, :u_changes))
      i2 = 0
      ex_loop_4 = fn ex_loop_4, i2 ->
        if i2 < TemperCore.List.length(pairs) do
          if true do
            pair = TemperCore.List.get(pairs, i2)
            fd = Temper.Orm.TableDef.field(TemperCore.Heap.get(this, :u_tableDef), TemperCore.Pair.get_key(pair))
            if Temper.Orm.FieldDef.get_virtual(fd) do
              nil
            else
              TemperCore.List.add(colNames, TemperCore.call(Temper.Orm.FieldDef.get_name(fd), :get_sqlValue, []))
              t2 = Temper.Orm.ChangesetImpl.valueToSqlPart(this, fd, TemperCore.Pair.get_value(pair))
              TemperCore.List.add(valParts, t2)
              nil
            end
          end
          i2 = TemperCore.int32(i2 + 1)
          ex_loop_4.(ex_loop_4, i2)
        else
          i2
        end
      end
      _i2 = ex_loop_4.(ex_loop_4, i2)
      i3 = 0
      ex_loop_7 = fn ex_loop_7, i3 ->
        if i3 < TemperCore.List.length(Temper.Orm.TableDef.get_fields(TemperCore.Heap.get(this, :u_tableDef))) do
          if true do
            f2 = TemperCore.List.get(Temper.Orm.TableDef.get_fields(TemperCore.Heap.get(this, :u_tableDef)), i3)
            if Temper.Orm.FieldDef.get_virtual(f2) do
              nil
            else
              dv2 = Temper.Orm.FieldDef.get_defaultValue(f2)
              if not (dv2 === nil) do
                dv3 = dv2
                if not TemperCore.Map.has(TemperCore.Heap.get(this, :u_changes), TemperCore.call(Temper.Orm.FieldDef.get_name(f2), :get_sqlValue, [])) do
                  TemperCore.List.add(colNames, TemperCore.call(Temper.Orm.FieldDef.get_name(f2), :get_sqlValue, []))
                  TemperCore.List.add(valParts, dv3)
                  nil
                else
                  nil
                end
              else
                nil
              end
            end
          end
          i3 = TemperCore.int32(i3 + 1)
          ex_loop_7.(ex_loop_7, i3)
        else
          i3
        end
      end
      _i3 = ex_loop_7.(ex_loop_7, i3)
      if TemperCore.List.length(valParts) == 0 do
        raise(TemperCore.Bubble)
      else
        b = Temper.Orm.SqlBuilder.new()
        Temper.Orm.SqlBuilder.appendSafe(b, "INSERT INTO ")
        Temper.Orm.SqlBuilder.appendSafe(b, TemperCore.call(Temper.Orm.TableDef.get_tableName(TemperCore.Heap.get(this, :u_tableDef)), :get_sqlValue, []))
        Temper.Orm.SqlBuilder.appendSafe(b, " (")
        fn_ = fn c ->
          c
        end
        Temper.Orm.SqlBuilder.appendSafe(b, TemperCore.List.join(TemperCore.List.to_list(colNames), ", ", fn_))
        Temper.Orm.SqlBuilder.appendSafe(b, ") VALUES (")
        Temper.Orm.SqlBuilder.appendPart(b, TemperCore.List.get(valParts, 0))
        j = 1
        ex_loop_11 = fn ex_loop_11, j ->
          if j < TemperCore.List.length(valParts) do
            Temper.Orm.SqlBuilder.appendSafe(b, ", ")
            Temper.Orm.SqlBuilder.appendPart(b, TemperCore.List.get(valParts, j))
            j = TemperCore.int32(j + 1)
            ex_loop_11.(ex_loop_11, j)
          else
            j
          end
        end
        _j = ex_loop_11.(ex_loop_11, j)
        Temper.Orm.SqlBuilder.appendSafe(b, ")")
        Temper.Orm.SqlBuilder.get_accumulated(b)
      end
    end
  end
  def toUpdateSql(this, id) do
    if not TemperCore.Heap.get(this, :u_isValid) do
      raise(TemperCore.Bubble)
    else
      pairs = TemperCore.Map.to_list(TemperCore.Heap.get(this, :u_changes))
      if TemperCore.List.length(pairs) == 0 do
        raise(TemperCore.Bubble)
      else
        b = Temper.Orm.SqlBuilder.new()
        Temper.Orm.SqlBuilder.appendSafe(b, "UPDATE ")
        Temper.Orm.SqlBuilder.appendSafe(b, TemperCore.call(Temper.Orm.TableDef.get_tableName(TemperCore.Heap.get(this, :u_tableDef)), :get_sqlValue, []))
        Temper.Orm.SqlBuilder.appendSafe(b, " SET ")
        setCount = 0
        i = 0
        ex_loop_1 = fn ex_loop_1, i, setCount ->
          if i < TemperCore.List.length(pairs) do
            setCount = if true do
              pair = TemperCore.List.get(pairs, i)
              fd = Temper.Orm.TableDef.field(TemperCore.Heap.get(this, :u_tableDef), TemperCore.Pair.get_key(pair))
              if Temper.Orm.FieldDef.get_virtual(fd) do
                setCount
              else
                if setCount > 0 do
                  Temper.Orm.SqlBuilder.appendSafe(b, ", ")
                  nil
                else
                  nil
                end
                Temper.Orm.SqlBuilder.appendSafe(b, TemperCore.call(Temper.Orm.FieldDef.get_name(fd), :get_sqlValue, []))
                Temper.Orm.SqlBuilder.appendSafe(b, " = ")
                t = Temper.Orm.ChangesetImpl.valueToSqlPart(this, fd, TemperCore.Pair.get_value(pair))
                Temper.Orm.SqlBuilder.appendPart(b, t)
                setCount = TemperCore.int32(setCount + 1)
                setCount
              end
            end
            i = TemperCore.int32(i + 1)
            ex_loop_1.(ex_loop_1, i, setCount)
          else
            {i, setCount}
          end
        end
        {_i, setCount} = ex_loop_1.(ex_loop_1, i, setCount)
        if setCount == 0 do
          raise(TemperCore.Bubble)
        else
          Temper.Orm.SqlBuilder.appendSafe(b, " WHERE ")
          Temper.Orm.SqlBuilder.appendSafe(b, Temper.Orm.TableDef.pkName(TemperCore.Heap.get(this, :u_tableDef)))
          Temper.Orm.SqlBuilder.appendSafe(b, " = ")
          Temper.Orm.SqlBuilder.appendInt32(b, id)
          Temper.Orm.SqlBuilder.get_accumulated(b)
        end
      end
    end
  end
  def new(u_tableDef, u_params, u_changes, u_errors, u_isValid) do
    this = TemperCore.Heap.new(Temper.Orm.ChangesetImpl, %{:u_tableDef => nil, :u_params => nil, :u_changes => nil, :u_errors => nil, :u_isValid => nil})
    TemperCore.Heap.put(this, :u_tableDef, u_tableDef)
    TemperCore.Heap.put(this, :u_params, u_params)
    TemperCore.Heap.put(this, :u_changes, u_changes)
    TemperCore.Heap.put(this, :u_errors, u_errors)
    TemperCore.Heap.put(this, :u_isValid, u_isValid)
    this
  end
end
defmodule Temper.Orm.JoinType do
  def __temper_supertypes__() do
    [Temper.Orm.JoinType]
  end
  def keyword(_this) do
    raise(TemperCore.Panic)
  end
end
defmodule Temper.Orm.InnerJoin do
  def __temper_supertypes__() do
    [Temper.Orm.InnerJoin, Temper.Orm.JoinType]
  end
  def keyword(_this) do
    "INNER JOIN"
  end
  def new() do
    Temper.Orm.__temper_init__()
    this = TemperCore.Heap.new(Temper.Orm.InnerJoin, %{})
    this
  end
end
defmodule Temper.Orm.LeftJoin do
  def __temper_supertypes__() do
    [Temper.Orm.LeftJoin, Temper.Orm.JoinType]
  end
  def keyword(_this) do
    "LEFT JOIN"
  end
  def new() do
    Temper.Orm.__temper_init__()
    this = TemperCore.Heap.new(Temper.Orm.LeftJoin, %{})
    this
  end
end
defmodule Temper.Orm.RightJoin do
  def __temper_supertypes__() do
    [Temper.Orm.RightJoin, Temper.Orm.JoinType]
  end
  def keyword(_this) do
    "RIGHT JOIN"
  end
  def new() do
    Temper.Orm.__temper_init__()
    this = TemperCore.Heap.new(Temper.Orm.RightJoin, %{})
    this
  end
end
defmodule Temper.Orm.FullJoin do
  def __temper_supertypes__() do
    [Temper.Orm.FullJoin, Temper.Orm.JoinType]
  end
  def keyword(_this) do
    "FULL OUTER JOIN"
  end
  def new() do
    Temper.Orm.__temper_init__()
    this = TemperCore.Heap.new(Temper.Orm.FullJoin, %{})
    this
  end
end
defmodule Temper.Orm.CrossJoin do
  def __temper_supertypes__() do
    [Temper.Orm.CrossJoin, Temper.Orm.JoinType]
  end
  def keyword(_this) do
    "CROSS JOIN"
  end
  def new() do
    Temper.Orm.__temper_init__()
    this = TemperCore.Heap.new(Temper.Orm.CrossJoin, %{})
    this
  end
end
defmodule Temper.Orm.JoinClause do
  def __temper_supertypes__() do
    [Temper.Orm.JoinClause]
  end
  def new(joinType, table, onCondition) do
    Temper.Orm.__temper_init__()
    this = TemperCore.Heap.new(Temper.Orm.JoinClause, %{:joinType => nil, :table => nil, :onCondition => nil})
    TemperCore.Heap.put(this, :joinType, joinType)
    TemperCore.Heap.put(this, :table, table)
    TemperCore.Heap.put(this, :onCondition, onCondition)
    this
  end
  def get_joinType(this) do
    TemperCore.Heap.get(this, :joinType)
  end
  def get_table(this) do
    TemperCore.Heap.get(this, :table)
  end
  def get_onCondition(this) do
    TemperCore.Heap.get(this, :onCondition)
  end
end
defmodule Temper.Orm.NullsPosition do
  def __temper_supertypes__() do
    [Temper.Orm.NullsPosition]
  end
  def keyword(_this) do
    raise(TemperCore.Panic)
  end
end
defmodule Temper.Orm.NullsFirst do
  def __temper_supertypes__() do
    [Temper.Orm.NullsFirst, Temper.Orm.NullsPosition]
  end
  def keyword(_this) do
    " NULLS FIRST"
  end
  def new() do
    Temper.Orm.__temper_init__()
    this = TemperCore.Heap.new(Temper.Orm.NullsFirst, %{})
    this
  end
end
defmodule Temper.Orm.NullsLast do
  def __temper_supertypes__() do
    [Temper.Orm.NullsLast, Temper.Orm.NullsPosition]
  end
  def keyword(_this) do
    " NULLS LAST"
  end
  def new() do
    Temper.Orm.__temper_init__()
    this = TemperCore.Heap.new(Temper.Orm.NullsLast, %{})
    this
  end
end
defmodule Temper.Orm.OrderClause do
  def __temper_supertypes__() do
    [Temper.Orm.OrderClause]
  end
  def new(field, ascending, nullsPos) do
    Temper.Orm.__temper_init__()
    this = TemperCore.Heap.new(Temper.Orm.OrderClause, %{:field => nil, :ascending => nil, :nullsPos => nil})
    TemperCore.Heap.put(this, :field, field)
    TemperCore.Heap.put(this, :ascending, ascending)
    TemperCore.Heap.put(this, :nullsPos, nullsPos)
    this
  end
  def get_field(this) do
    TemperCore.Heap.get(this, :field)
  end
  def get_ascending(this) do
    TemperCore.Heap.get(this, :ascending)
  end
  def get_nullsPos(this) do
    TemperCore.Heap.get(this, :nullsPos)
  end
end
defmodule Temper.Orm.LockMode do
  def __temper_supertypes__() do
    [Temper.Orm.LockMode]
  end
  def keyword(_this) do
    raise(TemperCore.Panic)
  end
end
defmodule Temper.Orm.ForUpdate do
  def __temper_supertypes__() do
    [Temper.Orm.ForUpdate, Temper.Orm.LockMode]
  end
  def keyword(_this) do
    " FOR UPDATE"
  end
  def new() do
    Temper.Orm.__temper_init__()
    this = TemperCore.Heap.new(Temper.Orm.ForUpdate, %{})
    this
  end
end
defmodule Temper.Orm.ForShare do
  def __temper_supertypes__() do
    [Temper.Orm.ForShare, Temper.Orm.LockMode]
  end
  def keyword(_this) do
    " FOR SHARE"
  end
  def new() do
    Temper.Orm.__temper_init__()
    this = TemperCore.Heap.new(Temper.Orm.ForShare, %{})
    this
  end
end
defmodule Temper.Orm.WhereClause do
  def __temper_supertypes__() do
    [Temper.Orm.WhereClause]
  end
  def get_condition(_this) do
    raise(TemperCore.Panic)
  end
  def keyword(_this) do
    raise(TemperCore.Panic)
  end
end
defmodule Temper.Orm.AndCondition do
  def __temper_supertypes__() do
    [Temper.Orm.AndCondition, Temper.Orm.WhereClause]
  end
  def get_condition(this) do
    TemperCore.Heap.get(this, :u_condition)
  end
  def keyword(_this) do
    "AND"
  end
  def new(u_condition) do
    Temper.Orm.__temper_init__()
    this = TemperCore.Heap.new(Temper.Orm.AndCondition, %{:u_condition => nil})
    TemperCore.Heap.put(this, :u_condition, u_condition)
    this
  end
end
defmodule Temper.Orm.OrCondition do
  def __temper_supertypes__() do
    [Temper.Orm.OrCondition, Temper.Orm.WhereClause]
  end
  def get_condition(this) do
    TemperCore.Heap.get(this, :u_condition)
  end
  def keyword(_this) do
    "OR"
  end
  def new(u_condition) do
    Temper.Orm.__temper_init__()
    this = TemperCore.Heap.new(Temper.Orm.OrCondition, %{:u_condition => nil})
    TemperCore.Heap.put(this, :u_condition, u_condition)
    this
  end
end
defmodule Temper.Orm.Query do
  def __temper_supertypes__() do
    [Temper.Orm.Query]
  end
  def where(this, condition) do
    nb = TemperCore.List.to_builder(TemperCore.Heap.get(this, :conditions))
    TemperCore.List.add(nb, Temper.Orm.AndCondition.new(condition))
    Temper.Orm.Query.new(TemperCore.Heap.get(this, :tableName), TemperCore.List.to_list(nb), TemperCore.Heap.get(this, :selectedFields), TemperCore.Heap.get(this, :orderClauses), TemperCore.Heap.get(this, :limitVal), TemperCore.Heap.get(this, :offsetVal), TemperCore.Heap.get(this, :joinClauses), TemperCore.Heap.get(this, :groupByFields), TemperCore.Heap.get(this, :havingConditions), TemperCore.Heap.get(this, :isDistinct), TemperCore.Heap.get(this, :selectExprs), TemperCore.Heap.get(this, :lockMode))
  end
  def orWhere(this, condition) do
    nb = TemperCore.List.to_builder(TemperCore.Heap.get(this, :conditions))
    TemperCore.List.add(nb, Temper.Orm.OrCondition.new(condition))
    Temper.Orm.Query.new(TemperCore.Heap.get(this, :tableName), TemperCore.List.to_list(nb), TemperCore.Heap.get(this, :selectedFields), TemperCore.Heap.get(this, :orderClauses), TemperCore.Heap.get(this, :limitVal), TemperCore.Heap.get(this, :offsetVal), TemperCore.Heap.get(this, :joinClauses), TemperCore.Heap.get(this, :groupByFields), TemperCore.Heap.get(this, :havingConditions), TemperCore.Heap.get(this, :isDistinct), TemperCore.Heap.get(this, :selectExprs), TemperCore.Heap.get(this, :lockMode))
  end
  def whereNull(this, field) do
    b = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(b, TemperCore.call(field, :get_sqlValue, []))
    Temper.Orm.SqlBuilder.appendSafe(b, " IS NULL")
    Temper.Orm.Query.where(this, Temper.Orm.SqlBuilder.get_accumulated(b))
  end
  def whereNotNull(this, field) do
    b = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(b, TemperCore.call(field, :get_sqlValue, []))
    Temper.Orm.SqlBuilder.appendSafe(b, " IS NOT NULL")
    Temper.Orm.Query.where(this, Temper.Orm.SqlBuilder.get_accumulated(b))
  end
  def whereIn(this, field, values) do
    try do
      _return = nil
      return = if true do
        if TemperCore.List.is_empty(values) do
          b2 = Temper.Orm.SqlBuilder.new()
          Temper.Orm.SqlBuilder.appendSafe(b2, "1 = 0")
          return = Temper.Orm.Query.where(this, Temper.Orm.SqlBuilder.get_accumulated(b2))
          return
        else
          b1 = Temper.Orm.SqlBuilder.new()
          Temper.Orm.SqlBuilder.appendSafe(b1, TemperCore.call(field, :get_sqlValue, []))
          Temper.Orm.SqlBuilder.appendSafe(b1, " IN (")
          Temper.Orm.SqlBuilder.appendPart(b1, TemperCore.List.get(values, 0))
          i = 1
          ex_loop_2 = fn ex_loop_2, i ->
            if i < TemperCore.List.length(values) do
              Temper.Orm.SqlBuilder.appendSafe(b1, ", ")
              Temper.Orm.SqlBuilder.appendPart(b1, TemperCore.List.get(values, i))
              i = TemperCore.int32(i + 1)
              ex_loop_2.(ex_loop_2, i)
            else
              i
            end
          end
          _i = ex_loop_2.(ex_loop_2, i)
          Temper.Orm.SqlBuilder.appendSafe(b1, ")")
          throw({:temper_return, :ex_return_0, Temper.Orm.Query.where(this, Temper.Orm.SqlBuilder.get_accumulated(b1))})
        end
      end
      return
    catch
      {:temper_return, :ex_return_0, ex_value_4} ->
        ex_value_4
    end
  end
  def whereInSubquery(this, field, sub) do
    b = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(b, TemperCore.call(field, :get_sqlValue, []))
    Temper.Orm.SqlBuilder.appendSafe(b, " IN (")
    Temper.Orm.SqlBuilder.appendFragment(b, Temper.Orm.Query.toSql(sub))
    Temper.Orm.SqlBuilder.appendSafe(b, ")")
    Temper.Orm.Query.where(this, Temper.Orm.SqlBuilder.get_accumulated(b))
  end
  def whereNot(this, condition) do
    b = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(b, "NOT (")
    Temper.Orm.SqlBuilder.appendFragment(b, condition)
    Temper.Orm.SqlBuilder.appendSafe(b, ")")
    Temper.Orm.Query.where(this, Temper.Orm.SqlBuilder.get_accumulated(b))
  end
  def whereBetween(this, field, low, high) do
    b = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(b, TemperCore.call(field, :get_sqlValue, []))
    Temper.Orm.SqlBuilder.appendSafe(b, " BETWEEN ")
    Temper.Orm.SqlBuilder.appendPart(b, low)
    Temper.Orm.SqlBuilder.appendSafe(b, " AND ")
    Temper.Orm.SqlBuilder.appendPart(b, high)
    Temper.Orm.Query.where(this, Temper.Orm.SqlBuilder.get_accumulated(b))
  end
  def whereLike(this, field, pattern) do
    b = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(b, TemperCore.call(field, :get_sqlValue, []))
    Temper.Orm.SqlBuilder.appendSafe(b, " LIKE ")
    Temper.Orm.SqlBuilder.appendString(b, pattern)
    Temper.Orm.Query.where(this, Temper.Orm.SqlBuilder.get_accumulated(b))
  end
  def whereILike(this, field, pattern) do
    b = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(b, TemperCore.call(field, :get_sqlValue, []))
    Temper.Orm.SqlBuilder.appendSafe(b, " ILIKE ")
    Temper.Orm.SqlBuilder.appendString(b, pattern)
    Temper.Orm.Query.where(this, Temper.Orm.SqlBuilder.get_accumulated(b))
  end
  def select(this, fields) do
    Temper.Orm.Query.new(TemperCore.Heap.get(this, :tableName), TemperCore.Heap.get(this, :conditions), fields, TemperCore.Heap.get(this, :orderClauses), TemperCore.Heap.get(this, :limitVal), TemperCore.Heap.get(this, :offsetVal), TemperCore.Heap.get(this, :joinClauses), TemperCore.Heap.get(this, :groupByFields), TemperCore.Heap.get(this, :havingConditions), TemperCore.Heap.get(this, :isDistinct), TemperCore.Heap.get(this, :selectExprs), TemperCore.Heap.get(this, :lockMode))
  end
  def selectExpr(this, exprs) do
    Temper.Orm.Query.new(TemperCore.Heap.get(this, :tableName), TemperCore.Heap.get(this, :conditions), TemperCore.Heap.get(this, :selectedFields), TemperCore.Heap.get(this, :orderClauses), TemperCore.Heap.get(this, :limitVal), TemperCore.Heap.get(this, :offsetVal), TemperCore.Heap.get(this, :joinClauses), TemperCore.Heap.get(this, :groupByFields), TemperCore.Heap.get(this, :havingConditions), TemperCore.Heap.get(this, :isDistinct), exprs, TemperCore.Heap.get(this, :lockMode))
  end
  def orderBy(this, field, ascending) do
    nb = TemperCore.List.to_builder(TemperCore.Heap.get(this, :orderClauses))
    TemperCore.List.add(nb, Temper.Orm.OrderClause.new(field, ascending, nil))
    Temper.Orm.Query.new(TemperCore.Heap.get(this, :tableName), TemperCore.Heap.get(this, :conditions), TemperCore.Heap.get(this, :selectedFields), TemperCore.List.to_list(nb), TemperCore.Heap.get(this, :limitVal), TemperCore.Heap.get(this, :offsetVal), TemperCore.Heap.get(this, :joinClauses), TemperCore.Heap.get(this, :groupByFields), TemperCore.Heap.get(this, :havingConditions), TemperCore.Heap.get(this, :isDistinct), TemperCore.Heap.get(this, :selectExprs), TemperCore.Heap.get(this, :lockMode))
  end
  def orderByNulls(this, field, ascending, nulls) do
    nb = TemperCore.List.to_builder(TemperCore.Heap.get(this, :orderClauses))
    TemperCore.List.add(nb, Temper.Orm.OrderClause.new(field, ascending, nulls))
    Temper.Orm.Query.new(TemperCore.Heap.get(this, :tableName), TemperCore.Heap.get(this, :conditions), TemperCore.Heap.get(this, :selectedFields), TemperCore.List.to_list(nb), TemperCore.Heap.get(this, :limitVal), TemperCore.Heap.get(this, :offsetVal), TemperCore.Heap.get(this, :joinClauses), TemperCore.Heap.get(this, :groupByFields), TemperCore.Heap.get(this, :havingConditions), TemperCore.Heap.get(this, :isDistinct), TemperCore.Heap.get(this, :selectExprs), TemperCore.Heap.get(this, :lockMode))
  end
  def limit(this, n) do
    if n < 0 do
      raise(TemperCore.Bubble)
    else
      Temper.Orm.Query.new(TemperCore.Heap.get(this, :tableName), TemperCore.Heap.get(this, :conditions), TemperCore.Heap.get(this, :selectedFields), TemperCore.Heap.get(this, :orderClauses), n, TemperCore.Heap.get(this, :offsetVal), TemperCore.Heap.get(this, :joinClauses), TemperCore.Heap.get(this, :groupByFields), TemperCore.Heap.get(this, :havingConditions), TemperCore.Heap.get(this, :isDistinct), TemperCore.Heap.get(this, :selectExprs), TemperCore.Heap.get(this, :lockMode))
    end
  end
  def offset(this, n) do
    if n < 0 do
      raise(TemperCore.Bubble)
    else
      Temper.Orm.Query.new(TemperCore.Heap.get(this, :tableName), TemperCore.Heap.get(this, :conditions), TemperCore.Heap.get(this, :selectedFields), TemperCore.Heap.get(this, :orderClauses), TemperCore.Heap.get(this, :limitVal), n, TemperCore.Heap.get(this, :joinClauses), TemperCore.Heap.get(this, :groupByFields), TemperCore.Heap.get(this, :havingConditions), TemperCore.Heap.get(this, :isDistinct), TemperCore.Heap.get(this, :selectExprs), TemperCore.Heap.get(this, :lockMode))
    end
  end
  def join(this, joinType, table, onCondition) do
    nb = TemperCore.List.to_builder(TemperCore.Heap.get(this, :joinClauses))
    TemperCore.List.add(nb, Temper.Orm.JoinClause.new(joinType, table, onCondition))
    Temper.Orm.Query.new(TemperCore.Heap.get(this, :tableName), TemperCore.Heap.get(this, :conditions), TemperCore.Heap.get(this, :selectedFields), TemperCore.Heap.get(this, :orderClauses), TemperCore.Heap.get(this, :limitVal), TemperCore.Heap.get(this, :offsetVal), TemperCore.List.to_list(nb), TemperCore.Heap.get(this, :groupByFields), TemperCore.Heap.get(this, :havingConditions), TemperCore.Heap.get(this, :isDistinct), TemperCore.Heap.get(this, :selectExprs), TemperCore.Heap.get(this, :lockMode))
  end
  def innerJoin(this, table, onCondition) do
    Temper.Orm.Query.join(this, Temper.Orm.InnerJoin.new(), table, onCondition)
  end
  def leftJoin(this, table, onCondition) do
    Temper.Orm.Query.join(this, Temper.Orm.LeftJoin.new(), table, onCondition)
  end
  def rightJoin(this, table, onCondition) do
    Temper.Orm.Query.join(this, Temper.Orm.RightJoin.new(), table, onCondition)
  end
  def fullJoin(this, table, onCondition) do
    Temper.Orm.Query.join(this, Temper.Orm.FullJoin.new(), table, onCondition)
  end
  def crossJoin(this, table) do
    nb = TemperCore.List.to_builder(TemperCore.Heap.get(this, :joinClauses))
    TemperCore.List.add(nb, Temper.Orm.JoinClause.new(Temper.Orm.CrossJoin.new(), table, nil))
    Temper.Orm.Query.new(TemperCore.Heap.get(this, :tableName), TemperCore.Heap.get(this, :conditions), TemperCore.Heap.get(this, :selectedFields), TemperCore.Heap.get(this, :orderClauses), TemperCore.Heap.get(this, :limitVal), TemperCore.Heap.get(this, :offsetVal), TemperCore.List.to_list(nb), TemperCore.Heap.get(this, :groupByFields), TemperCore.Heap.get(this, :havingConditions), TemperCore.Heap.get(this, :isDistinct), TemperCore.Heap.get(this, :selectExprs), TemperCore.Heap.get(this, :lockMode))
  end
  def groupBy(this, field) do
    nb = TemperCore.List.to_builder(TemperCore.Heap.get(this, :groupByFields))
    TemperCore.List.add(nb, field)
    Temper.Orm.Query.new(TemperCore.Heap.get(this, :tableName), TemperCore.Heap.get(this, :conditions), TemperCore.Heap.get(this, :selectedFields), TemperCore.Heap.get(this, :orderClauses), TemperCore.Heap.get(this, :limitVal), TemperCore.Heap.get(this, :offsetVal), TemperCore.Heap.get(this, :joinClauses), TemperCore.List.to_list(nb), TemperCore.Heap.get(this, :havingConditions), TemperCore.Heap.get(this, :isDistinct), TemperCore.Heap.get(this, :selectExprs), TemperCore.Heap.get(this, :lockMode))
  end
  def having(this, condition) do
    nb = TemperCore.List.to_builder(TemperCore.Heap.get(this, :havingConditions))
    TemperCore.List.add(nb, Temper.Orm.AndCondition.new(condition))
    Temper.Orm.Query.new(TemperCore.Heap.get(this, :tableName), TemperCore.Heap.get(this, :conditions), TemperCore.Heap.get(this, :selectedFields), TemperCore.Heap.get(this, :orderClauses), TemperCore.Heap.get(this, :limitVal), TemperCore.Heap.get(this, :offsetVal), TemperCore.Heap.get(this, :joinClauses), TemperCore.Heap.get(this, :groupByFields), TemperCore.List.to_list(nb), TemperCore.Heap.get(this, :isDistinct), TemperCore.Heap.get(this, :selectExprs), TemperCore.Heap.get(this, :lockMode))
  end
  def orHaving(this, condition) do
    nb = TemperCore.List.to_builder(TemperCore.Heap.get(this, :havingConditions))
    TemperCore.List.add(nb, Temper.Orm.OrCondition.new(condition))
    Temper.Orm.Query.new(TemperCore.Heap.get(this, :tableName), TemperCore.Heap.get(this, :conditions), TemperCore.Heap.get(this, :selectedFields), TemperCore.Heap.get(this, :orderClauses), TemperCore.Heap.get(this, :limitVal), TemperCore.Heap.get(this, :offsetVal), TemperCore.Heap.get(this, :joinClauses), TemperCore.Heap.get(this, :groupByFields), TemperCore.List.to_list(nb), TemperCore.Heap.get(this, :isDistinct), TemperCore.Heap.get(this, :selectExprs), TemperCore.Heap.get(this, :lockMode))
  end
  def distinct(this) do
    Temper.Orm.Query.new(TemperCore.Heap.get(this, :tableName), TemperCore.Heap.get(this, :conditions), TemperCore.Heap.get(this, :selectedFields), TemperCore.Heap.get(this, :orderClauses), TemperCore.Heap.get(this, :limitVal), TemperCore.Heap.get(this, :offsetVal), TemperCore.Heap.get(this, :joinClauses), TemperCore.Heap.get(this, :groupByFields), TemperCore.Heap.get(this, :havingConditions), true, TemperCore.Heap.get(this, :selectExprs), TemperCore.Heap.get(this, :lockMode))
  end
  def lock(this, mode) do
    Temper.Orm.Query.new(TemperCore.Heap.get(this, :tableName), TemperCore.Heap.get(this, :conditions), TemperCore.Heap.get(this, :selectedFields), TemperCore.Heap.get(this, :orderClauses), TemperCore.Heap.get(this, :limitVal), TemperCore.Heap.get(this, :offsetVal), TemperCore.Heap.get(this, :joinClauses), TemperCore.Heap.get(this, :groupByFields), TemperCore.Heap.get(this, :havingConditions), TemperCore.Heap.get(this, :isDistinct), TemperCore.Heap.get(this, :selectExprs), mode)
  end
  def toSql(this1) do
    b = Temper.Orm.SqlBuilder.new()
    if TemperCore.Heap.get(this1, :isDistinct) do
      Temper.Orm.SqlBuilder.appendSafe(b, "SELECT DISTINCT ")
      nil
    else
      Temper.Orm.SqlBuilder.appendSafe(b, "SELECT ")
      nil
    end
    cond do
      not TemperCore.List.is_empty(TemperCore.Heap.get(this1, :selectExprs)) ->
        Temper.Orm.SqlBuilder.appendFragment(b, TemperCore.List.get(TemperCore.Heap.get(this1, :selectExprs), 0))
        i1 = 1
        ex_loop_1 = fn ex_loop_1, i1 ->
          if i1 < TemperCore.List.length(TemperCore.Heap.get(this1, :selectExprs)) do
            Temper.Orm.SqlBuilder.appendSafe(b, ", ")
            Temper.Orm.SqlBuilder.appendFragment(b, TemperCore.List.get(TemperCore.Heap.get(this1, :selectExprs), i1))
            i1 = TemperCore.int32(i1 + 1)
            ex_loop_1.(ex_loop_1, i1)
          else
            i1
          end
        end
        _i1 = ex_loop_1.(ex_loop_1, i1)
        nil
      TemperCore.List.is_empty(TemperCore.Heap.get(this1, :selectedFields)) ->
        Temper.Orm.SqlBuilder.appendSafe(b, "*")
        nil
      true ->
        fn_ = fn f ->
          TemperCore.call(f, :get_sqlValue, [])
        end
        Temper.Orm.SqlBuilder.appendSafe(b, TemperCore.List.join(TemperCore.Heap.get(this1, :selectedFields), ", ", fn_))
        nil
    end
    Temper.Orm.SqlBuilder.appendSafe(b, " FROM ")
    Temper.Orm.SqlBuilder.appendSafe(b, TemperCore.call(TemperCore.Heap.get(this1, :tableName), :get_sqlValue, []))
    Temper.Orm.renderJoins(b, TemperCore.Heap.get(this1, :joinClauses))
    Temper.Orm.renderWhere(b, TemperCore.Heap.get(this1, :conditions))
    Temper.Orm.renderGroupBy(b, TemperCore.Heap.get(this1, :groupByFields))
    Temper.Orm.renderHaving(b, TemperCore.Heap.get(this1, :havingConditions))
    if not TemperCore.List.is_empty(TemperCore.Heap.get(this1, :orderClauses)) do
      Temper.Orm.SqlBuilder.appendSafe(b, " ORDER BY ")
      first = true
      this2 = TemperCore.Heap.get(this1, :orderClauses)
      n = TemperCore.List.length(this2)
      i2 = 0
      ex_loop_4 = fn ex_loop_4, first, i2 ->
        if i2 < n do
          el = TemperCore.List.get(this2, i2)
          i2 = TemperCore.int32(i2 + 1)
          orc = el
          _t = nil
          if not first do
            Temper.Orm.SqlBuilder.appendSafe(b, ", ")
            nil
          else
            nil
          end
          first = false
          Temper.Orm.SqlBuilder.appendSafe(b, TemperCore.call(Temper.Orm.OrderClause.get_field(orc), :get_sqlValue, []))
          t = if Temper.Orm.OrderClause.get_ascending(orc) do
            t = " ASC"
            t
          else
            t = " DESC"
            t
          end
          Temper.Orm.SqlBuilder.appendSafe(b, t)
          np = Temper.Orm.OrderClause.get_nullsPos(orc)
          if not (np === nil) do
            Temper.Orm.SqlBuilder.appendSafe(b, TemperCore.call(np, :keyword, []))
            ex_loop_4.(ex_loop_4, first, i2)
          else
            ex_loop_4.(ex_loop_4, first, i2)
          end
        else
          {first, i2}
        end
      end
      {_first, _i2} = ex_loop_4.(ex_loop_4, first, i2)
      nil
    else
      nil
    end
    lv1 = TemperCore.Heap.get(this1, :limitVal)
    if not (lv1 === nil) do
      lv2 = lv1
      Temper.Orm.SqlBuilder.appendSafe(b, " LIMIT ")
      Temper.Orm.SqlBuilder.appendInt32(b, lv2)
      nil
    else
      nil
    end
    ov1 = TemperCore.Heap.get(this1, :offsetVal)
    if not (ov1 === nil) do
      ov2 = ov1
      Temper.Orm.SqlBuilder.appendSafe(b, " OFFSET ")
      Temper.Orm.SqlBuilder.appendInt32(b, ov2)
      nil
    else
      nil
    end
    lm = TemperCore.Heap.get(this1, :lockMode)
    if not (lm === nil) do
      Temper.Orm.SqlBuilder.appendSafe(b, TemperCore.call(lm, :keyword, []))
      nil
    else
      nil
    end
    Temper.Orm.SqlBuilder.get_accumulated(b)
  end
  def countSql(this) do
    b = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(b, "SELECT COUNT(*) FROM ")
    Temper.Orm.SqlBuilder.appendSafe(b, TemperCore.call(TemperCore.Heap.get(this, :tableName), :get_sqlValue, []))
    Temper.Orm.renderJoins(b, TemperCore.Heap.get(this, :joinClauses))
    Temper.Orm.renderWhere(b, TemperCore.Heap.get(this, :conditions))
    Temper.Orm.renderGroupBy(b, TemperCore.Heap.get(this, :groupByFields))
    Temper.Orm.renderHaving(b, TemperCore.Heap.get(this, :havingConditions))
    Temper.Orm.SqlBuilder.get_accumulated(b)
  end
  def safeToSql(this, defaultLimit) do
    cond do
      defaultLimit < 0 ->
        raise(TemperCore.Bubble)
      not (TemperCore.Heap.get(this, :limitVal) === nil) ->
        Temper.Orm.Query.toSql(this)
      true ->
        t = Temper.Orm.Query.limit(this, defaultLimit)
        Temper.Orm.Query.toSql(t)
    end
  end
  def new(tableName, conditions, selectedFields, orderClauses, limitVal, offsetVal, joinClauses, groupByFields, havingConditions, isDistinct, selectExprs, lockMode) do
    Temper.Orm.__temper_init__()
    this = TemperCore.Heap.new(Temper.Orm.Query, %{:tableName => nil, :conditions => nil, :selectedFields => nil, :orderClauses => nil, :limitVal => nil, :offsetVal => nil, :joinClauses => nil, :groupByFields => nil, :havingConditions => nil, :isDistinct => nil, :selectExprs => nil, :lockMode => nil})
    TemperCore.Heap.put(this, :tableName, tableName)
    TemperCore.Heap.put(this, :conditions, conditions)
    TemperCore.Heap.put(this, :selectedFields, selectedFields)
    TemperCore.Heap.put(this, :orderClauses, orderClauses)
    TemperCore.Heap.put(this, :limitVal, limitVal)
    TemperCore.Heap.put(this, :offsetVal, offsetVal)
    TemperCore.Heap.put(this, :joinClauses, joinClauses)
    TemperCore.Heap.put(this, :groupByFields, groupByFields)
    TemperCore.Heap.put(this, :havingConditions, havingConditions)
    TemperCore.Heap.put(this, :isDistinct, isDistinct)
    TemperCore.Heap.put(this, :selectExprs, selectExprs)
    TemperCore.Heap.put(this, :lockMode, lockMode)
    this
  end
  def get_tableName(this) do
    TemperCore.Heap.get(this, :tableName)
  end
  def get_conditions(this) do
    TemperCore.Heap.get(this, :conditions)
  end
  def get_selectedFields(this) do
    TemperCore.Heap.get(this, :selectedFields)
  end
  def get_orderClauses(this) do
    TemperCore.Heap.get(this, :orderClauses)
  end
  def get_limitVal(this) do
    TemperCore.Heap.get(this, :limitVal)
  end
  def get_offsetVal(this) do
    TemperCore.Heap.get(this, :offsetVal)
  end
  def get_joinClauses(this) do
    TemperCore.Heap.get(this, :joinClauses)
  end
  def get_groupByFields(this) do
    TemperCore.Heap.get(this, :groupByFields)
  end
  def get_havingConditions(this) do
    TemperCore.Heap.get(this, :havingConditions)
  end
  def get_isDistinct(this) do
    TemperCore.Heap.get(this, :isDistinct)
  end
  def get_selectExprs(this) do
    TemperCore.Heap.get(this, :selectExprs)
  end
  def get_lockMode(this) do
    TemperCore.Heap.get(this, :lockMode)
  end
end
defmodule Temper.Orm.SetClause do
  def __temper_supertypes__() do
    [Temper.Orm.SetClause]
  end
  def new(field, value) do
    Temper.Orm.__temper_init__()
    this = TemperCore.Heap.new(Temper.Orm.SetClause, %{:field => nil, :value => nil})
    TemperCore.Heap.put(this, :field, field)
    TemperCore.Heap.put(this, :value, value)
    this
  end
  def get_field(this) do
    TemperCore.Heap.get(this, :field)
  end
  def get_value(this) do
    TemperCore.Heap.get(this, :value)
  end
end
defmodule Temper.Orm.UpdateQuery do
  def __temper_supertypes__() do
    [Temper.Orm.UpdateQuery]
  end
  def set(this, field, value) do
    nb = TemperCore.List.to_builder(TemperCore.Heap.get(this, :setClauses))
    TemperCore.List.add(nb, Temper.Orm.SetClause.new(field, value))
    Temper.Orm.UpdateQuery.new(TemperCore.Heap.get(this, :tableName), TemperCore.List.to_list(nb), TemperCore.Heap.get(this, :conditions), TemperCore.Heap.get(this, :limitVal))
  end
  def where(this, condition) do
    nb = TemperCore.List.to_builder(TemperCore.Heap.get(this, :conditions))
    TemperCore.List.add(nb, Temper.Orm.AndCondition.new(condition))
    Temper.Orm.UpdateQuery.new(TemperCore.Heap.get(this, :tableName), TemperCore.Heap.get(this, :setClauses), TemperCore.List.to_list(nb), TemperCore.Heap.get(this, :limitVal))
  end
  def orWhere(this, condition) do
    nb = TemperCore.List.to_builder(TemperCore.Heap.get(this, :conditions))
    TemperCore.List.add(nb, Temper.Orm.OrCondition.new(condition))
    Temper.Orm.UpdateQuery.new(TemperCore.Heap.get(this, :tableName), TemperCore.Heap.get(this, :setClauses), TemperCore.List.to_list(nb), TemperCore.Heap.get(this, :limitVal))
  end
  def limit(this, n) do
    if n < 0 do
      raise(TemperCore.Bubble)
    else
      Temper.Orm.UpdateQuery.new(TemperCore.Heap.get(this, :tableName), TemperCore.Heap.get(this, :setClauses), TemperCore.Heap.get(this, :conditions), n)
    end
  end
  def toSql(this) do
    cond do
      TemperCore.List.is_empty(TemperCore.Heap.get(this, :conditions)) ->
        raise(TemperCore.Bubble)
      TemperCore.List.is_empty(TemperCore.Heap.get(this, :setClauses)) ->
        raise(TemperCore.Bubble)
      true ->
        b = Temper.Orm.SqlBuilder.new()
        Temper.Orm.SqlBuilder.appendSafe(b, "UPDATE ")
        Temper.Orm.SqlBuilder.appendSafe(b, TemperCore.call(TemperCore.Heap.get(this, :tableName), :get_sqlValue, []))
        Temper.Orm.SqlBuilder.appendSafe(b, " SET ")
        Temper.Orm.SqlBuilder.appendSafe(b, TemperCore.call(Temper.Orm.SetClause.get_field(TemperCore.List.get(TemperCore.Heap.get(this, :setClauses), 0)), :get_sqlValue, []))
        Temper.Orm.SqlBuilder.appendSafe(b, " = ")
        Temper.Orm.SqlBuilder.appendPart(b, Temper.Orm.SetClause.get_value(TemperCore.List.get(TemperCore.Heap.get(this, :setClauses), 0)))
        i = 1
        ex_loop_1 = fn ex_loop_1, i ->
          if i < TemperCore.List.length(TemperCore.Heap.get(this, :setClauses)) do
            Temper.Orm.SqlBuilder.appendSafe(b, ", ")
            Temper.Orm.SqlBuilder.appendSafe(b, TemperCore.call(Temper.Orm.SetClause.get_field(TemperCore.List.get(TemperCore.Heap.get(this, :setClauses), i)), :get_sqlValue, []))
            Temper.Orm.SqlBuilder.appendSafe(b, " = ")
            Temper.Orm.SqlBuilder.appendPart(b, Temper.Orm.SetClause.get_value(TemperCore.List.get(TemperCore.Heap.get(this, :setClauses), i)))
            i = TemperCore.int32(i + 1)
            ex_loop_1.(ex_loop_1, i)
          else
            i
          end
        end
        _i = ex_loop_1.(ex_loop_1, i)
        Temper.Orm.renderWhere(b, TemperCore.Heap.get(this, :conditions))
        lv1 = TemperCore.Heap.get(this, :limitVal)
        if not (lv1 === nil) do
          lv2 = lv1
          Temper.Orm.SqlBuilder.appendSafe(b, " LIMIT ")
          Temper.Orm.SqlBuilder.appendInt32(b, lv2)
          nil
        else
          nil
        end
        Temper.Orm.SqlBuilder.get_accumulated(b)
    end
  end
  def new(tableName, setClauses, conditions, limitVal) do
    Temper.Orm.__temper_init__()
    this = TemperCore.Heap.new(Temper.Orm.UpdateQuery, %{:tableName => nil, :setClauses => nil, :conditions => nil, :limitVal => nil})
    TemperCore.Heap.put(this, :tableName, tableName)
    TemperCore.Heap.put(this, :setClauses, setClauses)
    TemperCore.Heap.put(this, :conditions, conditions)
    TemperCore.Heap.put(this, :limitVal, limitVal)
    this
  end
  def get_tableName(this) do
    TemperCore.Heap.get(this, :tableName)
  end
  def get_setClauses(this) do
    TemperCore.Heap.get(this, :setClauses)
  end
  def get_conditions(this) do
    TemperCore.Heap.get(this, :conditions)
  end
  def get_limitVal(this) do
    TemperCore.Heap.get(this, :limitVal)
  end
end
defmodule Temper.Orm.DeleteQuery do
  def __temper_supertypes__() do
    [Temper.Orm.DeleteQuery]
  end
  def where(this, condition) do
    nb = TemperCore.List.to_builder(TemperCore.Heap.get(this, :conditions))
    TemperCore.List.add(nb, Temper.Orm.AndCondition.new(condition))
    Temper.Orm.DeleteQuery.new(TemperCore.Heap.get(this, :tableName), TemperCore.List.to_list(nb), TemperCore.Heap.get(this, :limitVal))
  end
  def orWhere(this, condition) do
    nb = TemperCore.List.to_builder(TemperCore.Heap.get(this, :conditions))
    TemperCore.List.add(nb, Temper.Orm.OrCondition.new(condition))
    Temper.Orm.DeleteQuery.new(TemperCore.Heap.get(this, :tableName), TemperCore.List.to_list(nb), TemperCore.Heap.get(this, :limitVal))
  end
  def limit(this, n) do
    if n < 0 do
      raise(TemperCore.Bubble)
    else
      Temper.Orm.DeleteQuery.new(TemperCore.Heap.get(this, :tableName), TemperCore.Heap.get(this, :conditions), n)
    end
  end
  def toSql(this) do
    if TemperCore.List.is_empty(TemperCore.Heap.get(this, :conditions)) do
      raise(TemperCore.Bubble)
    else
      b = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(b, "DELETE FROM ")
      Temper.Orm.SqlBuilder.appendSafe(b, TemperCore.call(TemperCore.Heap.get(this, :tableName), :get_sqlValue, []))
      Temper.Orm.renderWhere(b, TemperCore.Heap.get(this, :conditions))
      lv1 = TemperCore.Heap.get(this, :limitVal)
      if not (lv1 === nil) do
        lv2 = lv1
        Temper.Orm.SqlBuilder.appendSafe(b, " LIMIT ")
        Temper.Orm.SqlBuilder.appendInt32(b, lv2)
        nil
      else
        nil
      end
      Temper.Orm.SqlBuilder.get_accumulated(b)
    end
  end
  def new(tableName, conditions, limitVal) do
    Temper.Orm.__temper_init__()
    this = TemperCore.Heap.new(Temper.Orm.DeleteQuery, %{:tableName => nil, :conditions => nil, :limitVal => nil})
    TemperCore.Heap.put(this, :tableName, tableName)
    TemperCore.Heap.put(this, :conditions, conditions)
    TemperCore.Heap.put(this, :limitVal, limitVal)
    this
  end
  def get_tableName(this) do
    TemperCore.Heap.get(this, :tableName)
  end
  def get_conditions(this) do
    TemperCore.Heap.get(this, :conditions)
  end
  def get_limitVal(this) do
    TemperCore.Heap.get(this, :limitVal)
  end
end
defmodule Temper.Orm.SafeIdentifier do
  def __temper_supertypes__() do
    [Temper.Orm.SafeIdentifier]
  end
  def get_sqlValue(_this) do
    raise(TemperCore.Panic)
  end
end
defmodule Temper.Orm.ValidatedIdentifier do
  def __temper_supertypes__() do
    [Temper.Orm.ValidatedIdentifier, Temper.Orm.SafeIdentifier]
  end
  def get_sqlValue(this) do
    TemperCore.Heap.get(this, :u_value)
  end
  def new(u_value) do
    this = TemperCore.Heap.new(Temper.Orm.ValidatedIdentifier, %{:u_value => nil})
    TemperCore.Heap.put(this, :u_value, u_value)
    this
  end
end
defmodule Temper.Orm.FieldType do
  def __temper_supertypes__() do
    [Temper.Orm.FieldType]
  end
end
defmodule Temper.Orm.StringField do
  def __temper_supertypes__() do
    [Temper.Orm.StringField, Temper.Orm.FieldType]
  end
  def new() do
    Temper.Orm.__temper_init__()
    this = TemperCore.Heap.new(Temper.Orm.StringField, %{})
    this
  end
end
defmodule Temper.Orm.IntField do
  def __temper_supertypes__() do
    [Temper.Orm.IntField, Temper.Orm.FieldType]
  end
  def new() do
    Temper.Orm.__temper_init__()
    this = TemperCore.Heap.new(Temper.Orm.IntField, %{})
    this
  end
end
defmodule Temper.Orm.Int64Field do
  def __temper_supertypes__() do
    [Temper.Orm.Int64Field, Temper.Orm.FieldType]
  end
  def new() do
    Temper.Orm.__temper_init__()
    this = TemperCore.Heap.new(Temper.Orm.Int64Field, %{})
    this
  end
end
defmodule Temper.Orm.FloatField do
  def __temper_supertypes__() do
    [Temper.Orm.FloatField, Temper.Orm.FieldType]
  end
  def new() do
    Temper.Orm.__temper_init__()
    this = TemperCore.Heap.new(Temper.Orm.FloatField, %{})
    this
  end
end
defmodule Temper.Orm.BoolField do
  def __temper_supertypes__() do
    [Temper.Orm.BoolField, Temper.Orm.FieldType]
  end
  def new() do
    Temper.Orm.__temper_init__()
    this = TemperCore.Heap.new(Temper.Orm.BoolField, %{})
    this
  end
end
defmodule Temper.Orm.DateField do
  def __temper_supertypes__() do
    [Temper.Orm.DateField, Temper.Orm.FieldType]
  end
  def new() do
    Temper.Orm.__temper_init__()
    this = TemperCore.Heap.new(Temper.Orm.DateField, %{})
    this
  end
end
defmodule Temper.Orm.FieldDef do
  def __temper_supertypes__() do
    [Temper.Orm.FieldDef]
  end
  def new(name, fieldType, nullable, defaultValue, virtual) do
    Temper.Orm.__temper_init__()
    this = TemperCore.Heap.new(Temper.Orm.FieldDef, %{:name => nil, :fieldType => nil, :nullable => nil, :defaultValue => nil, :virtual => nil})
    TemperCore.Heap.put(this, :name, name)
    TemperCore.Heap.put(this, :fieldType, fieldType)
    TemperCore.Heap.put(this, :nullable, nullable)
    TemperCore.Heap.put(this, :defaultValue, defaultValue)
    TemperCore.Heap.put(this, :virtual, virtual)
    this
  end
  def get_name(this) do
    TemperCore.Heap.get(this, :name)
  end
  def get_fieldType(this) do
    TemperCore.Heap.get(this, :fieldType)
  end
  def get_nullable(this) do
    TemperCore.Heap.get(this, :nullable)
  end
  def get_defaultValue(this) do
    TemperCore.Heap.get(this, :defaultValue)
  end
  def get_virtual(this) do
    TemperCore.Heap.get(this, :virtual)
  end
end
defmodule Temper.Orm.TableDef do
  def __temper_supertypes__() do
    [Temper.Orm.TableDef]
  end
  def field(this1, name) do
    return = nil
    return = try do
      this2 = TemperCore.Heap.get(this1, :fields)
      n = TemperCore.List.length(this2)
      i = 0
      ex_loop_2 = fn ex_loop_2, i, return ->
        if i < n do
          el = TemperCore.List.get(this2, i)
          i = TemperCore.int32(i + 1)
          f = el
          if TemperCore.call(Temper.Orm.FieldDef.get_name(f), :get_sqlValue, []) == name do
            return = f
            throw({:temper_break, :ex_block_1, return})
          else
            ex_loop_2.(ex_loop_2, i, return)
          end
        else
          {i, return}
        end
      end
      {_i, _return} = ex_loop_2.(ex_loop_2, i, return)
      raise(TemperCore.Bubble)
    catch
      {:temper_break, :ex_block_1, ex_vars_4} ->
        ex_vars_4
    end
    return
  end
  def pkName(this) do
    try do
      _return = nil
      return = if true do
        pk = TemperCore.Heap.get(this, :primaryKey)
        if not (pk === nil) do
          return = TemperCore.call(pk, :get_sqlValue, [])
          return
        else
          throw({:temper_return, :ex_return_0, "id"})
        end
      end
      return
    catch
      {:temper_return, :ex_return_0, ex_value_2} ->
        ex_value_2
    end
  end
  def new(tableName, fields, primaryKey) do
    Temper.Orm.__temper_init__()
    this = TemperCore.Heap.new(Temper.Orm.TableDef, %{:tableName => nil, :fields => nil, :primaryKey => nil})
    TemperCore.Heap.put(this, :tableName, tableName)
    TemperCore.Heap.put(this, :fields, fields)
    TemperCore.Heap.put(this, :primaryKey, primaryKey)
    this
  end
  def get_tableName(this) do
    TemperCore.Heap.get(this, :tableName)
  end
  def get_fields(this) do
    TemperCore.Heap.get(this, :fields)
  end
  def get_primaryKey(this) do
    TemperCore.Heap.get(this, :primaryKey)
  end
end
defmodule Temper.Orm.SqlBuilder do
  def __temper_supertypes__() do
    [Temper.Orm.SqlBuilder]
  end
  def appendSafe(this, sqlSource) do
    TemperCore.List.add(TemperCore.Heap.get(this, :buffer), Temper.Orm.SqlSource.new(sqlSource))
    nil
  end
  def appendFragment(this, fragment) do
    TemperCore.List.add_all(TemperCore.Heap.get(this, :buffer), Temper.Orm.SqlFragment.get_parts(fragment))
    nil
  end
  def appendPart(this, part) do
    TemperCore.List.add(TemperCore.Heap.get(this, :buffer), part)
    nil
  end
  def appendPartList(this, values) do
    fn_ = fn x ->
      Temper.Orm.SqlBuilder.appendPart(this, x)
      nil
    end
    Temper.Orm.SqlBuilder.appendList(this, values, fn_)
    nil
  end
  def appendBoolean(this, value) do
    TemperCore.List.add(TemperCore.Heap.get(this, :buffer), Temper.Orm.SqlBoolean.new(value))
    nil
  end
  def appendBooleanList(this, values) do
    fn_ = fn x ->
      Temper.Orm.SqlBuilder.appendBoolean(this, x)
      nil
    end
    Temper.Orm.SqlBuilder.appendList(this, values, fn_)
    nil
  end
  def appendDate(this, value) do
    TemperCore.List.add(TemperCore.Heap.get(this, :buffer), Temper.Orm.SqlDate.new(value))
    nil
  end
  def appendDateList(this, values) do
    fn_ = fn x ->
      Temper.Orm.SqlBuilder.appendDate(this, x)
      nil
    end
    Temper.Orm.SqlBuilder.appendList(this, values, fn_)
    nil
  end
  def appendFloat64(this, value) do
    TemperCore.List.add(TemperCore.Heap.get(this, :buffer), Temper.Orm.SqlFloat64.new(value))
    nil
  end
  def appendFloat64List(this, values) do
    fn_ = fn x ->
      Temper.Orm.SqlBuilder.appendFloat64(this, x)
      nil
    end
    Temper.Orm.SqlBuilder.appendList(this, values, fn_)
    nil
  end
  def appendInt32(this, value) do
    TemperCore.List.add(TemperCore.Heap.get(this, :buffer), Temper.Orm.SqlInt32.new(value))
    nil
  end
  def appendInt32List(this, values) do
    fn_ = fn x ->
      Temper.Orm.SqlBuilder.appendInt32(this, x)
      nil
    end
    Temper.Orm.SqlBuilder.appendList(this, values, fn_)
    nil
  end
  def appendInt64(this, value) do
    TemperCore.List.add(TemperCore.Heap.get(this, :buffer), Temper.Orm.SqlInt64.new(value))
    nil
  end
  def appendInt64List(this, values) do
    fn_ = fn x ->
      Temper.Orm.SqlBuilder.appendInt64(this, x)
      nil
    end
    Temper.Orm.SqlBuilder.appendList(this, values, fn_)
    nil
  end
  def appendString(this, value) do
    TemperCore.List.add(TemperCore.Heap.get(this, :buffer), Temper.Orm.SqlString.new(value))
    nil
  end
  def appendStringList(this, values) do
    fn_ = fn x ->
      Temper.Orm.SqlBuilder.appendString(this, x)
      nil
    end
    Temper.Orm.SqlBuilder.appendList(this, values, fn_)
    nil
  end
  def appendList(this, values, appendValue) do
    i = 0
    ex_loop_1 = fn ex_loop_1, i ->
      if i < TemperCore.List.length(values) do
        if i > 0 do
          Temper.Orm.SqlBuilder.appendSafe(this, ", ")
          nil
        else
          nil
        end
        appendValue.(TemperCore.List.get(values, i))
        i = TemperCore.int32(i + 1)
        ex_loop_1.(ex_loop_1, i)
      else
        i
      end
    end
    _i = ex_loop_1.(ex_loop_1, i)
    nil
  end
  def get_accumulated(this) do
    Temper.Orm.SqlFragment.new(TemperCore.List.to_list(TemperCore.Heap.get(this, :buffer)))
  end
  def new() do
    Temper.Orm.__temper_init__()
    this = TemperCore.Heap.new(Temper.Orm.SqlBuilder, %{:buffer => nil})
    t = TemperCore.List.builder()
    TemperCore.Heap.put(this, :buffer, t)
    this
  end
end
defmodule Temper.Orm.SqlFragment do
  def __temper_supertypes__() do
    [Temper.Orm.SqlFragment]
  end
  def toSource(this) do
    Temper.Orm.SqlSource.new(Temper.Orm.SqlFragment.toString(this))
  end
  def toString(this) do
    builder = TemperCore.StringBuilder.new()
    i = 0
    ex_loop_1 = fn ex_loop_1, i ->
      if i < TemperCore.List.length(TemperCore.Heap.get(this, :parts)) do
        TemperCore.call(TemperCore.List.get(TemperCore.Heap.get(this, :parts), i), :formatTo, [builder])
        i = TemperCore.int32(i + 1)
        ex_loop_1.(ex_loop_1, i)
      else
        i
      end
    end
    _i = ex_loop_1.(ex_loop_1, i)
    TemperCore.StringBuilder.to_string(builder)
  end
  def toParameterized(this) do
    text = TemperCore.StringBuilder.new()
    params = TemperCore.List.builder()
    i = 0
    ex_loop_1 = fn ex_loop_1, i ->
      if i < TemperCore.List.length(TemperCore.Heap.get(this, :parts)) do
        TemperCore.call(TemperCore.List.get(TemperCore.Heap.get(this, :parts), i), :formatParameterized, [text, params])
        i = TemperCore.int32(i + 1)
        ex_loop_1.(ex_loop_1, i)
      else
        i
      end
    end
    _i = ex_loop_1.(ex_loop_1, i)
    Temper.Orm.ParameterizedSql.new(TemperCore.StringBuilder.to_string(text), TemperCore.List.to_list(params))
  end
  def new(parts) do
    Temper.Orm.__temper_init__()
    this = TemperCore.Heap.new(Temper.Orm.SqlFragment, %{:parts => nil})
    TemperCore.Heap.put(this, :parts, parts)
    this
  end
  def get_parts(this) do
    TemperCore.Heap.get(this, :parts)
  end
end
defmodule Temper.Orm.ParameterizedSql do
  def __temper_supertypes__() do
    [Temper.Orm.ParameterizedSql]
  end
  def new(text, params) do
    Temper.Orm.__temper_init__()
    this = TemperCore.Heap.new(Temper.Orm.ParameterizedSql, %{:text => nil, :params => nil})
    TemperCore.Heap.put(this, :text, text)
    TemperCore.Heap.put(this, :params, params)
    this
  end
  def get_text(this) do
    TemperCore.Heap.get(this, :text)
  end
  def get_params(this) do
    TemperCore.Heap.get(this, :params)
  end
end
defmodule Temper.Orm.SqlPart do
  def __temper_supertypes__() do
    [Temper.Orm.SqlPart]
  end
  def formatTo(_this, _builder) do
    raise(TemperCore.Panic)
  end
  def formatParameterized(_this, _text, _params) do
    raise(TemperCore.Panic)
  end
end
defmodule Temper.Orm.SqlSource do
  def __temper_supertypes__() do
    [Temper.Orm.SqlSource, Temper.Orm.SqlPart]
  end
  def formatTo(this, builder) do
    TemperCore.StringBuilder.append(builder, TemperCore.Heap.get(this, :source))
    nil
  end
  def formatParameterized(this, text, _params) do
    TemperCore.StringBuilder.append(text, TemperCore.Heap.get(this, :source))
    nil
  end
  def new(source) do
    Temper.Orm.__temper_init__()
    this = TemperCore.Heap.new(Temper.Orm.SqlSource, %{:source => nil})
    TemperCore.Heap.put(this, :source, source)
    this
  end
  def get_source(this) do
    TemperCore.Heap.get(this, :source)
  end
end
defmodule Temper.Orm.SqlBoolean do
  def __temper_supertypes__() do
    [Temper.Orm.SqlBoolean, Temper.Orm.SqlPart]
  end
  def formatTo(this, builder) do
    _t = nil
    t = if TemperCore.Heap.get(this, :value) do
      t = "TRUE"
      t
    else
      t = "FALSE"
      t
    end
    TemperCore.StringBuilder.append(builder, t)
    nil
  end
  def formatParameterized(this, text, _params) do
    Temper.Orm.SqlBoolean.formatTo(this, text)
    nil
  end
  def new(value) do
    Temper.Orm.__temper_init__()
    this = TemperCore.Heap.new(Temper.Orm.SqlBoolean, %{:value => nil})
    TemperCore.Heap.put(this, :value, value)
    this
  end
  def get_value(this) do
    TemperCore.Heap.get(this, :value)
  end
end
defmodule Temper.Orm.SqlDate do
  def __temper_supertypes__() do
    [Temper.Orm.SqlDate, Temper.Orm.SqlPart]
  end
  def formatTo(this1, builder) do
    TemperCore.StringBuilder.append(builder, "'")
    this2 = Temper.Std.Date.toString(TemperCore.Heap.get(this1, :value))
    index = TemperCore.String.begin()
    ex_loop_1 = fn ex_loop_1, index ->
      if TemperCore.String.has_index(this2, index) do
        codePoint = TemperCore.String.get(this2, index)
        c = codePoint
        if c == 39 do
          TemperCore.StringBuilder.append(builder, "''")
          nil
        else
          try do
            TemperCore.StringBuilder.append_code_point(builder, c)
            nil
          rescue
            _ in TemperCore.Bubble ->
              raise(TemperCore.Bubble)
          end
          nil
        end
        index = TemperCore.String.next(this2, index)
        ex_loop_1.(ex_loop_1, index)
      else
        index
      end
    end
    _index = ex_loop_1.(ex_loop_1, index)
    TemperCore.StringBuilder.append(builder, "'")
    nil
  end
  def formatParameterized(this, text, params) do
    Temper.Orm.placeholder(text, params, Temper.Std.Date.toString(TemperCore.Heap.get(this, :value)))
    nil
  end
  def new(value) do
    Temper.Orm.__temper_init__()
    this = TemperCore.Heap.new(Temper.Orm.SqlDate, %{:value => nil})
    TemperCore.Heap.put(this, :value, value)
    this
  end
  def get_value(this) do
    TemperCore.Heap.get(this, :value)
  end
end
defmodule Temper.Orm.SqlFloat64 do
  def __temper_supertypes__() do
    [Temper.Orm.SqlFloat64, Temper.Orm.SqlPart]
  end
  def formatTo(this, builder) do
    s = TemperCore.Float.to_string(TemperCore.Heap.get(this, :value))
    _t = nil
    t = cond do
      s == "NaN" ->
        t = true
        t
      s == "Infinity" ->
        t = true
        t
      true ->
        t = s == "-Infinity"
        t
    end
    if t do
      TemperCore.StringBuilder.append(builder, "NULL")
      nil
    else
      TemperCore.StringBuilder.append(builder, s)
      nil
    end
    nil
  end
  def formatParameterized(this, text, params) do
    s = TemperCore.Float.to_string(TemperCore.Heap.get(this, :value))
    _t = nil
    t = cond do
      s == "NaN" ->
        t = true
        t
      s == "Infinity" ->
        t = true
        t
      true ->
        t = s == "-Infinity"
        t
    end
    if t do
      TemperCore.StringBuilder.append(text, "NULL")
      nil
    else
      Temper.Orm.placeholder(text, params, s)
      nil
    end
    nil
  end
  def new(value) do
    Temper.Orm.__temper_init__()
    this = TemperCore.Heap.new(Temper.Orm.SqlFloat64, %{:value => nil})
    TemperCore.Heap.put(this, :value, value)
    this
  end
  def get_value(this) do
    TemperCore.Heap.get(this, :value)
  end
end
defmodule Temper.Orm.SqlInt32 do
  def __temper_supertypes__() do
    [Temper.Orm.SqlInt32, Temper.Orm.SqlPart]
  end
  def formatTo(this, builder) do
    TemperCore.StringBuilder.append(builder, TemperCore.int_to_string(TemperCore.Heap.get(this, :value)))
    nil
  end
  def formatParameterized(this, text, params) do
    Temper.Orm.placeholder(text, params, TemperCore.int_to_string(TemperCore.Heap.get(this, :value)))
    nil
  end
  def new(value) do
    Temper.Orm.__temper_init__()
    this = TemperCore.Heap.new(Temper.Orm.SqlInt32, %{:value => nil})
    TemperCore.Heap.put(this, :value, value)
    this
  end
  def get_value(this) do
    TemperCore.Heap.get(this, :value)
  end
end
defmodule Temper.Orm.SqlInt64 do
  def __temper_supertypes__() do
    [Temper.Orm.SqlInt64, Temper.Orm.SqlPart]
  end
  def formatTo(this, builder) do
    TemperCore.StringBuilder.append(builder, TemperCore.int_to_string(TemperCore.Heap.get(this, :value)))
    nil
  end
  def formatParameterized(this, text, params) do
    Temper.Orm.placeholder(text, params, TemperCore.int_to_string(TemperCore.Heap.get(this, :value)))
    nil
  end
  def new(value) do
    Temper.Orm.__temper_init__()
    this = TemperCore.Heap.new(Temper.Orm.SqlInt64, %{:value => nil})
    TemperCore.Heap.put(this, :value, value)
    this
  end
  def get_value(this) do
    TemperCore.Heap.get(this, :value)
  end
end
defmodule Temper.Orm.SqlDefault do
  def __temper_supertypes__() do
    [Temper.Orm.SqlDefault, Temper.Orm.SqlPart]
  end
  def formatTo(_this, builder) do
    TemperCore.StringBuilder.append(builder, "DEFAULT")
    nil
  end
  def formatParameterized(this, text, _params) do
    Temper.Orm.SqlDefault.formatTo(this, text)
    nil
  end
  def new() do
    Temper.Orm.__temper_init__()
    this = TemperCore.Heap.new(Temper.Orm.SqlDefault, %{})
    this
  end
end
defmodule Temper.Orm.SqlString do
  def __temper_supertypes__() do
    [Temper.Orm.SqlString, Temper.Orm.SqlPart]
  end
  def formatTo(this1, builder) do
    TemperCore.StringBuilder.append(builder, "'")
    this2 = TemperCore.Heap.get(this1, :value)
    index = TemperCore.String.begin()
    ex_loop_1 = fn ex_loop_1, index ->
      if TemperCore.String.has_index(this2, index) do
        codePoint = TemperCore.String.get(this2, index)
        c = codePoint
        if c == 39 do
          TemperCore.StringBuilder.append(builder, "''")
          nil
        else
          try do
            TemperCore.StringBuilder.append_code_point(builder, c)
            nil
          rescue
            _ in TemperCore.Bubble ->
              raise(TemperCore.Bubble)
          end
          nil
        end
        index = TemperCore.String.next(this2, index)
        ex_loop_1.(ex_loop_1, index)
      else
        index
      end
    end
    _index = ex_loop_1.(ex_loop_1, index)
    TemperCore.StringBuilder.append(builder, "'")
    nil
  end
  def formatParameterized(this, text, params) do
    Temper.Orm.placeholder(text, params, TemperCore.Heap.get(this, :value))
    nil
  end
  def new(value) do
    Temper.Orm.__temper_init__()
    this = TemperCore.Heap.new(Temper.Orm.SqlString, %{:value => nil})
    TemperCore.Heap.put(this, :value, value)
    this
  end
  def get_value(this) do
    TemperCore.Heap.get(this, :value)
  end
end
defmodule Temper.Orm do
  def placeholder(text, params, value) do
    TemperCore.List.add(params, value)
    TemperCore.StringBuilder.append(text, "$")
    TemperCore.StringBuilder.append(text, TemperCore.int_to_string(TemperCore.List.length(params)))
    nil
  end
  def changeset(tableDef, params) do
    Temper.Orm.__temper_init__()
    TemperCore.Heap.entry(fn ->
      Temper.Orm.ChangesetImpl.new(tableDef, params, TemperCore.Map.new(%TemperCore.Vec{t: {}}), %TemperCore.Vec{t: {}}, true)
    end)
  end
  def isIdentStart(c) do
    _t1 = nil
    t1 = if c >= 97 do
      t1 = c <= 122
      t1
    else
      t1 = false
      t1
    end
    if t1 do
      true
    else
      _t2 = nil
      t2 = if c >= 65 do
        t2 = c <= 90
        t2
      else
        t2 = false
        t2
      end
      if t2 do
        true
      else
        c == 95
      end
    end
  end
  def isIdentPart(c) do
    cond do
      Temper.Orm.isIdentStart(c) ->
        true
      c >= 48 ->
        c <= 57
      true ->
        false
    end
  end
  def safeIdentifier(name) do
    Temper.Orm.__temper_init__()
    TemperCore.Heap.entry(fn ->
      if TemperCore.String.is_empty(name) do
        raise(TemperCore.Bubble)
      else
        idx = TemperCore.String.begin()
        if not Temper.Orm.isIdentStart(TemperCore.String.get(name, idx)) do
          raise(TemperCore.Bubble)
        else
          idx = TemperCore.String.next(name, idx)
          ex_loop_1 = fn ex_loop_1, idx ->
            if TemperCore.String.has_index(name, idx) do
              if not Temper.Orm.isIdentPart(TemperCore.String.get(name, idx)) do
                raise(TemperCore.Bubble)
              else
                idx = TemperCore.String.next(name, idx)
                ex_loop_1.(ex_loop_1, idx)
              end
            else
              idx
            end
          end
          _idx = ex_loop_1.(ex_loop_1, idx)
          Temper.Orm.ValidatedIdentifier.new(name)
        end
      end
    end)
  end
  def timestamps() do
    Temper.Orm.__temper_init__()
    TemperCore.Heap.entry(fn ->
      t1 = Temper.Orm.safeIdentifier("inserted_at")
      t2 = Temper.Orm.safeIdentifier("updated_at")
      %TemperCore.Vec{t: {Temper.Orm.FieldDef.new(t1, Temper.Orm.DateField.new(), true, Temper.Orm.SqlDefault.new(), false), Temper.Orm.FieldDef.new(t2, Temper.Orm.DateField.new(), true, Temper.Orm.SqlDefault.new(), false)}}
    end)
  end
  def deleteSql(tableDef, id) do
    Temper.Orm.__temper_init__()
    TemperCore.Heap.entry(fn ->
      b = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(b, "DELETE FROM ")
      Temper.Orm.SqlBuilder.appendSafe(b, TemperCore.call(Temper.Orm.TableDef.get_tableName(tableDef), :get_sqlValue, []))
      Temper.Orm.SqlBuilder.appendSafe(b, " WHERE ")
      Temper.Orm.SqlBuilder.appendSafe(b, Temper.Orm.TableDef.pkName(tableDef))
      Temper.Orm.SqlBuilder.appendSafe(b, " = ")
      Temper.Orm.SqlBuilder.appendInt32(b, id)
      Temper.Orm.SqlBuilder.get_accumulated(b)
    end)
  end
  def renderWhere(b, conditions) do
    if not TemperCore.List.is_empty(conditions) do
      Temper.Orm.SqlBuilder.appendSafe(b, " WHERE ")
      Temper.Orm.SqlBuilder.appendFragment(b, TemperCore.call(TemperCore.List.get(conditions, 0), :get_condition, []))
      i = 1
      ex_loop_1 = fn ex_loop_1, i ->
        if i < TemperCore.List.length(conditions) do
          Temper.Orm.SqlBuilder.appendSafe(b, " ")
          Temper.Orm.SqlBuilder.appendSafe(b, TemperCore.call(TemperCore.List.get(conditions, i), :keyword, []))
          Temper.Orm.SqlBuilder.appendSafe(b, " ")
          Temper.Orm.SqlBuilder.appendFragment(b, TemperCore.call(TemperCore.List.get(conditions, i), :get_condition, []))
          i = TemperCore.int32(i + 1)
          ex_loop_1.(ex_loop_1, i)
        else
          i
        end
      end
      _i = ex_loop_1.(ex_loop_1, i)
      nil
    else
      nil
    end
    nil
  end
  def renderJoins(b, joinClauses) do
    this = joinClauses
    n = TemperCore.List.length(this)
    i = 0
    ex_loop_1 = fn ex_loop_1, i ->
      if i < n do
        el = TemperCore.List.get(this, i)
        i = TemperCore.int32(i + 1)
        jc = el
        Temper.Orm.SqlBuilder.appendSafe(b, " ")
        Temper.Orm.SqlBuilder.appendSafe(b, TemperCore.call(Temper.Orm.JoinClause.get_joinType(jc), :keyword, []))
        Temper.Orm.SqlBuilder.appendSafe(b, " ")
        Temper.Orm.SqlBuilder.appendSafe(b, TemperCore.call(Temper.Orm.JoinClause.get_table(jc), :get_sqlValue, []))
        oc1 = Temper.Orm.JoinClause.get_onCondition(jc)
        if not (oc1 === nil) do
          oc2 = oc1
          Temper.Orm.SqlBuilder.appendSafe(b, " ON ")
          Temper.Orm.SqlBuilder.appendFragment(b, oc2)
          ex_loop_1.(ex_loop_1, i)
        else
          ex_loop_1.(ex_loop_1, i)
        end
      else
        i
      end
    end
    _i = ex_loop_1.(ex_loop_1, i)
    nil
  end
  def renderGroupBy(b, groupByFields) do
    if not TemperCore.List.is_empty(groupByFields) do
      Temper.Orm.SqlBuilder.appendSafe(b, " GROUP BY ")
      fn_ = fn f ->
        TemperCore.call(f, :get_sqlValue, [])
      end
      Temper.Orm.SqlBuilder.appendSafe(b, TemperCore.List.join(groupByFields, ", ", fn_))
      nil
    else
      nil
    end
    nil
  end
  def renderHaving(b, havingConditions) do
    if not TemperCore.List.is_empty(havingConditions) do
      Temper.Orm.SqlBuilder.appendSafe(b, " HAVING ")
      Temper.Orm.SqlBuilder.appendFragment(b, TemperCore.call(TemperCore.List.get(havingConditions, 0), :get_condition, []))
      i = 1
      ex_loop_1 = fn ex_loop_1, i ->
        if i < TemperCore.List.length(havingConditions) do
          Temper.Orm.SqlBuilder.appendSafe(b, " ")
          Temper.Orm.SqlBuilder.appendSafe(b, TemperCore.call(TemperCore.List.get(havingConditions, i), :keyword, []))
          Temper.Orm.SqlBuilder.appendSafe(b, " ")
          Temper.Orm.SqlBuilder.appendFragment(b, TemperCore.call(TemperCore.List.get(havingConditions, i), :get_condition, []))
          i = TemperCore.int32(i + 1)
          ex_loop_1.(ex_loop_1, i)
        else
          i
        end
      end
      _i = ex_loop_1.(ex_loop_1, i)
      nil
    else
      nil
    end
    nil
  end
  def from(tableName) do
    Temper.Orm.__temper_init__()
    TemperCore.Heap.entry(fn ->
      Temper.Orm.Query.new(tableName, %TemperCore.Vec{t: {}}, %TemperCore.Vec{t: {}}, %TemperCore.Vec{t: {}}, nil, nil, %TemperCore.Vec{t: {}}, %TemperCore.Vec{t: {}}, %TemperCore.Vec{t: {}}, false, %TemperCore.Vec{t: {}}, nil)
    end)
  end
  def col(table, column) do
    Temper.Orm.__temper_init__()
    TemperCore.Heap.entry(fn ->
      b = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(b, TemperCore.call(table, :get_sqlValue, []))
      Temper.Orm.SqlBuilder.appendSafe(b, ".")
      Temper.Orm.SqlBuilder.appendSafe(b, TemperCore.call(column, :get_sqlValue, []))
      Temper.Orm.SqlBuilder.get_accumulated(b)
    end)
  end
  def countAll() do
    Temper.Orm.__temper_init__()
    TemperCore.Heap.entry(fn ->
      b = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(b, "COUNT(*)")
      Temper.Orm.SqlBuilder.get_accumulated(b)
    end)
  end
  def countCol(field) do
    Temper.Orm.__temper_init__()
    TemperCore.Heap.entry(fn ->
      b = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(b, "COUNT(")
      Temper.Orm.SqlBuilder.appendSafe(b, TemperCore.call(field, :get_sqlValue, []))
      Temper.Orm.SqlBuilder.appendSafe(b, ")")
      Temper.Orm.SqlBuilder.get_accumulated(b)
    end)
  end
  def sumCol(field) do
    Temper.Orm.__temper_init__()
    TemperCore.Heap.entry(fn ->
      b = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(b, "SUM(")
      Temper.Orm.SqlBuilder.appendSafe(b, TemperCore.call(field, :get_sqlValue, []))
      Temper.Orm.SqlBuilder.appendSafe(b, ")")
      Temper.Orm.SqlBuilder.get_accumulated(b)
    end)
  end
  def avgCol(field) do
    Temper.Orm.__temper_init__()
    TemperCore.Heap.entry(fn ->
      b = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(b, "AVG(")
      Temper.Orm.SqlBuilder.appendSafe(b, TemperCore.call(field, :get_sqlValue, []))
      Temper.Orm.SqlBuilder.appendSafe(b, ")")
      Temper.Orm.SqlBuilder.get_accumulated(b)
    end)
  end
  def minCol(field) do
    Temper.Orm.__temper_init__()
    TemperCore.Heap.entry(fn ->
      b = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(b, "MIN(")
      Temper.Orm.SqlBuilder.appendSafe(b, TemperCore.call(field, :get_sqlValue, []))
      Temper.Orm.SqlBuilder.appendSafe(b, ")")
      Temper.Orm.SqlBuilder.get_accumulated(b)
    end)
  end
  def maxCol(field) do
    Temper.Orm.__temper_init__()
    TemperCore.Heap.entry(fn ->
      b = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(b, "MAX(")
      Temper.Orm.SqlBuilder.appendSafe(b, TemperCore.call(field, :get_sqlValue, []))
      Temper.Orm.SqlBuilder.appendSafe(b, ")")
      Temper.Orm.SqlBuilder.get_accumulated(b)
    end)
  end
  def unionSql(a, b) do
    Temper.Orm.__temper_init__()
    TemperCore.Heap.entry(fn ->
      sb = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(sb, "(")
      Temper.Orm.SqlBuilder.appendFragment(sb, Temper.Orm.Query.toSql(a))
      Temper.Orm.SqlBuilder.appendSafe(sb, ") UNION (")
      Temper.Orm.SqlBuilder.appendFragment(sb, Temper.Orm.Query.toSql(b))
      Temper.Orm.SqlBuilder.appendSafe(sb, ")")
      Temper.Orm.SqlBuilder.get_accumulated(sb)
    end)
  end
  def unionAllSql(a, b) do
    Temper.Orm.__temper_init__()
    TemperCore.Heap.entry(fn ->
      sb = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(sb, "(")
      Temper.Orm.SqlBuilder.appendFragment(sb, Temper.Orm.Query.toSql(a))
      Temper.Orm.SqlBuilder.appendSafe(sb, ") UNION ALL (")
      Temper.Orm.SqlBuilder.appendFragment(sb, Temper.Orm.Query.toSql(b))
      Temper.Orm.SqlBuilder.appendSafe(sb, ")")
      Temper.Orm.SqlBuilder.get_accumulated(sb)
    end)
  end
  def intersectSql(a, b) do
    Temper.Orm.__temper_init__()
    TemperCore.Heap.entry(fn ->
      sb = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(sb, "(")
      Temper.Orm.SqlBuilder.appendFragment(sb, Temper.Orm.Query.toSql(a))
      Temper.Orm.SqlBuilder.appendSafe(sb, ") INTERSECT (")
      Temper.Orm.SqlBuilder.appendFragment(sb, Temper.Orm.Query.toSql(b))
      Temper.Orm.SqlBuilder.appendSafe(sb, ")")
      Temper.Orm.SqlBuilder.get_accumulated(sb)
    end)
  end
  def exceptSql(a, b) do
    Temper.Orm.__temper_init__()
    TemperCore.Heap.entry(fn ->
      sb = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(sb, "(")
      Temper.Orm.SqlBuilder.appendFragment(sb, Temper.Orm.Query.toSql(a))
      Temper.Orm.SqlBuilder.appendSafe(sb, ") EXCEPT (")
      Temper.Orm.SqlBuilder.appendFragment(sb, Temper.Orm.Query.toSql(b))
      Temper.Orm.SqlBuilder.appendSafe(sb, ")")
      Temper.Orm.SqlBuilder.get_accumulated(sb)
    end)
  end
  def subquery(q, alias_) do
    Temper.Orm.__temper_init__()
    TemperCore.Heap.entry(fn ->
      b = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(b, "(")
      Temper.Orm.SqlBuilder.appendFragment(b, Temper.Orm.Query.toSql(q))
      Temper.Orm.SqlBuilder.appendSafe(b, ") AS ")
      Temper.Orm.SqlBuilder.appendSafe(b, TemperCore.call(alias_, :get_sqlValue, []))
      Temper.Orm.SqlBuilder.get_accumulated(b)
    end)
  end
  def existsSql(q) do
    Temper.Orm.__temper_init__()
    TemperCore.Heap.entry(fn ->
      b = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(b, "EXISTS (")
      Temper.Orm.SqlBuilder.appendFragment(b, Temper.Orm.Query.toSql(q))
      Temper.Orm.SqlBuilder.appendSafe(b, ")")
      Temper.Orm.SqlBuilder.get_accumulated(b)
    end)
  end
  def update(tableName) do
    Temper.Orm.__temper_init__()
    TemperCore.Heap.entry(fn ->
      Temper.Orm.UpdateQuery.new(tableName, %TemperCore.Vec{t: {}}, %TemperCore.Vec{t: {}}, nil)
    end)
  end
  def deleteFrom(tableName) do
    Temper.Orm.__temper_init__()
    TemperCore.Heap.entry(fn ->
      Temper.Orm.DeleteQuery.new(tableName, %TemperCore.Vec{t: {}}, nil)
    end)
  end
  def __temper_init__() do
    TemperCore.init_once(:"Temper.Orm", fn ->
      Temper.Std.__temper_init__()
      nil
    end)
  end
  def main() do
    Temper.Orm.__temper_init__()
    TemperCore.Async.drain()
  end
end
