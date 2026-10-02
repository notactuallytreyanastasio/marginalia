defmodule Temper.Std.InterchangeContext do
  def __temper_supertypes__() do
    [Temper.Std.InterchangeContext]
  end
  def getHeader(_this, _headerName) do
    raise(TemperCore.Panic)
  end
end
defmodule Temper.Std.NullInterchangeContext do
  defstruct []
  def __temper_supertypes__() do
    [Temper.Std.NullInterchangeContext, Temper.Std.InterchangeContext]
  end
  def getHeader(_this, _headerName) do
    nil
  end
  def new() do
    Temper.Std.__temper_init__()
    this = %Temper.Std.NullInterchangeContext{}
    this
  end
end
defmodule Temper.Std.JsonProducer do
  def __temper_supertypes__() do
    [Temper.Std.JsonProducer]
  end
  def startObject(_this) do
    raise(TemperCore.Panic)
  end
  def endObject(_this) do
    raise(TemperCore.Panic)
  end
  def objectKey(_this, _key) do
    raise(TemperCore.Panic)
  end
  def startArray(_this) do
    raise(TemperCore.Panic)
  end
  def endArray(_this) do
    raise(TemperCore.Panic)
  end
  def nullValue(_this) do
    raise(TemperCore.Panic)
  end
  def booleanValue(_this, _x) do
    raise(TemperCore.Panic)
  end
  def int32Value(_this, _x) do
    raise(TemperCore.Panic)
  end
  def int64Value(_this, _x) do
    raise(TemperCore.Panic)
  end
  def float64Value(_this, _x) do
    raise(TemperCore.Panic)
  end
  def numericTokenValue(_this, _x) do
    raise(TemperCore.Panic)
  end
  def stringValue(_this, _x) do
    raise(TemperCore.Panic)
  end
  def get_parseErrorReceiver(_this) do
    nil
  end
end
defmodule Temper.Std.JsonSyntaxTree do
  def __temper_supertypes__() do
    [Temper.Std.JsonSyntaxTree]
  end
  def produce(_this, _p) do
    raise(TemperCore.Panic)
  end
end
defmodule Temper.Std.JsonObject do
  defstruct [:properties]
  def __temper_supertypes__() do
    [Temper.Std.JsonObject, Temper.Std.JsonSyntaxTree]
  end
  def propertyValueOrNull(this, propertyKey) do
    treeList = TemperCore.Map.get_or(this.properties, propertyKey, %TemperCore.Vec{t: {}})
    lastIndex = TemperCore.int32(TemperCore.List.length(treeList) - 1)
    if lastIndex >= 0 do
      TemperCore.List.get(treeList, lastIndex)
    else
      nil
    end
  end
  def propertyValueOrBubble(this, propertyKey) do
    t = Temper.Std.JsonObject.propertyValueOrNull(this, propertyKey)
    if t === nil do
      raise(TemperCore.Bubble)
    else
      t
    end
  end
  def produce(this1, p) do
    TemperCore.call(p, :startObject, [])
    fn_ = fn k, vs ->
      this2 = vs
      n = TemperCore.List.length(this2)
      i = 0
      ex_loop_2 = fn ex_loop_2, i ->
        if i < n do
          el = TemperCore.List.get(this2, i)
          i = TemperCore.int32(i + 1)
          v = el
          TemperCore.call(p, :objectKey, [k])
          TemperCore.call(v, :produce, [p])
          ex_loop_2.(ex_loop_2, i)
        else
          i
        end
      end
      _i = ex_loop_2.(ex_loop_2, i)
      nil
    end
    TemperCore.Map.for_each(this1.properties, fn_)
    TemperCore.call(p, :endObject, [])
    nil
  end
  def new(properties) do
    Temper.Std.__temper_init__()
    this = %Temper.Std.JsonObject{}
    this = %{this | :properties => properties}
    this
  end
  def get_properties(this) do
    this.properties
  end
end
defmodule Temper.Std.JsonArray do
  defstruct [:elements]
  def __temper_supertypes__() do
    [Temper.Std.JsonArray, Temper.Std.JsonSyntaxTree]
  end
  def produce(this1, p) do
    TemperCore.call(p, :startArray, [])
    this2 = this1.elements
    n = TemperCore.List.length(this2)
    i = 0
    ex_loop_1 = fn ex_loop_1, i ->
      if i < n do
        el = TemperCore.List.get(this2, i)
        i = TemperCore.int32(i + 1)
        v = el
        TemperCore.call(v, :produce, [p])
        ex_loop_1.(ex_loop_1, i)
      else
        i
      end
    end
    _i = ex_loop_1.(ex_loop_1, i)
    TemperCore.call(p, :endArray, [])
    nil
  end
  def new(elements) do
    Temper.Std.__temper_init__()
    this = %Temper.Std.JsonArray{}
    this = %{this | :elements => elements}
    this
  end
  def get_elements(this) do
    this.elements
  end
end
defmodule Temper.Std.JsonBoolean do
  defstruct [:content]
  def __temper_supertypes__() do
    [Temper.Std.JsonBoolean, Temper.Std.JsonSyntaxTree]
  end
  def produce(this, p) do
    TemperCore.call(p, :booleanValue, [this.content])
    nil
  end
  def new(content) do
    Temper.Std.__temper_init__()
    this = %Temper.Std.JsonBoolean{}
    this = %{this | :content => content}
    this
  end
  def get_content(this) do
    this.content
  end
end
defmodule Temper.Std.JsonNull do
  defstruct []
  def __temper_supertypes__() do
    [Temper.Std.JsonNull, Temper.Std.JsonSyntaxTree]
  end
  def produce(_this, p) do
    TemperCore.call(p, :nullValue, [])
    nil
  end
  def new() do
    Temper.Std.__temper_init__()
    this = %Temper.Std.JsonNull{}
    this
  end
end
defmodule Temper.Std.JsonString do
  defstruct [:content]
  def __temper_supertypes__() do
    [Temper.Std.JsonString, Temper.Std.JsonSyntaxTree]
  end
  def produce(this, p) do
    TemperCore.call(p, :stringValue, [this.content])
    nil
  end
  def new(content) do
    Temper.Std.__temper_init__()
    this = %Temper.Std.JsonString{}
    this = %{this | :content => content}
    this
  end
  def get_content(this) do
    this.content
  end
end
defmodule Temper.Std.JsonNumeric do
  def __temper_supertypes__() do
    [Temper.Std.JsonNumeric, Temper.Std.JsonSyntaxTree]
  end
  def asJsonNumericToken(_this) do
    raise(TemperCore.Panic)
  end
  def asInt32(_this) do
    raise(TemperCore.Panic)
  end
  def asInt64(_this) do
    raise(TemperCore.Panic)
  end
  def asFloat64(_this) do
    raise(TemperCore.Panic)
  end
end
defmodule Temper.Std.JsonInt32 do
  defstruct [:content]
  def __temper_supertypes__() do
    [Temper.Std.JsonInt32, Temper.Std.JsonNumeric, Temper.Std.JsonSyntaxTree]
  end
  def produce(this, p) do
    TemperCore.call(p, :int32Value, [this.content])
    nil
  end
  def asJsonNumericToken(this) do
    TemperCore.int_to_string(this.content)
  end
  def asInt32(this) do
    this.content
  end
  def asInt32Safe(this) do
    this.content
  end
  def asInt64(this) do
    Temper.Std.JsonInt32.asInt64Safe(this)
  end
  def asInt64Safe(this) do
    this.content
  end
  def asFloat64(this) do
    Temper.Std.JsonInt32.asFloat64Safe(this)
  end
  def asFloat64Safe(this) do
    TemperCore.int_to_float(this.content)
  end
  def new(content) do
    Temper.Std.__temper_init__()
    this = %Temper.Std.JsonInt32{}
    this = %{this | :content => content}
    this
  end
  def get_content(this) do
    this.content
  end
end
defmodule Temper.Std.JsonInt64 do
  defstruct [:content]
  def __temper_supertypes__() do
    [Temper.Std.JsonInt64, Temper.Std.JsonNumeric, Temper.Std.JsonSyntaxTree]
  end
  def produce(this, p) do
    TemperCore.call(p, :int64Value, [this.content])
    nil
  end
  def asJsonNumericToken(this) do
    TemperCore.int_to_string(this.content)
  end
  def asInt32(this) do
    TemperCore.int64_to_int32(this.content)
  end
  def asInt64(this) do
    this.content
  end
  def asInt64Safe(this) do
    this.content
  end
  def asFloat64(this) do
    TemperCore.int64_to_float(this.content)
  end
  def new(content) do
    Temper.Std.__temper_init__()
    this = %Temper.Std.JsonInt64{}
    this = %{this | :content => content}
    this
  end
  def get_content(this) do
    this.content
  end
end
defmodule Temper.Std.JsonFloat64 do
  defstruct [:content]
  def __temper_supertypes__() do
    [Temper.Std.JsonFloat64, Temper.Std.JsonNumeric, Temper.Std.JsonSyntaxTree]
  end
  def produce(this, p) do
    TemperCore.call(p, :float64Value, [this.content])
    nil
  end
  def asJsonNumericToken(this) do
    TemperCore.Float.to_string(this.content)
  end
  def asInt32(this) do
    TemperCore.float_to_int32(this.content)
  end
  def asInt64(this) do
    TemperCore.float_to_int64(this.content)
  end
  def asFloat64(this) do
    this.content
  end
  def asFloat64Safe(this) do
    this.content
  end
  def new(content) do
    Temper.Std.__temper_init__()
    this = %Temper.Std.JsonFloat64{}
    this = %{this | :content => content}
    this
  end
  def get_content(this) do
    this.content
  end
end
defmodule Temper.Std.JsonNumericToken do
  defstruct [:content]
  def __temper_supertypes__() do
    [Temper.Std.JsonNumericToken, Temper.Std.JsonNumeric, Temper.Std.JsonSyntaxTree]
  end
  def produce(this, p) do
    TemperCore.call(p, :numericTokenValue, [this.content])
    nil
  end
  def asJsonNumericToken(this) do
    this.content
  end
  def asInt32(this) do
    try do
      try do
        throw({:temper_return, :ex_return_0, TemperCore.String.to_int32(this.content)})
      rescue
        _ in TemperCore.Bubble ->
          t = TemperCore.String.to_float64(this.content)
          throw({:temper_return, :ex_return_0, TemperCore.float_to_int32(t)})
      end
      nil
    catch
      {:temper_return, :ex_return_0, ex_value_1} ->
        ex_value_1
    end
  end
  def asInt64(this) do
    try do
      try do
        throw({:temper_return, :ex_return_0, TemperCore.String.to_int64(this.content)})
      rescue
        _ in TemperCore.Bubble ->
          t = TemperCore.String.to_float64(this.content)
          throw({:temper_return, :ex_return_0, TemperCore.float_to_int64(t)})
      end
      nil
    catch
      {:temper_return, :ex_return_0, ex_value_1} ->
        ex_value_1
    end
  end
  def asFloat64(this) do
    TemperCore.String.to_float64(this.content)
  end
  def new(content) do
    Temper.Std.__temper_init__()
    this = %Temper.Std.JsonNumericToken{}
    this = %{this | :content => content}
    this
  end
  def get_content(this) do
    this.content
  end
end
defmodule Temper.Std.JsonTextProducer do
  def __temper_supertypes__() do
    [Temper.Std.JsonTextProducer, Temper.Std.JsonProducer]
  end
  def new(interchangeContext1) do
    Temper.Std.__temper_init__()
    this = TemperCore.Heap.new(Temper.Std.JsonTextProducer, %{:interchangeContext => nil, :buffer => nil, :stack => nil, :wellFormed => nil})
    _interchangeContext2 = nil
    interchangeContext2 = if interchangeContext1 === nil do
      interchangeContext2 = TemperCore.Global.get(:"Temper.Std.NullInterchangeContext.instance")
      interchangeContext2
    else
      interchangeContext2 = interchangeContext1
      interchangeContext2
    end
    TemperCore.Heap.put(this, :interchangeContext, interchangeContext2)
    t1 = TemperCore.StringBuilder.new()
    TemperCore.Heap.put(this, :buffer, t1)
    t2 = TemperCore.List.builder()
    TemperCore.Heap.put(this, :stack, t2)
    TemperCore.List.add(TemperCore.Heap.get(this, :stack), 5)
    TemperCore.Heap.put(this, :wellFormed, true)
    this
  end
  def state(this) do
    TemperCore.List.get_or(TemperCore.Heap.get(this, :stack), TemperCore.int32(TemperCore.List.length(TemperCore.Heap.get(this, :stack)) - 1), -1)
  end
  def beforeValue(this) do
    currentState = Temper.Std.JsonTextProducer.state(this)
    cond do
      currentState == 3 ->
        TemperCore.List.set(TemperCore.Heap.get(this, :stack), TemperCore.int32(TemperCore.List.length(TemperCore.Heap.get(this, :stack)) - 1), 4)
        nil
      currentState == 4 ->
        TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :buffer), ",")
        nil
      currentState == 1 ->
        TemperCore.List.set(TemperCore.Heap.get(this, :stack), TemperCore.int32(TemperCore.List.length(TemperCore.Heap.get(this, :stack)) - 1), 2)
        nil
      currentState == 5 ->
        TemperCore.List.set(TemperCore.Heap.get(this, :stack), TemperCore.int32(TemperCore.List.length(TemperCore.Heap.get(this, :stack)) - 1), 6)
        nil
      true ->
        _t = nil
        t = if currentState == 6 do
          t = true
          t
        else
          t = currentState == 2
          t
        end
        if t do
          TemperCore.Heap.put(this, :wellFormed, false)
          nil
        else
          nil
        end
    end
  end
  def startObject(this) do
    Temper.Std.JsonTextProducer.beforeValue(this)
    TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :buffer), "{")
    TemperCore.List.add(TemperCore.Heap.get(this, :stack), 0)
    nil
  end
  def endObject(this) do
    TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :buffer), "}")
    currentState = Temper.Std.JsonTextProducer.state(this)
    _t = nil
    t = if 0 == currentState do
      t = true
      t
    else
      t = 2 == currentState
      t
    end
    if t do
      TemperCore.List.remove_last(TemperCore.Heap.get(this, :stack))
      nil
    else
      TemperCore.Heap.put(this, :wellFormed, false)
      nil
    end
    nil
  end
  def objectKey(this, key) do
    currentState = Temper.Std.JsonTextProducer.state(this)
    if not (currentState == 0) do
      if currentState == 2 do
        TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :buffer), ",")
        nil
      else
        TemperCore.Heap.put(this, :wellFormed, false)
        nil
      end
    else
      nil
    end
    Temper.Std.encodeJsonString(key, TemperCore.Heap.get(this, :buffer))
    TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :buffer), ":")
    if currentState >= 0 do
      TemperCore.List.set(TemperCore.Heap.get(this, :stack), TemperCore.int32(TemperCore.List.length(TemperCore.Heap.get(this, :stack)) - 1), 1)
      nil
    else
      nil
    end
    nil
  end
  def startArray(this) do
    Temper.Std.JsonTextProducer.beforeValue(this)
    TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :buffer), "[")
    TemperCore.List.add(TemperCore.Heap.get(this, :stack), 3)
    nil
  end
  def endArray(this) do
    TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :buffer), "]")
    currentState = Temper.Std.JsonTextProducer.state(this)
    _t = nil
    t = if 3 == currentState do
      t = true
      t
    else
      t = 4 == currentState
      t
    end
    if t do
      TemperCore.List.remove_last(TemperCore.Heap.get(this, :stack))
      nil
    else
      TemperCore.Heap.put(this, :wellFormed, false)
      nil
    end
    nil
  end
  def nullValue(this) do
    Temper.Std.JsonTextProducer.beforeValue(this)
    TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :buffer), "null")
    nil
  end
  def booleanValue(this, x) do
    _t1 = nil
    Temper.Std.JsonTextProducer.beforeValue(this)
    t2 = TemperCore.Heap.get(this, :buffer)
    t1 = if x do
      t1 = "true"
      t1
    else
      t1 = "false"
      t1
    end
    TemperCore.StringBuilder.append(t2, t1)
    nil
  end
  def int32Value(this, x) do
    Temper.Std.JsonTextProducer.beforeValue(this)
    TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :buffer), TemperCore.int_to_string(x))
    nil
  end
  def int64Value(this, x) do
    Temper.Std.JsonTextProducer.beforeValue(this)
    TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :buffer), TemperCore.int_to_string(x))
    nil
  end
  def float64Value(this, x) do
    Temper.Std.JsonTextProducer.beforeValue(this)
    TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :buffer), TemperCore.Float.to_string(x))
    nil
  end
  def numericTokenValue(this, x) do
    Temper.Std.JsonTextProducer.beforeValue(this)
    TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :buffer), x)
    nil
  end
  def stringValue(this, x) do
    Temper.Std.JsonTextProducer.beforeValue(this)
    Temper.Std.encodeJsonString(x, TemperCore.Heap.get(this, :buffer))
    nil
  end
  def toJsonString(this) do
    _t = nil
    t = if TemperCore.Heap.get(this, :wellFormed) do
      if TemperCore.List.length(TemperCore.Heap.get(this, :stack)) == 1 do
        t = Temper.Std.JsonTextProducer.state(this) == 6
        t
      else
        t = false
        t
      end
    else
      t = false
      t
    end
    if t do
      TemperCore.StringBuilder.to_string(TemperCore.Heap.get(this, :buffer))
    else
      raise(TemperCore.Bubble)
    end
  end
  def get_interchangeContext(this) do
    TemperCore.Heap.get(this, :interchangeContext)
  end
  def get_parseErrorReceiver(_this) do
    nil
  end
end
defmodule Temper.Std.JsonParseErrorReceiver do
  def __temper_supertypes__() do
    [Temper.Std.JsonParseErrorReceiver]
  end
  def explainJsonError(_this, _explanation) do
    raise(TemperCore.Panic)
  end
end
defmodule Temper.Std.JsonSyntaxTreeProducer do
  def __temper_supertypes__() do
    [Temper.Std.JsonSyntaxTreeProducer, Temper.Std.JsonProducer, Temper.Std.JsonParseErrorReceiver]
  end
  def get_interchangeContext(_this) do
    TemperCore.Global.get(:"Temper.Std.NullInterchangeContext.instance")
  end
  def new() do
    Temper.Std.__temper_init__()
    this = TemperCore.Heap.new(Temper.Std.JsonSyntaxTreeProducer, %{:stack => nil, :error => nil})
    t = TemperCore.List.builder()
    TemperCore.Heap.put(this, :stack, t)
    TemperCore.List.add(TemperCore.Heap.get(this, :stack), TemperCore.List.builder())
    TemperCore.Heap.put(this, :error, nil)
    this
  end
  def storeValue(this, v) do
    if not TemperCore.List.is_empty(TemperCore.Heap.get(this, :stack)) do
      TemperCore.List.add(TemperCore.List.get(TemperCore.Heap.get(this, :stack), TemperCore.int32(TemperCore.List.length(TemperCore.Heap.get(this, :stack)) - 1)), v)
      nil
    else
      nil
    end
    nil
  end
  def startObject(this) do
    TemperCore.List.add(TemperCore.Heap.get(this, :stack), TemperCore.List.builder())
    nil
  end
  def endObject(this) do
    _return = nil
    return = if true do
      return = nil
      if TemperCore.List.is_empty(TemperCore.Heap.get(this, :stack)) do
        return
      else
        ls = TemperCore.List.remove_last(TemperCore.Heap.get(this, :stack))
        m = TemperCore.Map.builder()
        multis1 = nil
        i = 0
        n = TemperCore.int32(Bitwise.band(TemperCore.List.length(ls), -2))
        ex_loop_2 = fn ex_loop_2, i, multis1 ->
          if i < n do
            _t1 = nil
            postfixReturn1 = i
            i = TemperCore.int32(postfixReturn1 + 1)
            keyTree = TemperCore.List.get(ls, postfixReturn1)
            if not TemperCore.is_a(keyTree, Temper.Std.JsonString) do
              {i, multis1}
            else
              t1 = try do
                t1 = TemperCore.cast(keyTree, Temper.Std.JsonString)
                t1
              rescue
                _ in TemperCore.Bubble ->
                  raise(TemperCore.Panic)
              end
              key = Temper.Std.JsonString.get_content(t1)
              postfixReturn2 = i
              i = TemperCore.int32(postfixReturn2 + 1)
              value = TemperCore.List.get(ls, postfixReturn2)
              if TemperCore.Map.has(m, key) do
                _t2 = nil
                multis1 = if multis1 === nil do
                  multis1 = TemperCore.Map.builder()
                  multis1
                else
                  multis1
                end
                _mb = nil
                mb = try do
                  if multis1 === nil do
                    raise(TemperCore.Bubble)
                  else
                    mb = multis1
                    mb
                  end
                rescue
                  _ in TemperCore.Bubble ->
                    raise(TemperCore.Panic)
                end
                if not TemperCore.Map.has(mb, key) do
                  _t3 = nil
                  t3 = try do
                    t3 = TemperCore.Map.get(m, key)
                    t3
                  rescue
                    _ in TemperCore.Bubble ->
                      raise(TemperCore.Panic)
                  end
                  TemperCore.Map.set(mb, key, TemperCore.List.to_builder(t3))
                  nil
                else
                  nil
                end
                t2 = try do
                  t2 = TemperCore.Map.get(mb, key)
                  t2
                rescue
                  _ in TemperCore.Bubble ->
                    raise(TemperCore.Panic)
                end
                TemperCore.List.add(t2, value)
                ex_loop_2.(ex_loop_2, i, multis1)
              else
                TemperCore.Map.set(m, key, %TemperCore.Vec{t: {value}})
                ex_loop_2.(ex_loop_2, i, multis1)
              end
            end
          else
            {i, multis1}
          end
        end
        {_i, multis1} = ex_loop_2.(ex_loop_2, i, multis1)
        multis2 = multis1
        if not (multis2 === nil) do
          fn_ = fn k, vs ->
            TemperCore.Map.set(m, k, TemperCore.List.to_list(vs))
            nil
          end
          TemperCore.Map.for_each(multis2, fn_)
          nil
        else
          nil
        end
        Temper.Std.JsonSyntaxTreeProducer.storeValue(this, Temper.Std.JsonObject.new(TemperCore.Map.to_map(m)))
        return
      end
    end
    return
  end
  def objectKey(this, key) do
    Temper.Std.JsonSyntaxTreeProducer.storeValue(this, Temper.Std.JsonString.new(key))
    nil
  end
  def startArray(this) do
    TemperCore.List.add(TemperCore.Heap.get(this, :stack), TemperCore.List.builder())
    nil
  end
  def endArray(this) do
    _return = nil
    return = if true do
      return = nil
      if TemperCore.List.is_empty(TemperCore.Heap.get(this, :stack)) do
        return
      else
        ls = TemperCore.List.remove_last(TemperCore.Heap.get(this, :stack))
        Temper.Std.JsonSyntaxTreeProducer.storeValue(this, Temper.Std.JsonArray.new(TemperCore.List.to_list(ls)))
        return
      end
    end
    return
  end
  def nullValue(this) do
    Temper.Std.JsonSyntaxTreeProducer.storeValue(this, Temper.Std.JsonNull.new())
    nil
  end
  def booleanValue(this, x) do
    Temper.Std.JsonSyntaxTreeProducer.storeValue(this, Temper.Std.JsonBoolean.new(x))
    nil
  end
  def int32Value(this, x) do
    Temper.Std.JsonSyntaxTreeProducer.storeValue(this, Temper.Std.JsonInt32.new(x))
    nil
  end
  def int64Value(this, x) do
    Temper.Std.JsonSyntaxTreeProducer.storeValue(this, Temper.Std.JsonInt64.new(x))
    nil
  end
  def float64Value(this, x) do
    Temper.Std.JsonSyntaxTreeProducer.storeValue(this, Temper.Std.JsonFloat64.new(x))
    nil
  end
  def numericTokenValue(this, x) do
    Temper.Std.JsonSyntaxTreeProducer.storeValue(this, Temper.Std.JsonNumericToken.new(x))
    nil
  end
  def stringValue(this, x) do
    Temper.Std.JsonSyntaxTreeProducer.storeValue(this, Temper.Std.JsonString.new(x))
    nil
  end
  def toJsonSyntaxTree(this) do
    _t = nil
    t = if TemperCore.List.length(TemperCore.Heap.get(this, :stack)) != 1 do
      t = true
      t
    else
      t = not (TemperCore.Heap.get(this, :error) === nil)
      t
    end
    if t do
      raise(TemperCore.Bubble)
    else
      ls = TemperCore.List.get(TemperCore.Heap.get(this, :stack), 0)
      if TemperCore.List.length(ls) != 1 do
        raise(TemperCore.Bubble)
      else
        TemperCore.List.get(ls, 0)
      end
    end
  end
  def get_jsonError(this) do
    TemperCore.Heap.get(this, :error)
  end
  def get_parseErrorReceiver(this) do
    this
  end
  def get_parseErrorReceiverSafe(this) do
    this
  end
  def explainJsonError(this, error) do
    TemperCore.Heap.put(this, :error, error)
    nil
  end
end
defmodule Temper.Std.JsonAdapter do
  def __temper_supertypes__() do
    [Temper.Std.JsonAdapter]
  end
  def encodeToJson(_this, _x, _p) do
    raise(TemperCore.Panic)
  end
  def decodeFromJson(_this, _t, _ic) do
    raise(TemperCore.Panic)
  end
end
defmodule Temper.Std.BooleanJsonAdapter do
  defstruct []
  def __temper_supertypes__() do
    [Temper.Std.BooleanJsonAdapter, Temper.Std.JsonAdapter]
  end
  def encodeToJson(_this, x, p) do
    TemperCore.call(p, :booleanValue, [x])
    nil
  end
  def decodeFromJson(_this, t1, _ic) do
    t2 = TemperCore.cast(t1, Temper.Std.JsonBoolean)
    Temper.Std.JsonBoolean.get_content(t2)
  end
  def new() do
    this = %Temper.Std.BooleanJsonAdapter{}
    this
  end
end
defmodule Temper.Std.Float64JsonAdapter do
  defstruct []
  def __temper_supertypes__() do
    [Temper.Std.Float64JsonAdapter, Temper.Std.JsonAdapter]
  end
  def encodeToJson(_this, x, p) do
    TemperCore.call(p, :float64Value, [x])
    nil
  end
  def decodeFromJson(_this, t1, _ic) do
    t2 = TemperCore.cast(t1, Temper.Std.JsonNumeric)
    TemperCore.call(t2, :asFloat64, [])
  end
  def new() do
    this = %Temper.Std.Float64JsonAdapter{}
    this
  end
end
defmodule Temper.Std.Int32JsonAdapter do
  defstruct []
  def __temper_supertypes__() do
    [Temper.Std.Int32JsonAdapter, Temper.Std.JsonAdapter]
  end
  def encodeToJson(_this, x, p) do
    TemperCore.call(p, :int32Value, [x])
    nil
  end
  def decodeFromJson(_this, t1, _ic) do
    t2 = TemperCore.cast(t1, Temper.Std.JsonNumeric)
    TemperCore.call(t2, :asInt32, [])
  end
  def new() do
    this = %Temper.Std.Int32JsonAdapter{}
    this
  end
end
defmodule Temper.Std.Int64JsonAdapter do
  defstruct []
  def __temper_supertypes__() do
    [Temper.Std.Int64JsonAdapter, Temper.Std.JsonAdapter]
  end
  def encodeToJson(_this, x, p) do
    TemperCore.call(p, :int64Value, [x])
    nil
  end
  def decodeFromJson(_this, t1, _ic) do
    t2 = TemperCore.cast(t1, Temper.Std.JsonNumeric)
    TemperCore.call(t2, :asInt64, [])
  end
  def new() do
    this = %Temper.Std.Int64JsonAdapter{}
    this
  end
end
defmodule Temper.Std.StringJsonAdapter do
  defstruct []
  def __temper_supertypes__() do
    [Temper.Std.StringJsonAdapter, Temper.Std.JsonAdapter]
  end
  def encodeToJson(_this, x, p) do
    TemperCore.call(p, :stringValue, [x])
    nil
  end
  def decodeFromJson(_this, t1, _ic) do
    t2 = TemperCore.cast(t1, Temper.Std.JsonString)
    Temper.Std.JsonString.get_content(t2)
  end
  def new() do
    this = %Temper.Std.StringJsonAdapter{}
    this
  end
end
defmodule Temper.Std.ListJsonAdapter do
  def __temper_supertypes__() do
    [Temper.Std.ListJsonAdapter, Temper.Std.JsonAdapter]
  end
  def encodeToJson(this1, x, p) do
    TemperCore.call(p, :startArray, [])
    this2 = x
    n = TemperCore.List.length(this2)
    i = 0
    ex_loop_1 = fn ex_loop_1, i ->
      if i < n do
        el1 = TemperCore.List.get(this2, i)
        i = TemperCore.int32(i + 1)
        el2 = el1
        TemperCore.call(TemperCore.Heap.get(this1, :adapterForT), :encodeToJson, [el2, p])
        ex_loop_1.(ex_loop_1, i)
      else
        i
      end
    end
    _i = ex_loop_1.(ex_loop_1, i)
    TemperCore.call(p, :endArray, [])
    nil
  end
  def decodeFromJson(this, t1, ic) do
    b = TemperCore.List.builder()
    t2 = TemperCore.cast(t1, Temper.Std.JsonArray)
    elements = Temper.Std.JsonArray.get_elements(t2)
    n = TemperCore.List.length(elements)
    i = 0
    ex_loop_1 = fn ex_loop_1, i ->
      if i < n do
        el = TemperCore.List.get(elements, i)
        i = TemperCore.int32(i + 1)
        t3 = TemperCore.call(TemperCore.Heap.get(this, :adapterForT), :decodeFromJson, [el, ic])
        TemperCore.List.add(b, t3)
        ex_loop_1.(ex_loop_1, i)
      else
        i
      end
    end
    _i = ex_loop_1.(ex_loop_1, i)
    TemperCore.List.to_list(b)
  end
  def new(adapterForT) do
    this = TemperCore.Heap.new(Temper.Std.ListJsonAdapter, %{:adapterForT => nil})
    TemperCore.Heap.put(this, :adapterForT, adapterForT)
    this
  end
end
defmodule Temper.Std.OrNullJsonAdapter do
  def __temper_supertypes__() do
    [Temper.Std.OrNullJsonAdapter, Temper.Std.JsonAdapter]
  end
  def encodeToJson(this, x1, p) do
    if x1 === nil do
      TemperCore.call(p, :nullValue, [])
      nil
    else
      x2 = x1
      TemperCore.call(TemperCore.Heap.get(this, :adapterForT), :encodeToJson, [x2, p])
      nil
    end
    nil
  end
  def decodeFromJson(this, t, ic) do
    if TemperCore.is_a(t, Temper.Std.JsonNull) do
      nil
    else
      TemperCore.call(TemperCore.Heap.get(this, :adapterForT), :decodeFromJson, [t, ic])
    end
  end
  def new(adapterForT) do
    Temper.Std.__temper_init__()
    this = TemperCore.Heap.new(Temper.Std.OrNullJsonAdapter, %{:adapterForT => nil})
    TemperCore.Heap.put(this, :adapterForT, adapterForT)
    this
  end
end
defmodule Temper.Std.DateJsonAdapter do
  def __temper_supertypes__() do
    [Temper.Std.DateJsonAdapter, Temper.Std.JsonAdapter]
  end
  def encodeToJson(_this, x, p) do
    Temper.Std.Date.encodeToJson(x, p)
    nil
  end
  def decodeFromJson(_this, t, ic) do
    Temper.Std.Date.decodeFromJson(t, ic)
  end
  def new() do
    this = TemperCore.Heap.new(Temper.Std.DateJsonAdapter, %{})
    this
  end
end
defmodule Temper.Std.Date do
  defstruct [:year, :month, :day]
  def __temper_supertypes__() do
    [Temper.Std.Date]
  end
  def new(year, month, day) do
    Temper.Std.__temper_init__()
    this = %Temper.Std.Date{}
    _t1 = nil
    t1 = if 1 <= month do
      if month <= 12 do
        if 1 <= day do
          _t2 = nil
          t2 = if month != 2 do
            t2 = true
            t2
          else
            t2 = day != 29
            t2
          end
          if t2 do
            t1 = day <= TemperCore.List.get(TemperCore.Global.get(:"Temper.Std.daysInMonth"), month)
            t1
          else
            t1 = Temper.Std.isLeapYear(year)
            t1
          end
        else
          t1 = false
          t1
        end
      else
        t1 = false
        t1
      end
    else
      t1 = false
      t1
    end
    if t1 do
      this = %{this | :year => year}
      this = %{this | :month => month}
      this = %{this | :day => day}
      this
    else
      raise(TemperCore.Bubble)
    end
  end
  def toString(this) do
    sb = TemperCore.StringBuilder.new()
    Temper.Std.padTo(4, this.year, sb)
    TemperCore.StringBuilder.append(sb, "-")
    Temper.Std.padTo(2, this.month, sb)
    TemperCore.StringBuilder.append(sb, "-")
    Temper.Std.padTo(2, this.day, sb)
    TemperCore.StringBuilder.to_string(sb)
  end
  def fromIsoString(isoString) do
    end_ = TemperCore.String.end_of(isoString)
    strIndex = TemperCore.String.prev(isoString, TemperCore.String.prev(isoString, end_))
    beforeDay = strIndex
    strIndex = TemperCore.String.prev(isoString, strIndex)
    afterMonth = strIndex
    _t1 = nil
    t1 = if not TemperCore.String.has_index(isoString, afterMonth) do
      t1 = true
      t1
    else
      t1 = TemperCore.String.get(isoString, strIndex) != 45
      t1
    end
    if t1 do
      raise(TemperCore.Bubble)
    else
      strIndex = TemperCore.String.prev(isoString, TemperCore.String.prev(isoString, strIndex))
      beforeMonth = strIndex
      strIndex = TemperCore.String.prev(isoString, strIndex)
      _t2 = nil
      t2 = if TemperCore.String.get(isoString, strIndex) != 45 do
        t2 = true
        t2
      else
        t2 = not TemperCore.String.has_at_least(isoString, TemperCore.String.begin(), strIndex, 4)
        t2
      end
      if t2 do
        raise(TemperCore.Bubble)
      else
        day = TemperCore.String.to_int32(TemperCore.String.slice(isoString, beforeDay, end_), 10)
        month = TemperCore.String.to_int32(TemperCore.String.slice(isoString, beforeMonth, afterMonth), 10)
        year = TemperCore.String.to_int32(TemperCore.String.slice(isoString, TemperCore.String.begin(), strIndex), 10)
        Temper.Std.Date.new(year, month, day)
      end
    end
  end
  def yearsBetween(start, end_) do
    _t1 = nil
    yearDelta = TemperCore.int32(Temper.Std.Date.get_year(end_) - Temper.Std.Date.get_year(start))
    monthDelta = TemperCore.int32(Temper.Std.Date.get_month(end_) - Temper.Std.Date.get_month(start))
    _t2 = nil
    t2 = cond do
      monthDelta < 0 ->
        t2 = true
        t2
      monthDelta == 0 ->
        t2 = Temper.Std.Date.get_day(end_) < Temper.Std.Date.get_day(start)
        t2
      true ->
        t2 = false
        t2
    end
    t1 = if t2 do
      t1 = 1
      t1
    else
      t1 = 0
      t1
    end
    TemperCore.int32(yearDelta - t1)
  end
  def get_dayOfWeek(this) do
    y = this.year
    _c = nil
    c = if y >= 0 do
      c = TemperCore.int32(div(y, 100))
      c
    else
      c = TemperCore.int32(-TemperCore.int32(div(TemperCore.int32(-y), 100)))
      c
    end
    yy = TemperCore.int32(y - TemperCore.int32(c * 100))
    janFirst = rem(TemperCore.int32(TemperCore.int32(TemperCore.int32(8 + TemperCore.int32(5 * rem(TemperCore.int32(yy + 3), 4))) + TemperCore.int32(3 * TemperCore.int32(yy - 1))) + TemperCore.int32(5 * rem(c, 4))), 7)
    _table = nil
    table = if Temper.Std.isLeapYear(y) do
      table = TemperCore.Global.get(:"Temper.Std.dayOfWeekLookupTableLeapy")
      table
    else
      table = TemperCore.Global.get(:"Temper.Std.dayOfWeekLookupTableNotLeapy")
      table
    end
    monthOffset = TemperCore.List.get(table, this.month)
    gaussWeekday = rem(TemperCore.int32(TemperCore.int32(janFirst + TemperCore.int32(this.day + 6)) + monthOffset), 7)
    if gaussWeekday == 0 do
      7
    else
      gaussWeekday
    end
  end
  def encodeToJson(this, p) do
    TemperCore.call(p, :stringValue, [Temper.Std.Date.toString(this)])
    nil
  end
  def decodeFromJson(t1, _ic) do
    t2 = TemperCore.cast(t1, Temper.Std.JsonString)
    Temper.Std.Date.fromIsoString(Temper.Std.JsonString.get_content(t2))
  end
  def get_year(this) do
    this.year
  end
  def get_month(this) do
    this.month
  end
  def get_day(this) do
    this.day
  end
  def jsonAdapter() do
    Temper.Std.DateJsonAdapter.new()
  end
end
defmodule Temper.Std.Test do
  def __temper_supertypes__() do
    [Temper.Std.Test]
  end
  def softFailToHard(this) do
    if Temper.Std.Test.get_hasUnhandledFail(this) do
      TemperCore.Heap.put(this, :u_failedOnAssert, true)
      TemperCore.Test.bail(this)
      nil
    else
      nil
    end
    nil
  end
  def get_hasUnhandledFail(this) do
    _t = nil
    t = if TemperCore.Heap.get(this, :u_failedOnAssert) do
      t = true
      t
    else
      t = TemperCore.Heap.get(this, :u_passing)
      t
    end
    not t
  end
  def messagesCombined(this) do
    if TemperCore.List.is_empty(TemperCore.Heap.get(this, :u_messages)) do
      nil
    else
      fn_ = fn it ->
        it
      end
      TemperCore.List.join(TemperCore.Heap.get(this, :u_messages), ", ", fn_)
    end
  end
  def new() do
    Temper.Std.__temper_init__()
    this = TemperCore.Heap.new(Temper.Std.Test, %{:u_failedOnAssert => nil, :u_passing => nil, :u_messages => nil})
    TemperCore.Heap.put(this, :u_failedOnAssert, false)
    TemperCore.Heap.put(this, :u_passing, true)
    t = TemperCore.List.builder()
    TemperCore.Heap.put(this, :u_messages, t)
    this
  end
end
defmodule Temper.Std.NetRequest do
  def __temper_supertypes__() do
    [Temper.Std.NetRequest]
  end
  def post(this, content, _mimeType) do
    TemperCore.Heap.put(this, :method, "POST")
    TemperCore.Heap.put(this, :bodyContent, content)
    t = TemperCore.Heap.get(this, :bodyMimeType)
    TemperCore.Heap.put(this, :bodyMimeType, t)
    nil
  end
  def send_(this) do
    TemperCore.Net.send_request(TemperCore.Heap.get(this, :url), TemperCore.Heap.get(this, :method), TemperCore.Heap.get(this, :bodyContent), TemperCore.Heap.get(this, :bodyMimeType))
  end
  def new(url) do
    Temper.Std.__temper_init__()
    this = TemperCore.Heap.new(Temper.Std.NetRequest, %{:url => nil, :method => nil, :bodyContent => nil, :bodyMimeType => nil})
    TemperCore.Heap.put(this, :url, url)
    TemperCore.Heap.put(this, :method, "GET")
    TemperCore.Heap.put(this, :bodyContent, nil)
    TemperCore.Heap.put(this, :bodyMimeType, nil)
    this
  end
end
defmodule Temper.Std.NetResponse do
  def __temper_supertypes__() do
    [Temper.Std.NetResponse]
  end
end
defmodule Temper.Std.RegexNode do
  def __temper_supertypes__() do
    [Temper.Std.RegexNode]
  end
  def compiled(this) do
    Temper.Std.Regex.new(this)
  end
  def found(this, text) do
    Temper.Std.Regex.found(TemperCore.call(this, :compiled, []), text)
  end
  def find(this, text) do
    Temper.Std.Regex.find(TemperCore.call(this, :compiled, []), text, nil)
  end
  def replace(this, text, format) do
    Temper.Std.Regex.replace(TemperCore.call(this, :compiled, []), text, format)
  end
  def split(this, text) do
    Temper.Std.Regex.split(TemperCore.call(this, :compiled, []), text)
  end
end
defmodule Temper.Std.Capture do
  defstruct [:name, :item]
  def __temper_supertypes__() do
    [Temper.Std.Capture, Temper.Std.RegexNode]
  end
  def new(name, item) do
    Temper.Std.__temper_init__()
    this = %Temper.Std.Capture{}
    this = %{this | :name => name}
    this = %{this | :item => item}
    this
  end
  def get_name(this) do
    this.name
  end
  def get_item(this) do
    this.item
  end
  def compiled(this) do
    Temper.Std.Regex.new(this)
  end
  def found(this, text) do
    Temper.Std.Regex.found(TemperCore.call(this, :compiled, []), text)
  end
  def find(this, text) do
    Temper.Std.Regex.find(TemperCore.call(this, :compiled, []), text, nil)
  end
  def replace(this, text, format) do
    Temper.Std.Regex.replace(TemperCore.call(this, :compiled, []), text, format)
  end
  def split(this, text) do
    Temper.Std.Regex.split(TemperCore.call(this, :compiled, []), text)
  end
end
defmodule Temper.Std.CodePart do
  def __temper_supertypes__() do
    [Temper.Std.CodePart, Temper.Std.RegexNode]
  end
end
defmodule Temper.Std.CodePoints do
  defstruct [:value]
  def __temper_supertypes__() do
    [Temper.Std.CodePoints, Temper.Std.CodePart, Temper.Std.RegexNode]
  end
  def new(value) do
    Temper.Std.__temper_init__()
    this = %Temper.Std.CodePoints{}
    this = %{this | :value => value}
    this
  end
  def get_value(this) do
    this.value
  end
  def compiled(this) do
    Temper.Std.Regex.new(this)
  end
  def found(this, text) do
    Temper.Std.Regex.found(TemperCore.call(this, :compiled, []), text)
  end
  def find(this, text) do
    Temper.Std.Regex.find(TemperCore.call(this, :compiled, []), text, nil)
  end
  def replace(this, text, format) do
    Temper.Std.Regex.replace(TemperCore.call(this, :compiled, []), text, format)
  end
  def split(this, text) do
    Temper.Std.Regex.split(TemperCore.call(this, :compiled, []), text)
  end
end
defmodule Temper.Std.Special do
  def __temper_supertypes__() do
    [Temper.Std.Special, Temper.Std.RegexNode]
  end
end
defmodule Temper.Std.SpecialSet do
  def __temper_supertypes__() do
    [Temper.Std.SpecialSet, Temper.Std.CodePart, Temper.Std.Special, Temper.Std.RegexNode]
  end
end
defmodule Temper.Std.CodeRange do
  defstruct [:min_, :max_]
  def __temper_supertypes__() do
    [Temper.Std.CodeRange, Temper.Std.CodePart, Temper.Std.RegexNode]
  end
  def new(min_, max_) do
    Temper.Std.__temper_init__()
    this = %Temper.Std.CodeRange{}
    this = %{this | :min_ => min_}
    this = %{this | :max_ => max_}
    this
  end
  def get_min(this) do
    this.min_
  end
  def get_max(this) do
    this.max_
  end
  def compiled(this) do
    Temper.Std.Regex.new(this)
  end
  def found(this, text) do
    Temper.Std.Regex.found(TemperCore.call(this, :compiled, []), text)
  end
  def find(this, text) do
    Temper.Std.Regex.find(TemperCore.call(this, :compiled, []), text, nil)
  end
  def replace(this, text, format) do
    Temper.Std.Regex.replace(TemperCore.call(this, :compiled, []), text, format)
  end
  def split(this, text) do
    Temper.Std.Regex.split(TemperCore.call(this, :compiled, []), text)
  end
end
defmodule Temper.Std.CodeSet do
  defstruct [:items, :negated]
  def __temper_supertypes__() do
    [Temper.Std.CodeSet, Temper.Std.RegexNode]
  end
  def new(items, negated1) do
    Temper.Std.__temper_init__()
    this = %Temper.Std.CodeSet{}
    _negated2 = nil
    negated2 = if negated1 === nil do
      negated2 = false
      negated2
    else
      negated2 = negated1
      negated2
    end
    this = %{this | :items => items}
    this = %{this | :negated => negated2}
    this
  end
  def get_items(this) do
    this.items
  end
  def get_negated(this) do
    this.negated
  end
  def compiled(this) do
    Temper.Std.Regex.new(this)
  end
  def found(this, text) do
    Temper.Std.Regex.found(TemperCore.call(this, :compiled, []), text)
  end
  def find(this, text) do
    Temper.Std.Regex.find(TemperCore.call(this, :compiled, []), text, nil)
  end
  def replace(this, text, format) do
    Temper.Std.Regex.replace(TemperCore.call(this, :compiled, []), text, format)
  end
  def split(this, text) do
    Temper.Std.Regex.split(TemperCore.call(this, :compiled, []), text)
  end
end
defmodule Temper.Std.Or do
  defstruct [:items]
  def __temper_supertypes__() do
    [Temper.Std.Or, Temper.Std.RegexNode]
  end
  def new(items) do
    Temper.Std.__temper_init__()
    this = %Temper.Std.Or{}
    this = %{this | :items => items}
    this
  end
  def get_items(this) do
    this.items
  end
  def compiled(this) do
    Temper.Std.Regex.new(this)
  end
  def found(this, text) do
    Temper.Std.Regex.found(TemperCore.call(this, :compiled, []), text)
  end
  def find(this, text) do
    Temper.Std.Regex.find(TemperCore.call(this, :compiled, []), text, nil)
  end
  def replace(this, text, format) do
    Temper.Std.Regex.replace(TemperCore.call(this, :compiled, []), text, format)
  end
  def split(this, text) do
    Temper.Std.Regex.split(TemperCore.call(this, :compiled, []), text)
  end
end
defmodule Temper.Std.Repeat do
  defstruct [:item, :min_, :max_, :reluctant]
  def __temper_supertypes__() do
    [Temper.Std.Repeat, Temper.Std.RegexNode]
  end
  def new(item, min_, max_, reluctant1) do
    Temper.Std.__temper_init__()
    this = %Temper.Std.Repeat{}
    _reluctant2 = nil
    reluctant2 = if reluctant1 === nil do
      reluctant2 = false
      reluctant2
    else
      reluctant2 = reluctant1
      reluctant2
    end
    this = %{this | :item => item}
    this = %{this | :min_ => min_}
    this = %{this | :max_ => max_}
    this = %{this | :reluctant => reluctant2}
    this
  end
  def get_item(this) do
    this.item
  end
  def get_min(this) do
    this.min_
  end
  def get_max(this) do
    this.max_
  end
  def get_reluctant(this) do
    this.reluctant
  end
  def compiled(this) do
    Temper.Std.Regex.new(this)
  end
  def found(this, text) do
    Temper.Std.Regex.found(TemperCore.call(this, :compiled, []), text)
  end
  def find(this, text) do
    Temper.Std.Regex.find(TemperCore.call(this, :compiled, []), text, nil)
  end
  def replace(this, text, format) do
    Temper.Std.Regex.replace(TemperCore.call(this, :compiled, []), text, format)
  end
  def split(this, text) do
    Temper.Std.Regex.split(TemperCore.call(this, :compiled, []), text)
  end
end
defmodule Temper.Std.Sequence do
  defstruct [:items]
  def __temper_supertypes__() do
    [Temper.Std.Sequence, Temper.Std.RegexNode]
  end
  def new(items) do
    Temper.Std.__temper_init__()
    this = %Temper.Std.Sequence{}
    this = %{this | :items => items}
    this
  end
  def get_items(this) do
    this.items
  end
  def compiled(this) do
    Temper.Std.Regex.new(this)
  end
  def found(this, text) do
    Temper.Std.Regex.found(TemperCore.call(this, :compiled, []), text)
  end
  def find(this, text) do
    Temper.Std.Regex.find(TemperCore.call(this, :compiled, []), text, nil)
  end
  def replace(this, text, format) do
    Temper.Std.Regex.replace(TemperCore.call(this, :compiled, []), text, format)
  end
  def split(this, text) do
    Temper.Std.Regex.split(TemperCore.call(this, :compiled, []), text)
  end
end
defmodule Temper.Std.Match do
  defstruct [:full, :groups]
  def __temper_supertypes__() do
    [Temper.Std.Match]
  end
  def new(full, groups) do
    Temper.Std.__temper_init__()
    this = %Temper.Std.Match{}
    this = %{this | :full => full}
    this = %{this | :groups => groups}
    this
  end
  def get_full(this) do
    this.full
  end
  def get_groups(this) do
    this.groups
  end
end
defmodule Temper.Std.Group do
  defstruct [:name, :value, :begin, :end_]
  def __temper_supertypes__() do
    [Temper.Std.Group]
  end
  def new(name, value, begin, end_) do
    Temper.Std.__temper_init__()
    this = %Temper.Std.Group{}
    this = %{this | :name => name}
    this = %{this | :value => value}
    this = %{this | :begin => begin}
    this = %{this | :end_ => end_}
    this
  end
  def get_name(this) do
    this.name
  end
  def get_value(this) do
    this.value
  end
  def get_begin(this) do
    this.begin
  end
  def get_end(this) do
    this.end_
  end
end
defmodule Temper.Std.RegexRefs do
  defstruct [:codePoints, :group, :match, :orObject]
  def __temper_supertypes__() do
    [Temper.Std.RegexRefs]
  end
  def new(codePoints1, group1, match1, orObject1) do
    this = %Temper.Std.RegexRefs{}
    _codePoints2 = nil
    codePoints2 = if codePoints1 === nil do
      codePoints2 = Temper.Std.CodePoints.new("")
      codePoints2
    else
      codePoints2 = codePoints1
      codePoints2
    end
    _group2 = nil
    group2 = if group1 === nil do
      group2 = Temper.Std.Group.new("", "", TemperCore.String.begin(), TemperCore.String.begin())
      group2
    else
      group2 = group1
      group2
    end
    _match2 = nil
    match2 = if match1 === nil do
      match2 = Temper.Std.Match.new(group2, TemperCore.Map.new(%TemperCore.Vec{t: {TemperCore.Pair.new("", group2)}}))
      match2
    else
      match2 = match1
      match2
    end
    _orObject2 = nil
    orObject2 = if orObject1 === nil do
      orObject2 = Temper.Std.Or.new(%TemperCore.Vec{t: {}})
      orObject2
    else
      orObject2 = orObject1
      orObject2
    end
    this = %{this | :codePoints => codePoints2}
    this = %{this | :group => group2}
    this = %{this | :match => match2}
    this = %{this | :orObject => orObject2}
    this
  end
  def get_codePoints(this) do
    this.codePoints
  end
  def get_group(this) do
    this.group
  end
  def get_match(this) do
    this.match
  end
  def get_orObject(this) do
    this.orObject
  end
end
defmodule Temper.Std.Regex do
  def __temper_supertypes__() do
    [Temper.Std.Regex]
  end
  def new(data) do
    Temper.Std.__temper_init__()
    this = TemperCore.Heap.new(Temper.Std.Regex, %{:data => nil, :compiled => nil})
    t1 = data
    TemperCore.Heap.put(this, :data, t1)
    formatted = Temper.Std.RegexFormatter.regexFormat(data)
    t2 = TemperCore.Regex.compile(formatted)
    TemperCore.Heap.put(this, :compiled, t2)
    this
  end
  def found(this, text) do
    TemperCore.Regex.found(TemperCore.Heap.get(this, :compiled), text)
  end
  def find(this, text, begin1) do
    _begin2 = nil
    begin2 = if begin1 === nil do
      begin2 = TemperCore.String.begin()
      begin2
    else
      begin2 = begin1
      begin2
    end
    TemperCore.Regex.find(TemperCore.Heap.get(this, :compiled), text, begin2, Temper.Std.Match, Temper.Std.Group)
  end
  def replace(this, text, format) do
    TemperCore.Regex.replace(TemperCore.Heap.get(this, :compiled), text, format, Temper.Std.Match, Temper.Std.Group)
  end
  def split(this, text) do
    TemperCore.Regex.split(TemperCore.Heap.get(this, :compiled), text)
  end
  def get_data(this) do
    TemperCore.Heap.get(this, :data)
  end
end
defmodule Temper.Std.RegexFormatter do
  def __temper_supertypes__() do
    [Temper.Std.RegexFormatter]
  end
  def regexFormat(data) do
    Temper.Std.RegexFormatter.format(Temper.Std.RegexFormatter.new(), data)
  end
  def format(this, regex) do
    Temper.Std.RegexFormatter.pushRegex(this, regex)
    TemperCore.StringBuilder.to_string(TemperCore.Heap.get(this, :out))
  end
  def pushRegex(this, regex) do
    cond do
      TemperCore.is_a(regex, Temper.Std.Capture) ->
        t1 = regex
        Temper.Std.RegexFormatter.pushCapture(this, t1)
        nil
      TemperCore.is_a(regex, Temper.Std.CodePoints) ->
        t2 = regex
        Temper.Std.RegexFormatter.pushCodePoints(this, t2, false)
        nil
      TemperCore.is_a(regex, Temper.Std.CodeRange) ->
        t3 = regex
        Temper.Std.RegexFormatter.pushCodeRange(this, t3)
        nil
      TemperCore.is_a(regex, Temper.Std.CodeSet) ->
        t4 = regex
        Temper.Std.RegexFormatter.pushCodeSet(this, t4)
        nil
      TemperCore.is_a(regex, Temper.Std.Or) ->
        t5 = regex
        Temper.Std.RegexFormatter.pushOr(this, t5)
        nil
      TemperCore.is_a(regex, Temper.Std.Repeat) ->
        t6 = regex
        Temper.Std.RegexFormatter.pushRepeat(this, t6)
        nil
      TemperCore.is_a(regex, Temper.Std.Sequence) ->
        t7 = regex
        Temper.Std.RegexFormatter.pushSequence(this, t7)
        nil
      regex == TemperCore.Global.get(:"Temper.Std.v_Begin") ->
        TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :out), "^")
        nil
      regex == TemperCore.Global.get(:"Temper.Std.v_Dot") ->
        TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :out), ".")
        nil
      regex == TemperCore.Global.get(:"Temper.Std.v_End") ->
        TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :out), "$")
        nil
      regex == TemperCore.Global.get(:"Temper.Std.v_WordBoundary") ->
        TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :out), "\\b")
        nil
      regex == TemperCore.Global.get(:"Temper.Std.v_Digit") ->
        TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :out), "\\d")
        nil
      regex == TemperCore.Global.get(:"Temper.Std.v_Space") ->
        TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :out), "\\s")
        nil
      regex == TemperCore.Global.get(:"Temper.Std.v_Word") ->
        TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :out), "\\w")
        nil
      true ->
        nil
    end
  end
  def pushCapture(this, capture) do
    TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :out), "(")
    Temper.Std.RegexFormatter.pushCaptureName(this, TemperCore.Heap.get(this, :out), Temper.Std.Capture.get_name(capture))
    Temper.Std.RegexFormatter.pushRegex(this, Temper.Std.Capture.get_item(capture))
    TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :out), ")")
    nil
  end
  def pushCaptureName(_this, out, name) do
    TemperCore.StringBuilder.append(out, "?<" <> name <> ">")
    nil
  end
  def pushCode(this, code, insideCodeSet) do
    try do
      return = nil
      return = try do
        return = try do
          _specialEscape = nil
          specialEscape = cond do
            code == TemperCore.Global.get(:"Temper.Std.Codes.carriageReturn") ->
              specialEscape = "r"
              specialEscape
            code == TemperCore.Global.get(:"Temper.Std.Codes.newline") ->
              specialEscape = "n"
              specialEscape
            code == TemperCore.Global.get(:"Temper.Std.Codes.tab") ->
              specialEscape = "t"
              specialEscape
            true ->
              specialEscape = ""
              specialEscape
          end
          if specialEscape != "" do
            TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :out), "\\")
            TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :out), specialEscape)
            return = nil
            throw({:temper_break, :ex_block_1, return})
          else
            _return = if code <= 127 do
              escapeNeed = TemperCore.List.get(TemperCore.Global.get(:"Temper.Std.escapeNeeds"), code)
              _t2 = nil
              t2 = cond do
                escapeNeed == 2 ->
                  t2 = true
                  t2
                insideCodeSet ->
                  t2 = code == TemperCore.Global.get(:"Temper.Std.Codes.dash")
                  t2
                true ->
                  t2 = false
                  t2
              end
              cond do
                t2 ->
                  TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :out), "\\")
                  t7 = TemperCore.Heap.get(this, :out)
                  t8 = TemperCore.String.from_code_point(code)
                  TemperCore.StringBuilder.append(t7, t8)
                  return = nil
                  throw({:temper_break, :ex_block_1, return})
                escapeNeed == 0 ->
                  t9 = TemperCore.Heap.get(this, :out)
                  t10 = TemperCore.String.from_code_point(code)
                  TemperCore.StringBuilder.append(t9, t10)
                  return = nil
                  throw({:temper_break, :ex_block_1, return})
                true ->
                  return
              end
            else
              return
            end
            _t1 = nil
            t1 = cond do
              code >= TemperCore.Global.get(:"Temper.Std.Codes.supplementalMin") ->
                t1 = true
                t1
              code > TemperCore.Global.get(:"Temper.Std.Codes.highControlMax") ->
                _t5 = nil
                _t6 = nil
                t6 = if TemperCore.Global.get(:"Temper.Std.Codes.surrogateMin") <= code do
                  t6 = code <= TemperCore.Global.get(:"Temper.Std.Codes.surrogateMax")
                  t6
                else
                  t6 = false
                  t6
                end
                t5 = if t6 do
                  t5 = true
                  t5
                else
                  t5 = code == TemperCore.Global.get(:"Temper.Std.Codes.uint16Max")
                  t5
                end
                t1 = not t5
                t1
              true ->
                t1 = false
                t1
            end
            if t1 do
              t3 = TemperCore.Heap.get(this, :out)
              t4 = TemperCore.String.from_code_point(code)
              TemperCore.StringBuilder.append(t3, t4)
              throw({:temper_return, :ex_return_0, nil})
            else
              TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :out), TemperCore.Regex.code_escape(code))
              throw({:temper_return, :ex_return_0, nil})
            end
          end
        rescue
          _ in TemperCore.Bubble ->
            raise(TemperCore.Bubble)
        end
        return
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
  def pushCodePoints(this, codePoints, insideCodeSet) do
    value = Temper.Std.CodePoints.get_value(codePoints)
    index = TemperCore.String.begin()
    ex_loop_1 = fn ex_loop_1, index ->
      if TemperCore.String.has_index(value, index) do
        Temper.Std.RegexFormatter.pushCode(this, TemperCore.String.get(value, index), insideCodeSet)
        index = TemperCore.String.next(value, index)
        ex_loop_1.(ex_loop_1, index)
      else
        index
      end
    end
    _index = ex_loop_1.(ex_loop_1, index)
    nil
  end
  def pushCodeRange(this, codeRange) do
    TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :out), "[")
    Temper.Std.RegexFormatter.pushCodeRangeUnwrapped(this, codeRange)
    TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :out), "]")
    nil
  end
  def pushCodeRangeUnwrapped(this, codeRange) do
    Temper.Std.RegexFormatter.pushCode(this, Temper.Std.CodeRange.get_min(codeRange), true)
    TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :out), "-")
    Temper.Std.RegexFormatter.pushCode(this, Temper.Std.CodeRange.get_max(codeRange), true)
    nil
  end
  def pushCodeSet(this, codeSet) do
    adjusted = Temper.Std.RegexFormatter.adjustCodeSet(this, codeSet, TemperCore.Global.get(:"Temper.Std.regexRefs"))
    if TemperCore.is_a(adjusted, Temper.Std.CodeSet) do
      t = adjusted
      if TemperCore.List.is_empty(Temper.Std.CodeSet.get_items(t)) do
        if Temper.Std.CodeSet.get_negated(t) do
          TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :out), "[\\s\\S]")
          nil
        else
          TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :out), "(?:$.)")
          nil
        end
      else
        TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :out), "[")
        if Temper.Std.CodeSet.get_negated(t) do
          TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :out), "^")
          nil
        else
          nil
        end
        i = 0
        ex_loop_1 = fn ex_loop_1, i ->
          if i < TemperCore.List.length(Temper.Std.CodeSet.get_items(t)) do
            Temper.Std.RegexFormatter.pushCodeSetItem(this, TemperCore.List.get(Temper.Std.CodeSet.get_items(t), i))
            i = TemperCore.int32(i + 1)
            ex_loop_1.(ex_loop_1, i)
          else
            i
          end
        end
        _i = ex_loop_1.(ex_loop_1, i)
        TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :out), "]")
        nil
      end
    else
      Temper.Std.RegexFormatter.pushRegex(this, adjusted)
      nil
    end
  end
  def adjustCodeSet(_this, codeSet, _regexRefs) do
    codeSet
  end
  def pushCodeSetItem(this, codePart) do
    cond do
      TemperCore.is_a(codePart, Temper.Std.CodePoints) ->
        t1 = codePart
        Temper.Std.RegexFormatter.pushCodePoints(this, t1, true)
        nil
      TemperCore.is_a(codePart, Temper.Std.CodeRange) ->
        t2 = codePart
        Temper.Std.RegexFormatter.pushCodeRangeUnwrapped(this, t2)
        nil
      TemperCore.is_a(codePart, Temper.Std.SpecialSet) ->
        t3 = codePart
        Temper.Std.RegexFormatter.pushRegex(this, t3)
        nil
      true ->
        nil
    end
  end
  def pushOr(this, or_) do
    if not TemperCore.List.is_empty(Temper.Std.Or.get_items(or_)) do
      TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :out), "(?:")
      Temper.Std.RegexFormatter.pushRegex(this, TemperCore.List.get(Temper.Std.Or.get_items(or_), 0))
      i = 1
      ex_loop_1 = fn ex_loop_1, i ->
        if i < TemperCore.List.length(Temper.Std.Or.get_items(or_)) do
          TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :out), "|")
          Temper.Std.RegexFormatter.pushRegex(this, TemperCore.List.get(Temper.Std.Or.get_items(or_), i))
          i = TemperCore.int32(i + 1)
          ex_loop_1.(ex_loop_1, i)
        else
          i
        end
      end
      _i = ex_loop_1.(ex_loop_1, i)
      TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :out), ")")
      nil
    else
      nil
    end
    nil
  end
  def pushRepeat(this, repeat) do
    TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :out), "(?:")
    Temper.Std.RegexFormatter.pushRegex(this, Temper.Std.Repeat.get_item(repeat))
    TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :out), ")")
    min_ = Temper.Std.Repeat.get_min(repeat)
    max_1 = Temper.Std.Repeat.get_max(repeat)
    _t1 = nil
    t1 = if min_ == 0 do
      t1 = max_1 == 1
      t1
    else
      t1 = false
      t1
    end
    if t1 do
      TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :out), "?")
      nil
    else
      _t2 = nil
      t2 = if min_ == 0 do
        t2 = max_1 === nil
        t2
      else
        t2 = false
        t2
      end
      if t2 do
        TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :out), "*")
        nil
      else
        _t3 = nil
        t3 = if min_ == 1 do
          t3 = max_1 === nil
          t3
        else
          t3 = false
          t3
        end
        if t3 do
          TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :out), "+")
          nil
        else
          TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :out), "{" <> TemperCore.int_to_string(min_))
          if min_ != max_1 do
            TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :out), ",")
            if not (max_1 === nil) do
              max_2 = max_1
              TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :out), TemperCore.int_to_string(max_2))
              nil
            else
              nil
            end
          else
            nil
          end
          TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :out), "}")
          nil
        end
      end
    end
    if Temper.Std.Repeat.get_reluctant(repeat) do
      TemperCore.StringBuilder.append(TemperCore.Heap.get(this, :out), "?")
      nil
    else
      nil
    end
    nil
  end
  def pushSequence(this, sequence) do
    i = 0
    ex_loop_1 = fn ex_loop_1, i ->
      if i < TemperCore.List.length(Temper.Std.Sequence.get_items(sequence)) do
        Temper.Std.RegexFormatter.pushRegex(this, TemperCore.List.get(Temper.Std.Sequence.get_items(sequence), i))
        i = TemperCore.int32(i + 1)
        ex_loop_1.(ex_loop_1, i)
      else
        i
      end
    end
    _i = ex_loop_1.(ex_loop_1, i)
    nil
  end
  def maxCode(_this, codePart) do
    cond do
      TemperCore.is_a(codePart, Temper.Std.CodePoints) ->
        t = codePart
        value = Temper.Std.CodePoints.get_value(t)
        if TemperCore.String.is_empty(value) do
          nil
        else
          max_ = 0
          index = TemperCore.String.begin()
          ex_loop_1 = fn ex_loop_1, index, max_ ->
            if TemperCore.String.has_index(value, index) do
              next = TemperCore.String.get(value, index)
              max_ = if next > max_ do
                max_ = next
                max_
              else
                max_
              end
              index = TemperCore.String.next(value, index)
              ex_loop_1.(ex_loop_1, index, max_)
            else
              {index, max_}
            end
          end
          {_index, max_} = ex_loop_1.(ex_loop_1, index, max_)
          max_
        end
      TemperCore.is_a(codePart, Temper.Std.CodeRange) ->
        Temper.Std.CodeRange.get_max(codePart)
      codePart == TemperCore.Global.get(:"Temper.Std.v_Digit") ->
        TemperCore.Global.get(:"Temper.Std.Codes.digit9")
      codePart == TemperCore.Global.get(:"Temper.Std.v_Space") ->
        TemperCore.Global.get(:"Temper.Std.Codes.space")
      codePart == TemperCore.Global.get(:"Temper.Std.v_Word") ->
        TemperCore.Global.get(:"Temper.Std.Codes.lowerZ")
      true ->
        nil
    end
  end
  def new() do
    this = TemperCore.Heap.new(Temper.Std.RegexFormatter, %{:out => nil})
    t = TemperCore.StringBuilder.new()
    TemperCore.Heap.put(this, :out, t)
    this
  end
end
defmodule Temper.Std.Codes do
  def __temper_supertypes__() do
    [Temper.Std.Codes]
  end
  def new() do
    this = TemperCore.Heap.new(Temper.Std.Codes, %{})
    this
  end
end
defmodule Temper.Std.Begin do
  def __temper_supertypes__() do
    [Temper.Std.Begin, Temper.Std.Special, Temper.Std.RegexNode]
  end
  def new() do
    this = TemperCore.Heap.new(Temper.Std.Begin, %{})
    this
  end
  def compiled(this) do
    Temper.Std.Regex.new(this)
  end
  def found(this, text) do
    Temper.Std.Regex.found(TemperCore.call(this, :compiled, []), text)
  end
  def find(this, text) do
    Temper.Std.Regex.find(TemperCore.call(this, :compiled, []), text, nil)
  end
  def replace(this, text, format) do
    Temper.Std.Regex.replace(TemperCore.call(this, :compiled, []), text, format)
  end
  def split(this, text) do
    Temper.Std.Regex.split(TemperCore.call(this, :compiled, []), text)
  end
end
defmodule Temper.Std.Dot do
  def __temper_supertypes__() do
    [Temper.Std.Dot, Temper.Std.Special, Temper.Std.RegexNode]
  end
  def new() do
    this = TemperCore.Heap.new(Temper.Std.Dot, %{})
    this
  end
  def compiled(this) do
    Temper.Std.Regex.new(this)
  end
  def found(this, text) do
    Temper.Std.Regex.found(TemperCore.call(this, :compiled, []), text)
  end
  def find(this, text) do
    Temper.Std.Regex.find(TemperCore.call(this, :compiled, []), text, nil)
  end
  def replace(this, text, format) do
    Temper.Std.Regex.replace(TemperCore.call(this, :compiled, []), text, format)
  end
  def split(this, text) do
    Temper.Std.Regex.split(TemperCore.call(this, :compiled, []), text)
  end
end
defmodule Temper.Std.End do
  def __temper_supertypes__() do
    [Temper.Std.End, Temper.Std.Special, Temper.Std.RegexNode]
  end
  def new() do
    this = TemperCore.Heap.new(Temper.Std.End, %{})
    this
  end
  def compiled(this) do
    Temper.Std.Regex.new(this)
  end
  def found(this, text) do
    Temper.Std.Regex.found(TemperCore.call(this, :compiled, []), text)
  end
  def find(this, text) do
    Temper.Std.Regex.find(TemperCore.call(this, :compiled, []), text, nil)
  end
  def replace(this, text, format) do
    Temper.Std.Regex.replace(TemperCore.call(this, :compiled, []), text, format)
  end
  def split(this, text) do
    Temper.Std.Regex.split(TemperCore.call(this, :compiled, []), text)
  end
end
defmodule Temper.Std.WordBoundary do
  defstruct []
  def __temper_supertypes__() do
    [Temper.Std.WordBoundary, Temper.Std.Special, Temper.Std.RegexNode]
  end
  def new() do
    this = %Temper.Std.WordBoundary{}
    this
  end
  def compiled(this) do
    Temper.Std.Regex.new(this)
  end
  def found(this, text) do
    Temper.Std.Regex.found(TemperCore.call(this, :compiled, []), text)
  end
  def find(this, text) do
    Temper.Std.Regex.find(TemperCore.call(this, :compiled, []), text, nil)
  end
  def replace(this, text, format) do
    Temper.Std.Regex.replace(TemperCore.call(this, :compiled, []), text, format)
  end
  def split(this, text) do
    Temper.Std.Regex.split(TemperCore.call(this, :compiled, []), text)
  end
end
defmodule Temper.Std.Digit do
  defstruct []
  def __temper_supertypes__() do
    [Temper.Std.Digit, Temper.Std.SpecialSet, Temper.Std.CodePart, Temper.Std.Special, Temper.Std.RegexNode]
  end
  def new() do
    this = %Temper.Std.Digit{}
    this
  end
  def compiled(this) do
    Temper.Std.Regex.new(this)
  end
  def found(this, text) do
    Temper.Std.Regex.found(TemperCore.call(this, :compiled, []), text)
  end
  def find(this, text) do
    Temper.Std.Regex.find(TemperCore.call(this, :compiled, []), text, nil)
  end
  def replace(this, text, format) do
    Temper.Std.Regex.replace(TemperCore.call(this, :compiled, []), text, format)
  end
  def split(this, text) do
    Temper.Std.Regex.split(TemperCore.call(this, :compiled, []), text)
  end
end
defmodule Temper.Std.Space do
  defstruct []
  def __temper_supertypes__() do
    [Temper.Std.Space, Temper.Std.SpecialSet, Temper.Std.CodePart, Temper.Std.Special, Temper.Std.RegexNode]
  end
  def new() do
    this = %Temper.Std.Space{}
    this
  end
  def compiled(this) do
    Temper.Std.Regex.new(this)
  end
  def found(this, text) do
    Temper.Std.Regex.found(TemperCore.call(this, :compiled, []), text)
  end
  def find(this, text) do
    Temper.Std.Regex.find(TemperCore.call(this, :compiled, []), text, nil)
  end
  def replace(this, text, format) do
    Temper.Std.Regex.replace(TemperCore.call(this, :compiled, []), text, format)
  end
  def split(this, text) do
    Temper.Std.Regex.split(TemperCore.call(this, :compiled, []), text)
  end
end
defmodule Temper.Std.Word do
  defstruct []
  def __temper_supertypes__() do
    [Temper.Std.Word, Temper.Std.SpecialSet, Temper.Std.CodePart, Temper.Std.Special, Temper.Std.RegexNode]
  end
  def new() do
    this = %Temper.Std.Word{}
    this
  end
  def compiled(this) do
    Temper.Std.Regex.new(this)
  end
  def found(this, text) do
    Temper.Std.Regex.found(TemperCore.call(this, :compiled, []), text)
  end
  def find(this, text) do
    Temper.Std.Regex.find(TemperCore.call(this, :compiled, []), text, nil)
  end
  def replace(this, text, format) do
    Temper.Std.Regex.replace(TemperCore.call(this, :compiled, []), text, format)
  end
  def split(this, text) do
    Temper.Std.Regex.split(TemperCore.call(this, :compiled, []), text)
  end
end
defmodule Temper.Std do
  def parseJsonValue(sourceText, i, out) do
    try do
      _return = nil
      {_i, return} = if true do
        i = Temper.Std.skipJsonSpaces(sourceText, i)
        if not TemperCore.String.has_index(sourceText, i) do
          Temper.Std.expectedTokenError(sourceText, i, out, "JSON value")
          return = TemperCore.String.none()
          {i, return}
        else
          subject = TemperCore.String.get(sourceText, i)
          cond do
            subject == 123 ->
              throw({:temper_return, :ex_return_0, Temper.Std.parseJsonObject(sourceText, i, out)})
            subject == 91 ->
              throw({:temper_return, :ex_return_0, Temper.Std.parseJsonArray(sourceText, i, out)})
            subject == 34 ->
              throw({:temper_return, :ex_return_0, Temper.Std.parseJsonString(sourceText, i, out)})
            true ->
              _t = nil
              t = if subject == 116 do
                t = true
                t
              else
                t = subject == 102
                t
              end
              cond do
                t ->
                  throw({:temper_return, :ex_return_0, Temper.Std.parseJsonBoolean(sourceText, i, out)})
                subject == 110 ->
                  throw({:temper_return, :ex_return_0, Temper.Std.parseJsonNull(sourceText, i, out)})
                true ->
                  throw({:temper_return, :ex_return_0, Temper.Std.parseJsonNumber(sourceText, i, out)})
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
  def encodeHex4(cp, buffer) do
    b0 = TemperCore.int32(Bitwise.band(TemperCore.int32(div(cp, 4096)), 15))
    b1 = TemperCore.int32(Bitwise.band(TemperCore.int32(div(cp, 256)), 15))
    b2 = TemperCore.int32(Bitwise.band(TemperCore.int32(div(cp, 16)), 15))
    b3 = TemperCore.int32(Bitwise.band(cp, 15))
    TemperCore.StringBuilder.append(buffer, TemperCore.List.get(TemperCore.Global.get(:"Temper.Std.hexDigits"), b0))
    TemperCore.StringBuilder.append(buffer, TemperCore.List.get(TemperCore.Global.get(:"Temper.Std.hexDigits"), b1))
    TemperCore.StringBuilder.append(buffer, TemperCore.List.get(TemperCore.Global.get(:"Temper.Std.hexDigits"), b2))
    TemperCore.StringBuilder.append(buffer, TemperCore.List.get(TemperCore.Global.get(:"Temper.Std.hexDigits"), b3))
    nil
  end
  def encodeJsonString(x, buffer) do
    TemperCore.StringBuilder.append(buffer, "\"")
    i = TemperCore.String.begin()
    emitted = i
    ex_loop_1 = fn ex_loop_1, emitted, i ->
      if TemperCore.String.has_index(x, i) do
        cp = TemperCore.String.get(x, i)
        _replacement = nil
        replacement = cond do
          cp == 8 ->
            replacement = "\\b"
            replacement
          cp == 9 ->
            replacement = "\\t"
            replacement
          cp == 10 ->
            replacement = "\\n"
            replacement
          cp == 12 ->
            replacement = "\\f"
            replacement
          cp == 13 ->
            replacement = "\\r"
            replacement
          cp == 34 ->
            replacement = "\\\""
            replacement
          cp == 92 ->
            replacement = "\\\\"
            replacement
          true ->
            _t = nil
            t = cond do
              cp < 32 ->
                t = true
                t
              55296 <= cp ->
                t = cp <= 57343
                t
              true ->
                t = false
                t
            end
            if t do
              replacement = "\\u"
              replacement
            else
              replacement = ""
              replacement
            end
        end
        nextI = TemperCore.String.next(x, i)
        emitted = if replacement != "" do
          TemperCore.StringBuilder.append_between(buffer, x, emitted, i)
          TemperCore.StringBuilder.append(buffer, replacement)
          if replacement == "\\u" do
            Temper.Std.encodeHex4(cp, buffer)
            nil
          else
            nil
          end
          emitted = nextI
          emitted
        else
          emitted
        end
        i = nextI
        ex_loop_1.(ex_loop_1, emitted, i)
      else
        {emitted, i}
      end
    end
    {emitted, i} = ex_loop_1.(ex_loop_1, emitted, i)
    TemperCore.StringBuilder.append_between(buffer, x, emitted, i)
    TemperCore.StringBuilder.append(buffer, "\"")
    nil
  end
  def storeJsonError(out, explanation) do
    subject = TemperCore.call(out, :get_parseErrorReceiver, [])
    if not (subject === nil) do
      TemperCore.call(subject, :explainJsonError, [explanation])
      nil
    else
      nil
    end
    nil
  end
  def expectedTokenError(sourceText, i, out, shortExplanation) do
    _gotten = nil
    gotten = if TemperCore.String.has_index(sourceText, i) do
      gotten = "`" <> TemperCore.String.slice(sourceText, i, TemperCore.String.end_of(sourceText)) <> "`"
      gotten
    else
      gotten = "end-of-file"
      gotten
    end
    Temper.Std.storeJsonError(out, "Expected " <> shortExplanation <> ", but got " <> gotten)
    nil
  end
  def skipJsonSpaces(sourceText, i) do
    ex_loop_1 = fn ex_loop_1, i ->
      if TemperCore.String.has_index(sourceText, i) do
        subject = TemperCore.String.get(sourceText, i)
        _t = nil
        t = cond do
          subject == 9 ->
            t = true
            t
          subject == 10 ->
            t = true
            t
          subject == 13 ->
            t = true
            t
          true ->
            t = subject == 32
            t
        end
        if not t do
          i
        else
          i = TemperCore.String.next(sourceText, i)
          ex_loop_1.(ex_loop_1, i)
        end
      else
        i
      end
    end
    i = ex_loop_1.(ex_loop_1, i)
    i
  end
  def decodeHexUnsigned(sourceText, start, limit) do
    try do
      return = nil
      return = try do
        n = 0
        i = start
        ex_loop_2 = fn ex_loop_2, i, n, return ->
          if TemperCore.cmp(i, limit) < 0 do
            cp = TemperCore.String.get(sourceText, i)
            _digit = nil
            _t1 = nil
            t1 = if 48 <= cp do
              t1 = cp <= 57
              t1
            else
              t1 = false
              t1
            end
            {digit, return} = if t1 do
              digit = TemperCore.int32(cp - 48)
              {digit, return}
            else
              _t2 = nil
              t2 = if 65 <= cp do
                t2 = cp <= 70
                t2
              else
                t2 = false
                t2
              end
              if t2 do
                digit = TemperCore.int32(TemperCore.int32(cp - 65) + 10)
                {digit, return}
              else
                _t3 = nil
                t3 = if 97 <= cp do
                  t3 = cp <= 102
                  t3
                else
                  t3 = false
                  t3
                end
                if t3 do
                  digit = TemperCore.int32(TemperCore.int32(cp - 97) + 10)
                  {digit, return}
                else
                  return = -1
                  throw({:temper_break, :ex_block_1, return})
                end
              end
            end
            n = TemperCore.int32(TemperCore.int32(n * 16) + digit)
            i = TemperCore.String.next(sourceText, i)
            ex_loop_2.(ex_loop_2, i, n, return)
          else
            {i, n, return}
          end
        end
        {_i, n, _return} = ex_loop_2.(ex_loop_2, i, n, return)
        throw({:temper_return, :ex_return_0, n})
      catch
        {:temper_break, :ex_block_1, ex_vars_4} ->
          ex_vars_4
      end
      return
    catch
      {:temper_return, :ex_return_0, ex_value_5} ->
        ex_value_5
    end
  end
  def parseJsonStringTo(sourceText, i, sb, errOut) do
    try do
      return = nil
      {_i, return} = try do
        _t1 = nil
        t1 = if not TemperCore.String.has_index(sourceText, i) do
          t1 = true
          t1
        else
          t1 = TemperCore.String.get(sourceText, i) != 34
          t1
        end
        if t1 do
          Temper.Std.expectedTokenError(sourceText, i, errOut, "\"")
          return = TemperCore.String.none()
          {i, return}
        else
          i = TemperCore.String.next(sourceText, i)
          leadSurrogate = -1
          consumed = i
          ex_loop_2 = fn ex_loop_2, consumed, i, leadSurrogate, return ->
            if TemperCore.String.has_index(sourceText, i) do
              _t3 = nil
              cp = TemperCore.String.get(sourceText, i)
              if cp == 34 do
                {consumed, i, leadSurrogate, return}
              else
                iNext = TemperCore.String.next(sourceText, i)
                end_ = TemperCore.String.end_of(sourceText)
                needToFlush = false
                {iNext, needToFlush, return, t3} = if cp != 92 do
                  t3 = cp
                  {iNext, needToFlush, return, t3}
                else
                  needToFlush = true
                  if not TemperCore.String.has_index(sourceText, iNext) do
                    Temper.Std.expectedTokenError(sourceText, iNext, errOut, "escape sequence")
                    return = TemperCore.String.none()
                    throw({:temper_break, :ex_block_1, {i, return}})
                  else
                    esc0 = TemperCore.String.get(sourceText, iNext)
                    iNext = TemperCore.String.next(sourceText, iNext)
                    _t4 = nil
                    t4 = cond do
                      esc0 == 34 ->
                        t4 = true
                        t4
                      esc0 == 92 ->
                        t4 = true
                        t4
                      true ->
                        t4 = esc0 == 47
                        t4
                    end
                    cond do
                      t4 ->
                        t3 = esc0
                        {iNext, needToFlush, return, t3}
                      esc0 == 98 ->
                        t3 = 8
                        {iNext, needToFlush, return, t3}
                      esc0 == 102 ->
                        t3 = 12
                        {iNext, needToFlush, return, t3}
                      esc0 == 110 ->
                        t3 = 10
                        {iNext, needToFlush, return, t3}
                      esc0 == 114 ->
                        t3 = 13
                        {iNext, needToFlush, return, t3}
                      esc0 == 116 ->
                        t3 = 9
                        {iNext, needToFlush, return, t3}
                      esc0 == 117 ->
                        _hex = nil
                        {hex, iNext} = if TemperCore.String.has_at_least(sourceText, iNext, end_, 4) do
                          startHex = iNext
                          iNext = TemperCore.String.next(sourceText, iNext)
                          iNext = TemperCore.String.next(sourceText, iNext)
                          iNext = TemperCore.String.next(sourceText, iNext)
                          iNext = TemperCore.String.next(sourceText, iNext)
                          hex = Temper.Std.decodeHexUnsigned(sourceText, startHex, iNext)
                          {hex, iNext}
                        else
                          hex = -1
                          {hex, iNext}
                        end
                        if hex < 0 do
                          Temper.Std.expectedTokenError(sourceText, iNext, errOut, "four hex digits")
                          return = TemperCore.String.none()
                          throw({:temper_break, :ex_block_1, {i, return}})
                        else
                          t3 = hex
                          {iNext, needToFlush, return, t3}
                        end
                      true ->
                        Temper.Std.expectedTokenError(sourceText, iNext, errOut, "escape sequence")
                        return = TemperCore.String.none()
                        throw({:temper_break, :ex_block_1, {i, return}})
                    end
                  end
                end
                decodedCp = t3
                {decodedCp, leadSurrogate, needToFlush} = if leadSurrogate >= 0 do
                  needToFlush = true
                  lead = leadSurrogate
                  _t5 = nil
                  t5 = if 56320 <= decodedCp do
                    t5 = decodedCp <= 57343
                    t5
                  else
                    t5 = false
                    t5
                  end
                  if t5 do
                    leadSurrogate = -1
                    decodedCp = TemperCore.int32(65536 + TemperCore.int32(Bitwise.bor(TemperCore.int32(TemperCore.int32(lead - 55296) * 1024), TemperCore.int32(decodedCp - 56320))))
                    {decodedCp, leadSurrogate, needToFlush}
                  else
                    {decodedCp, leadSurrogate, needToFlush}
                  end
                else
                  _t6 = nil
                  t6 = if 55296 <= decodedCp do
                    t6 = decodedCp <= 56319
                    t6
                  else
                    t6 = false
                    t6
                  end
                  if t6 do
                    needToFlush = true
                    {decodedCp, leadSurrogate, needToFlush}
                  else
                    {decodedCp, leadSurrogate, needToFlush}
                  end
                end
                {consumed, leadSurrogate} = if needToFlush do
                  TemperCore.StringBuilder.append_between(sb, sourceText, consumed, i)
                  if leadSurrogate >= 0 do
                    try do
                      TemperCore.StringBuilder.append_code_point(sb, leadSurrogate)
                      nil
                    rescue
                      _ in TemperCore.Bubble ->
                        raise(TemperCore.Bubble)
                    end
                    nil
                  else
                    nil
                  end
                  _t7 = nil
                  t7 = if 55296 <= decodedCp do
                    t7 = decodedCp <= 56319
                    t7
                  else
                    t7 = false
                    t7
                  end
                  leadSurrogate = if t7 do
                    leadSurrogate = decodedCp
                    leadSurrogate
                  else
                    leadSurrogate = -1
                    try do
                      TemperCore.StringBuilder.append_code_point(sb, decodedCp)
                      nil
                    rescue
                      _ in TemperCore.Bubble ->
                        raise(TemperCore.Bubble)
                    end
                    leadSurrogate
                  end
                  consumed = iNext
                  {consumed, leadSurrogate}
                else
                  {consumed, leadSurrogate}
                end
                i = iNext
                ex_loop_2.(ex_loop_2, consumed, i, leadSurrogate, return)
              end
            else
              {consumed, i, leadSurrogate, return}
            end
          end
          {consumed, i, leadSurrogate, _return} = ex_loop_2.(ex_loop_2, consumed, i, leadSurrogate, return)
          _t2 = nil
          t2 = if not TemperCore.String.has_index(sourceText, i) do
            t2 = true
            t2
          else
            t2 = TemperCore.String.get(sourceText, i) != 34
            t2
          end
          if t2 do
            Temper.Std.expectedTokenError(sourceText, i, errOut, "\"")
            throw({:temper_return, :ex_return_0, TemperCore.String.none()})
          else
            if leadSurrogate >= 0 do
              try do
                TemperCore.StringBuilder.append_code_point(sb, leadSurrogate)
                nil
              rescue
                _ in TemperCore.Bubble ->
                  raise(TemperCore.Bubble)
              end
              nil
            else
              TemperCore.StringBuilder.append_between(sb, sourceText, consumed, i)
              nil
            end
            i = TemperCore.String.next(sourceText, i)
            throw({:temper_return, :ex_return_0, i})
          end
        end
      catch
        {:temper_break, :ex_block_1, ex_vars_4} ->
          ex_vars_4
      end
      return
    catch
      {:temper_return, :ex_return_0, ex_value_5} ->
        ex_value_5
    end
  end
  def parseJsonObject(sourceText, i, out) do
    try do
      return = nil
      {_i, return} = try do
        {i, return} = try do
          _t1 = nil
          t1 = if not TemperCore.String.has_index(sourceText, i) do
            t1 = true
            t1
          else
            t1 = TemperCore.String.get(sourceText, i) != 123
            t1
          end
          if t1 do
            Temper.Std.expectedTokenError(sourceText, i, out, "'{'")
            return = TemperCore.String.none()
            throw({:temper_break, :ex_block_1, {i, return}})
          else
            TemperCore.call(out, :startObject, [])
            i = Temper.Std.skipJsonSpaces(sourceText, TemperCore.String.next(sourceText, i))
            _t2 = nil
            t2 = if TemperCore.String.has_index(sourceText, i) do
              t2 = TemperCore.String.get(sourceText, i) != 125
              t2
            else
              t2 = false
              t2
            end
            {i, _return} = if t2 do
              ex_loop_2 = fn ex_loop_2, i, return ->
                if true do
                  _t4 = nil
                  keyBuffer = TemperCore.StringBuilder.new()
                  afterKey = Temper.Std.parseJsonStringTo(sourceText, i, keyBuffer, out)
                  if not (afterKey >= 0) do
                    return = TemperCore.String.none()
                    throw({:temper_break, :ex_block_1, {i, return}})
                  else
                    TemperCore.call(out, :objectKey, [TemperCore.StringBuilder.to_string(keyBuffer)])
                    t4 = try do
                      t4 = case afterKey do
                        ex_index_4 ->
                          TemperCore.cast_check(ex_index_4, ex_index_4 >= 0)
                      end
                      t4
                    rescue
                      _ in TemperCore.Bubble ->
                        raise(TemperCore.Panic)
                    end
                    i = Temper.Std.skipJsonSpaces(sourceText, t4)
                    _t5 = nil
                    t5 = if TemperCore.String.has_index(sourceText, i) do
                      t5 = TemperCore.String.get(sourceText, i) == 58
                      t5
                    else
                      t5 = false
                      t5
                    end
                    if t5 do
                      i = TemperCore.String.next(sourceText, i)
                      afterPropertyValue = Temper.Std.parseJsonValue(sourceText, i, out)
                      if not (afterPropertyValue >= 0) do
                        return = TemperCore.String.none()
                        throw({:temper_break, :ex_block_1, {i, return}})
                      else
                        t7 = case afterPropertyValue do
                          ex_index_5 ->
                            TemperCore.cast_check(ex_index_5, ex_index_5 >= 0)
                        end
                        i = t7
                        i = Temper.Std.skipJsonSpaces(sourceText, i)
                        _t6 = nil
                        t6 = if TemperCore.String.has_index(sourceText, i) do
                          t6 = TemperCore.String.get(sourceText, i) == 44
                          t6
                        else
                          t6 = false
                          t6
                        end
                        if t6 do
                          i = Temper.Std.skipJsonSpaces(sourceText, TemperCore.String.next(sourceText, i))
                          ex_loop_2.(ex_loop_2, i, return)
                        else
                          {i, return}
                        end
                      end
                    else
                      Temper.Std.expectedTokenError(sourceText, i, out, "':'")
                      return = TemperCore.String.none()
                      throw({:temper_break, :ex_block_1, {i, return}})
                    end
                  end
                else
                  {i, return}
                end
              end
              {i, return} = ex_loop_2.(ex_loop_2, i, return)
              {i, return}
            else
              {i, return}
            end
            _t3 = nil
            t3 = if TemperCore.String.has_index(sourceText, i) do
              t3 = TemperCore.String.get(sourceText, i) == 125
              t3
            else
              t3 = false
              t3
            end
            if t3 do
              TemperCore.call(out, :endObject, [])
              throw({:temper_return, :ex_return_0, TemperCore.String.next(sourceText, i)})
            else
              Temper.Std.expectedTokenError(sourceText, i, out, "'}'")
              throw({:temper_return, :ex_return_0, TemperCore.String.none()})
            end
          end
        rescue
          _ in TemperCore.Bubble ->
            throw({:temper_return, :ex_return_0, raise(TemperCore.Panic)})
        end
        {i, return}
      catch
        {:temper_break, :ex_block_1, ex_vars_6} ->
          ex_vars_6
      end
      return
    catch
      {:temper_return, :ex_return_0, ex_value_7} ->
        ex_value_7
    end
  end
  def parseJsonArray(sourceText, i, out) do
    try do
      return = nil
      {_i, return} = try do
        {i, return} = try do
          _t1 = nil
          t1 = if not TemperCore.String.has_index(sourceText, i) do
            t1 = true
            t1
          else
            t1 = TemperCore.String.get(sourceText, i) != 91
            t1
          end
          if t1 do
            Temper.Std.expectedTokenError(sourceText, i, out, "'['")
            return = TemperCore.String.none()
            throw({:temper_break, :ex_block_1, {i, return}})
          else
            TemperCore.call(out, :startArray, [])
            i = Temper.Std.skipJsonSpaces(sourceText, TemperCore.String.next(sourceText, i))
            _t2 = nil
            t2 = if TemperCore.String.has_index(sourceText, i) do
              t2 = TemperCore.String.get(sourceText, i) != 93
              t2
            else
              t2 = false
              t2
            end
            {i, _return} = if t2 do
              ex_loop_2 = fn ex_loop_2, i, return ->
                if true do
                  afterElementValue = Temper.Std.parseJsonValue(sourceText, i, out)
                  if not (afterElementValue >= 0) do
                    return = TemperCore.String.none()
                    throw({:temper_break, :ex_block_1, {i, return}})
                  else
                    t4 = case afterElementValue do
                      ex_index_4 ->
                        TemperCore.cast_check(ex_index_4, ex_index_4 >= 0)
                    end
                    i = t4
                    i = Temper.Std.skipJsonSpaces(sourceText, i)
                    _t5 = nil
                    t5 = if TemperCore.String.has_index(sourceText, i) do
                      t5 = TemperCore.String.get(sourceText, i) == 44
                      t5
                    else
                      t5 = false
                      t5
                    end
                    if t5 do
                      i = Temper.Std.skipJsonSpaces(sourceText, TemperCore.String.next(sourceText, i))
                      ex_loop_2.(ex_loop_2, i, return)
                    else
                      {i, return}
                    end
                  end
                else
                  {i, return}
                end
              end
              {i, return} = ex_loop_2.(ex_loop_2, i, return)
              {i, return}
            else
              {i, return}
            end
            _t3 = nil
            t3 = if TemperCore.String.has_index(sourceText, i) do
              t3 = TemperCore.String.get(sourceText, i) == 93
              t3
            else
              t3 = false
              t3
            end
            if t3 do
              TemperCore.call(out, :endArray, [])
              throw({:temper_return, :ex_return_0, TemperCore.String.next(sourceText, i)})
            else
              Temper.Std.expectedTokenError(sourceText, i, out, "']'")
              throw({:temper_return, :ex_return_0, TemperCore.String.none()})
            end
          end
        rescue
          _ in TemperCore.Bubble ->
            throw({:temper_return, :ex_return_0, raise(TemperCore.Panic)})
        end
        {i, return}
      catch
        {:temper_break, :ex_block_1, ex_vars_5} ->
          ex_vars_5
      end
      return
    catch
      {:temper_return, :ex_return_0, ex_value_6} ->
        ex_value_6
    end
  end
  def parseJsonString(sourceText, i, out) do
    sb = TemperCore.StringBuilder.new()
    after_ = Temper.Std.parseJsonStringTo(sourceText, i, sb, out)
    if after_ >= 0 do
      TemperCore.call(out, :stringValue, [TemperCore.StringBuilder.to_string(sb)])
      nil
    else
      nil
    end
    after_
  end
  def afterSubstring(string, inString, substring) do
    try do
      return = nil
      return = try do
        i = inString
        j = TemperCore.String.begin()
        ex_loop_2 = fn ex_loop_2, i, j, return ->
          if TemperCore.String.has_index(substring, j) do
            cond do
              not TemperCore.String.has_index(string, i) ->
                return = TemperCore.String.none()
                throw({:temper_break, :ex_block_1, return})
              TemperCore.String.get(string, i) != TemperCore.String.get(substring, j) ->
                return = TemperCore.String.none()
                throw({:temper_break, :ex_block_1, return})
              true ->
                i = TemperCore.String.next(string, i)
                j = TemperCore.String.next(substring, j)
                ex_loop_2.(ex_loop_2, i, j, return)
            end
          else
            {i, j, return}
          end
        end
        {i, _j, _return} = ex_loop_2.(ex_loop_2, i, j, return)
        throw({:temper_return, :ex_return_0, i})
      catch
        {:temper_break, :ex_block_1, ex_vars_4} ->
          ex_vars_4
      end
      return
    catch
      {:temper_return, :ex_return_0, ex_value_5} ->
        ex_value_5
    end
  end
  def parseJsonBoolean(sourceText, i, out) do
    try do
      return = nil
      return = try do
        _ch0 = nil
        ch0 = if TemperCore.String.has_index(sourceText, i) do
          ch0 = TemperCore.String.get(sourceText, i)
          ch0
        else
          ch0 = 0
          ch0
        end
        end_ = TemperCore.String.end_of(sourceText)
        _keyword1 = nil
        _n = nil
        {keyword1, n} = cond do
          ch0 == 102 ->
            keyword1 = "false"
            n = 5
            {keyword1, n}
          ch0 == 116 ->
            keyword1 = "true"
            n = 4
            {keyword1, n}
          true ->
            keyword1 = nil
            n = 0
            {keyword1, n}
        end
        _return = if not (keyword1 === nil) do
          keyword2 = keyword1
          if TemperCore.String.has_at_least(sourceText, i, end_, n) do
            after_ = Temper.Std.afterSubstring(sourceText, i, keyword2)
            if after_ >= 0 do
              return = after_
              TemperCore.call(out, :booleanValue, [n == 4])
              throw({:temper_break, :ex_block_1, return})
            else
              return
            end
          else
            return
          end
        else
          return
        end
        Temper.Std.expectedTokenError(sourceText, i, out, "`false` or `true`")
        throw({:temper_return, :ex_return_0, TemperCore.String.none()})
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
  def parseJsonNull(sourceText, i, out) do
    try do
      _return = nil
      return = if true do
        after_ = Temper.Std.afterSubstring(sourceText, i, "null")
        if after_ >= 0 do
          return = after_
          TemperCore.call(out, :nullValue, [])
          return
        else
          Temper.Std.expectedTokenError(sourceText, i, out, "`null`")
          throw({:temper_return, :ex_return_0, TemperCore.String.none()})
        end
      end
      return
    catch
      {:temper_return, :ex_return_0, ex_value_2} ->
        ex_value_2
    end
  end
  def parseJsonNumber(sourceText, i, out) do
    try do
      return = nil
      {_i, return} = try do
        isNegative = false
        startOfNumber = i
        _t1 = nil
        t1 = if TemperCore.String.has_index(sourceText, i) do
          t1 = TemperCore.String.get(sourceText, i) == 45
          t1
        else
          t1 = false
          t1
        end
        {i, isNegative} = if t1 do
          isNegative = true
          i = TemperCore.String.next(sourceText, i)
          {i, isNegative}
        else
          {i, isNegative}
        end
        _digit0 = nil
        digit0 = if TemperCore.String.has_index(sourceText, i) do
          digit0 = TemperCore.String.get(sourceText, i)
          digit0
        else
          digit0 = -1
          digit0
        end
        _t2 = nil
        t2 = if digit0 < 48 do
          t2 = true
          t2
        else
          t2 = 57 < digit0
          t2
        end
        if t2 do
          _error = nil
          _t8 = nil
          t8 = if not isNegative do
            t8 = digit0 != 46
            t8
          else
            t8 = false
            t8
          end
          error = if t8 do
            error = "JSON value"
            error
          else
            error = "digit"
            error
          end
          Temper.Std.expectedTokenError(sourceText, i, out, error)
          return = TemperCore.String.none()
          {i, return}
        else
          i = TemperCore.String.next(sourceText, i)
          nDigits = 1
          tentativeFloat64 = TemperCore.int_to_float(TemperCore.int32(digit0 - 48))
          tentativeInt64 = TemperCore.int32(digit0 - 48)
          overflowInt64 = false
          {i, nDigits, overflowInt64, tentativeFloat64, tentativeInt64} = if 48 != digit0 do
            ex_loop_2 = fn ex_loop_2, i, nDigits, overflowInt64, tentativeFloat64, tentativeInt64 ->
              if TemperCore.String.has_index(sourceText, i) do
                possibleDigit1 = TemperCore.String.get(sourceText, i)
                _t11 = nil
                t11 = if 48 <= possibleDigit1 do
                  t11 = possibleDigit1 <= 57
                  t11
                else
                  t11 = false
                  t11
                end
                if t11 do
                  i = TemperCore.String.next(sourceText, i)
                  nDigits = TemperCore.int32(nDigits + 1)
                  nextDigit = TemperCore.int32(possibleDigit1 - 48)
                  tentativeFloat64 = TemperCore.Float.add(TemperCore.Float.mul(tentativeFloat64, 10.0), TemperCore.int_to_float(nextDigit))
                  oldInt64 = tentativeInt64
                  tentativeInt64 = TemperCore.int64(TemperCore.int64(tentativeInt64 * 10) + nextDigit)
                  if tentativeInt64 < oldInt64 do
                    _t14 = nil
                    t14 = if TemperCore.int64(-9223372036854775808 - oldInt64) == TemperCore.int64(-nextDigit) do
                      if isNegative do
                        t14 = oldInt64 > 0
                        t14
                      else
                        t14 = false
                        t14
                      end
                    else
                      t14 = false
                      t14
                    end
                    if not t14 do
                      overflowInt64 = true
                      ex_loop_2.(ex_loop_2, i, nDigits, overflowInt64, tentativeFloat64, tentativeInt64)
                    else
                      ex_loop_2.(ex_loop_2, i, nDigits, overflowInt64, tentativeFloat64, tentativeInt64)
                    end
                  else
                    ex_loop_2.(ex_loop_2, i, nDigits, overflowInt64, tentativeFloat64, tentativeInt64)
                  end
                else
                  {i, nDigits, overflowInt64, tentativeFloat64, tentativeInt64}
                end
              else
                {i, nDigits, overflowInt64, tentativeFloat64, tentativeInt64}
              end
            end
            {i, nDigits, overflowInt64, tentativeFloat64, tentativeInt64} = ex_loop_2.(ex_loop_2, i, nDigits, overflowInt64, tentativeFloat64, tentativeInt64)
            {i, nDigits, overflowInt64, tentativeFloat64, tentativeInt64}
          else
            {i, nDigits, overflowInt64, tentativeFloat64, tentativeInt64}
          end
          nDigitsAfterPoint = 0
          _t3 = nil
          t3 = if TemperCore.String.has_index(sourceText, i) do
            t3 = 46 == TemperCore.String.get(sourceText, i)
            t3
          else
            t3 = false
            t3
          end
          {i, _nDigits, nDigitsAfterPoint, return, _tentativeFloat64} = if t3 do
            i = TemperCore.String.next(sourceText, i)
            afterPoint = i
            ex_loop_4 = fn ex_loop_4, i, nDigits, nDigitsAfterPoint, tentativeFloat64 ->
              if TemperCore.String.has_index(sourceText, i) do
                possibleDigit2 = TemperCore.String.get(sourceText, i)
                _t12 = nil
                t12 = if 48 <= possibleDigit2 do
                  t12 = possibleDigit2 <= 57
                  t12
                else
                  t12 = false
                  t12
                end
                if t12 do
                  i = TemperCore.String.next(sourceText, i)
                  nDigits = TemperCore.int32(nDigits + 1)
                  nDigitsAfterPoint = TemperCore.int32(nDigitsAfterPoint + 1)
                  tentativeFloat64 = TemperCore.Float.add(TemperCore.Float.mul(tentativeFloat64, 10.0), TemperCore.int_to_float(TemperCore.int32(possibleDigit2 - 48)))
                  ex_loop_4.(ex_loop_4, i, nDigits, nDigitsAfterPoint, tentativeFloat64)
                else
                  {i, nDigits, nDigitsAfterPoint, tentativeFloat64}
                end
              else
                {i, nDigits, nDigitsAfterPoint, tentativeFloat64}
              end
            end
            {i, nDigits, nDigitsAfterPoint, tentativeFloat64} = ex_loop_4.(ex_loop_4, i, nDigits, nDigitsAfterPoint, tentativeFloat64)
            if i == afterPoint do
              Temper.Std.expectedTokenError(sourceText, i, out, "digit")
              return = TemperCore.String.none()
              throw({:temper_break, :ex_block_1, {i, return}})
            else
              {i, nDigits, nDigitsAfterPoint, return, tentativeFloat64}
            end
          else
            {i, nDigits, nDigitsAfterPoint, return, tentativeFloat64}
          end
          nExponentDigits = 0
          _t4 = nil
          t4 = if TemperCore.String.has_index(sourceText, i) do
            t4 = 101 == TemperCore.int32(Bitwise.bor(TemperCore.String.get(sourceText, i), 32))
            t4
          else
            t4 = false
            t4
          end
          {i, nExponentDigits, _return} = if t4 do
            i = TemperCore.String.next(sourceText, i)
            if not TemperCore.String.has_index(sourceText, i) do
              Temper.Std.expectedTokenError(sourceText, i, out, "sign or digit")
              return = TemperCore.String.none()
              throw({:temper_break, :ex_block_1, {i, return}})
            else
              afterE = TemperCore.String.get(sourceText, i)
              _t9 = nil
              t9 = if afterE == 43 do
                t9 = true
                t9
              else
                t9 = afterE == 45
                t9
              end
              i = if t9 do
                i = TemperCore.String.next(sourceText, i)
                i
              else
                i
              end
              ex_loop_6 = fn ex_loop_6, i, nExponentDigits ->
                if TemperCore.String.has_index(sourceText, i) do
                  possibleDigit3 = TemperCore.String.get(sourceText, i)
                  _t13 = nil
                  t13 = if 48 <= possibleDigit3 do
                    t13 = possibleDigit3 <= 57
                    t13
                  else
                    t13 = false
                    t13
                  end
                  if t13 do
                    i = TemperCore.String.next(sourceText, i)
                    nExponentDigits = TemperCore.int32(nExponentDigits + 1)
                    ex_loop_6.(ex_loop_6, i, nExponentDigits)
                  else
                    {i, nExponentDigits}
                  end
                else
                  {i, nExponentDigits}
                end
              end
              {i, nExponentDigits} = ex_loop_6.(ex_loop_6, i, nExponentDigits)
              if nExponentDigits == 0 do
                Temper.Std.expectedTokenError(sourceText, i, out, "exponent digit")
                return = TemperCore.String.none()
                throw({:temper_break, :ex_block_1, {i, return}})
              else
                {i, nExponentDigits, return}
              end
            end
          else
            {i, nExponentDigits, return}
          end
          _afterExponent = i
          _t5 = nil
          t5 = if nExponentDigits == 0 do
            if nDigitsAfterPoint == 0 do
              t5 = not overflowInt64
              t5
            else
              t5 = false
              t5
            end
          else
            t5 = false
            t5
          end
          if t5 do
            _value = nil
            value = if isNegative do
              value = TemperCore.int64(-tentativeInt64)
              value
            else
              value = tentativeInt64
              value
            end
            _t10 = nil
            t10 = if -2147483648 <= value do
              t10 = value <= 2147483647
              t10
            else
              t10 = false
              t10
            end
            if t10 do
              TemperCore.call(out, :int32Value, [TemperCore.int32(value)])
              nil
            else
              TemperCore.call(out, :int64Value, [value])
              nil
            end
            return = i
            {i, return}
          else
            numericTokenString = TemperCore.String.slice(sourceText, startOfNumber, i)
            doubleValue = :nan
            _t6 = nil
            t6 = if nExponentDigits != 0 do
              t6 = true
              t6
            else
              t6 = nDigitsAfterPoint != 0
              t6
            end
            doubleValue = if t6 do
              doubleValue = try do
                doubleValue = TemperCore.String.to_float64(numericTokenString)
                doubleValue
              rescue
                _ in TemperCore.Bubble ->
                  doubleValue
              end
              doubleValue
            else
              doubleValue
            end
            _t7 = nil
            t7 = if TemperCore.Float.ne(doubleValue, :neg_infinity) do
              if TemperCore.Float.ne(doubleValue, :infinity) do
                t7 = TemperCore.Float.ne(doubleValue, :nan)
                t7
              else
                t7 = false
                t7
              end
            else
              t7 = false
              t7
            end
            if t7 do
              TemperCore.call(out, :float64Value, [doubleValue])
              nil
            else
              TemperCore.call(out, :numericTokenValue, [numericTokenString])
              nil
            end
            throw({:temper_return, :ex_return_0, i})
          end
        end
      catch
        {:temper_break, :ex_block_1, ex_vars_8} ->
          ex_vars_8
      end
      return
    catch
      {:temper_return, :ex_return_0, ex_value_9} ->
        ex_value_9
    end
  end
  def parseJsonToProducer(sourceText, out) do
    Temper.Std.__temper_init__()
    TemperCore.Heap.entry(fn ->
      i = TemperCore.String.begin()
      afterValue = Temper.Std.parseJsonValue(sourceText, i, out)
      _i = if afterValue >= 0 do
        t1 = afterValue
        i = Temper.Std.skipJsonSpaces(sourceText, t1)
        _t2 = nil
        t2 = if TemperCore.String.has_index(sourceText, i) do
          t2 = not (TemperCore.call(out, :get_parseErrorReceiver, []) === nil)
          t2
        else
          t2 = false
          t2
        end
        if t2 do
          Temper.Std.storeJsonError(out, "Extraneous JSON `" <> TemperCore.String.slice(sourceText, i, TemperCore.String.end_of(sourceText)) <> "`")
          i
        else
          i
        end
      else
        i
      end
      nil
    end)
  end
  def parseJson(sourceText) do
    Temper.Std.__temper_init__()
    TemperCore.Heap.entry(fn ->
      p = Temper.Std.JsonSyntaxTreeProducer.new()
      Temper.Std.parseJsonToProducer(sourceText, p)
      Temper.Std.JsonSyntaxTreeProducer.toJsonSyntaxTree(p)
    end)
  end
  def booleanJsonAdapter() do
    Temper.Std.__temper_init__()
    TemperCore.Heap.entry(fn ->
      Temper.Std.BooleanJsonAdapter.new()
    end)
  end
  def float64JsonAdapter() do
    Temper.Std.__temper_init__()
    TemperCore.Heap.entry(fn ->
      Temper.Std.Float64JsonAdapter.new()
    end)
  end
  def int32JsonAdapter() do
    Temper.Std.__temper_init__()
    TemperCore.Heap.entry(fn ->
      Temper.Std.Int32JsonAdapter.new()
    end)
  end
  def int64JsonAdapter() do
    Temper.Std.__temper_init__()
    TemperCore.Heap.entry(fn ->
      Temper.Std.Int64JsonAdapter.new()
    end)
  end
  def stringJsonAdapter() do
    Temper.Std.__temper_init__()
    TemperCore.Heap.entry(fn ->
      Temper.Std.StringJsonAdapter.new()
    end)
  end
  def listJsonAdapter(adapterForT) do
    Temper.Std.__temper_init__()
    TemperCore.Heap.entry(fn ->
      Temper.Std.ListJsonAdapter.new(adapterForT)
    end)
  end
  def isLeapYear(year) do
    if rem(year, 4) == 0 do
      if rem(year, 100) != 0 do
        true
      else
        rem(year, 400) == 0
      end
    else
      false
    end
  end
  def padTo(minWidth, num, sb) do
    decimal = TemperCore.int_to_string(num, 10)
    decimalIndex = TemperCore.String.begin()
    decimalEnd = TemperCore.String.end_of(decimal)
    _t = nil
    t = if decimalIndex < decimalEnd do
      t = TemperCore.String.get(decimal, decimalIndex) == 45
      t
    else
      t = false
      t
    end
    decimalIndex = if t do
      TemperCore.StringBuilder.append(sb, "-")
      decimalIndex = TemperCore.String.next(decimal, decimalIndex)
      decimalIndex
    else
      decimalIndex
    end
    nNeeded = TemperCore.int32(minWidth - TemperCore.String.count_between(decimal, decimalIndex, decimalEnd))
    ex_loop_1 = fn ex_loop_1, nNeeded ->
      if nNeeded > 0 do
        TemperCore.StringBuilder.append(sb, "0")
        nNeeded = TemperCore.int32(nNeeded - 1)
        ex_loop_1.(ex_loop_1, nNeeded)
      else
        nNeeded
      end
    end
    _nNeeded = ex_loop_1.(ex_loop_1, nNeeded)
    TemperCore.StringBuilder.append_between(sb, decimal, decimalIndex, decimalEnd)
    nil
  end
  def processTestCases(testCases) do
    Temper.Std.__temper_init__()
    TemperCore.Heap.entry(fn ->
      fn_ = fn testCase ->
        key = TemperCore.Pair.get_key(testCase)
        fun = TemperCore.Pair.get_value(testCase)
        test = Temper.Std.Test.new()
        hadBubble = false
        hadBubble = try do
          fun.(test)
          hadBubble
        rescue
          _ in TemperCore.Bubble ->
            hadBubble = true
            hadBubble
        end
        messages = TemperCore.Test.messages(test)
        _failures = nil
        _t1 = nil
        t1 = if TemperCore.Test.passing(test) do
          t1 = not hadBubble
          t1
        else
          t1 = false
          t1
        end
        failures = if t1 do
          failures = %TemperCore.Vec{t: {}}
          failures
        else
          _t2 = nil
          t2 = if hadBubble do
            t2 = not TemperCore.Test.failed_on_assert(test)
            t2
          else
            t2 = false
            t2
          end
          if t2 do
            allMessages = TemperCore.List.to_builder(messages)
            TemperCore.List.add(allMessages, "Bubble")
            failures = TemperCore.List.to_list(allMessages)
            failures
          else
            failures = messages
            failures
          end
        end
        TemperCore.Pair.new(key, failures)
      end
      TemperCore.List.map(testCases, fn_)
    end)
  end
  def escapeXml(s) do
    sb = TemperCore.StringBuilder.new()
    end_ = TemperCore.String.end_of(s)
    emitted = TemperCore.String.begin()
    i = TemperCore.String.begin()
    ex_loop_1 = fn ex_loop_1, emitted, i ->
      if i < end_ do
        emitted = try do
          c = TemperCore.String.get(s, i)
          _esc = nil
          esc = cond do
            c == 38 ->
              esc = "&amp;"
              esc
            c == 60 ->
              esc = "&lt;"
              esc
            c == 62 ->
              esc = "&gt;"
              esc
            c == 39 ->
              esc = "&\#39;"
              esc
            c == 34 ->
              esc = "&\#34;"
              esc
            true ->
              _t1 = nil
              t1 = cond do
                c == 10 ->
                  t1 = true
                  t1
                c == 13 ->
                  t1 = true
                  t1
                true ->
                  t1 = c == 9
                  t1
              end
              if t1 do
                throw({:temper_break, :ex_block_3, emitted})
              else
                _t2 = nil
                t2 = cond do
                  c < 32 ->
                    t2 = true
                    t2
                  c == 65534 ->
                    t2 = true
                    t2
                  true ->
                    t2 = c == 65535
                    t2
                end
                if t2 do
                  esc = "[0x" <> TemperCore.int_to_string(c, 16) <> "]"
                  esc
                else
                  throw({:temper_break, :ex_block_3, emitted})
                end
              end
          end
          TemperCore.StringBuilder.append_between(sb, s, emitted, i)
          TemperCore.StringBuilder.append(sb, esc)
          emitted = TemperCore.String.next(s, i)
          emitted
        catch
          {:temper_break, :ex_block_3, ex_vars_4} ->
            ex_vars_4
        end
        i = TemperCore.String.next(s, i)
        ex_loop_1.(ex_loop_1, emitted, i)
      else
        {emitted, i}
      end
    end
    {emitted, _i} = ex_loop_1.(ex_loop_1, emitted, i)
    if emitted == TemperCore.String.begin() do
      s
    else
      TemperCore.StringBuilder.append_between(sb, s, emitted, end_)
      TemperCore.StringBuilder.to_string(sb)
    end
  end
  def reportTestResults(testResults, writeLine) do
    Temper.Std.__temper_init__()
    TemperCore.Heap.entry(fn ->
      writeLine.("<testsuites>")
      total = TemperCore.int_to_string(TemperCore.List.length(testResults))
      fn_1 = fn fails1, testResult1 ->
        _t = nil
        t = if TemperCore.List.is_empty(TemperCore.Pair.get_value(testResult1)) do
          t = 0
          t
        else
          t = 1
          t
        end
        TemperCore.int32(fails1 + t)
      end
      fails2 = TemperCore.int_to_string(TemperCore.List.reduce_from(testResults, 0, fn_1))
      totals = "tests='" <> total <> "' failures='" <> fails2 <> "'"
      writeLine.("  <testsuite name='suite' " <> totals <> " time='0.0'>")
      i = 0
      ex_loop_2 = fn ex_loop_2, i ->
        if i < TemperCore.List.length(testResults) do
          testResult2 = TemperCore.List.get(testResults, i)
          failureMessages = TemperCore.Pair.get_value(testResult2)
          name = Temper.Std.escapeXml(TemperCore.Pair.get_key(testResult2))
          basics = "name='" <> name <> "' classname='" <> name <> "' time='0.0'"
          if TemperCore.List.is_empty(failureMessages) do
            writeLine.("    <testcase " <> basics <> " />")
            nil
          else
            writeLine.("    <testcase " <> basics <> ">")
            fn_2 = fn it ->
              it
            end
            message = Temper.Std.escapeXml(TemperCore.List.join(failureMessages, ", ", fn_2))
            writeLine.("      <failure message='" <> message <> "' />")
            writeLine.("    </testcase>")
            nil
          end
          i = TemperCore.int32(i + 1)
          ex_loop_2.(ex_loop_2, i)
        else
          i
        end
      end
      _i = ex_loop_2.(ex_loop_2, i)
      writeLine.("  </testsuite>")
      writeLine.("</testsuites>")
      nil
    end)
  end
  def runTestCases(testCases) do
    Temper.Std.__temper_init__()
    TemperCore.Heap.entry(fn ->
      report = TemperCore.StringBuilder.new()
      fn_ = fn line ->
        TemperCore.StringBuilder.append(report, line)
        TemperCore.StringBuilder.append(report, "\n")
        nil
      end
      Temper.Std.reportTestResults(TemperCore.Test.process(testCases), fn_)
      TemperCore.StringBuilder.to_string(report)
    end)
  end
  def runTest(testFun) do
    Temper.Std.__temper_init__()
    TemperCore.Heap.entry(fn ->
      test = Temper.Std.Test.new()
      try do
        testFun.(test)
        nil
      rescue
        _ in TemperCore.Bubble ->
          fn_ = fn ->
            "bubble during test running"
          end
          TemperCore.Test.assert(test, false, fn_)
          nil
      end
      Temper.Std.Test.softFailToHard(test)
      nil
    end)
  end
  def buildEscapeNeeds() do
    escapeNeeds = TemperCore.List.builder()
    code = 0
    ex_loop_1 = fn ex_loop_1, code ->
      if code <= 127 do
        _t1 = nil
        _t2 = nil
        t2 = cond do
          code == TemperCore.Global.get(:"Temper.Std.Codes.dash") ->
            t2 = true
            t2
          code == TemperCore.Global.get(:"Temper.Std.Codes.space") ->
            t2 = true
            t2
          code == TemperCore.Global.get(:"Temper.Std.Codes.underscore") ->
            t2 = true
            t2
          true ->
            _t4 = nil
            t4 = if TemperCore.Global.get(:"Temper.Std.Codes.digit0") <= code do
              t4 = code <= TemperCore.Global.get(:"Temper.Std.Codes.digit9")
              t4
            else
              t4 = false
              t4
            end
            if t4 do
              t2 = true
              t2
            else
              _t5 = nil
              t5 = if TemperCore.Global.get(:"Temper.Std.Codes.upperA") <= code do
                t5 = code <= TemperCore.Global.get(:"Temper.Std.Codes.upperZ")
                t5
              else
                t5 = false
                t5
              end
              cond do
                t5 ->
                  t2 = true
                  t2
                TemperCore.Global.get(:"Temper.Std.Codes.lowerA") <= code ->
                  t2 = code <= TemperCore.Global.get(:"Temper.Std.Codes.lowerZ")
                  t2
                true ->
                  t2 = false
                  t2
              end
            end
        end
        t1 = if t2 do
          t1 = 0
          t1
        else
          _t3 = nil
          t3 = cond do
            code == TemperCore.Global.get(:"Temper.Std.Codes.ampersand") ->
              t3 = true
              t3
            code == TemperCore.Global.get(:"Temper.Std.Codes.backslash") ->
              t3 = true
              t3
            code == TemperCore.Global.get(:"Temper.Std.Codes.caret") ->
              t3 = true
              t3
            code == TemperCore.Global.get(:"Temper.Std.Codes.curlyLeft") ->
              t3 = true
              t3
            code == TemperCore.Global.get(:"Temper.Std.Codes.curlyRight") ->
              t3 = true
              t3
            code == TemperCore.Global.get(:"Temper.Std.Codes.dot") ->
              t3 = true
              t3
            code == TemperCore.Global.get(:"Temper.Std.Codes.peso") ->
              t3 = true
              t3
            code == TemperCore.Global.get(:"Temper.Std.Codes.pipe") ->
              t3 = true
              t3
            code == TemperCore.Global.get(:"Temper.Std.Codes.plus") ->
              t3 = true
              t3
            code == TemperCore.Global.get(:"Temper.Std.Codes.question") ->
              t3 = true
              t3
            code == TemperCore.Global.get(:"Temper.Std.Codes.roundLeft") ->
              t3 = true
              t3
            code == TemperCore.Global.get(:"Temper.Std.Codes.roundRight") ->
              t3 = true
              t3
            code == TemperCore.Global.get(:"Temper.Std.Codes.slash") ->
              t3 = true
              t3
            code == TemperCore.Global.get(:"Temper.Std.Codes.squareLeft") ->
              t3 = true
              t3
            code == TemperCore.Global.get(:"Temper.Std.Codes.squareRight") ->
              t3 = true
              t3
            code == TemperCore.Global.get(:"Temper.Std.Codes.star") ->
              t3 = true
              t3
            true ->
              t3 = code == TemperCore.Global.get(:"Temper.Std.Codes.tilde")
              t3
          end
          if t3 do
            t1 = 2
            t1
          else
            t1 = 1
            t1
          end
        end
        TemperCore.List.add(escapeNeeds, t1)
        code = TemperCore.int32(code + 1)
        ex_loop_1.(ex_loop_1, code)
      else
        code
      end
    end
    _code = ex_loop_1.(ex_loop_1, code)
    TemperCore.List.to_list(escapeNeeds)
  end
  def entire(item) do
    Temper.Std.__temper_init__()
    TemperCore.Heap.entry(fn ->
      Temper.Std.Sequence.new(%TemperCore.Vec{t: {TemperCore.Global.get(:"Temper.Std.v_Begin"), item, TemperCore.Global.get(:"Temper.Std.v_End")}})
    end)
  end
  def oneOrMore(item, reluctant1) do
    Temper.Std.__temper_init__()
    TemperCore.Heap.entry(fn ->
      _reluctant2 = nil
      reluctant2 = if reluctant1 === nil do
        reluctant2 = false
        reluctant2
      else
        reluctant2 = reluctant1
        reluctant2
      end
      Temper.Std.Repeat.new(item, 1, nil, reluctant2)
    end)
  end
  def optional(item, reluctant1) do
    Temper.Std.__temper_init__()
    TemperCore.Heap.entry(fn ->
      _reluctant2 = nil
      reluctant2 = if reluctant1 === nil do
        reluctant2 = false
        reluctant2
      else
        reluctant2 = reluctant1
        reluctant2
      end
      Temper.Std.Repeat.new(item, 0, 1, reluctant2)
    end)
  end
  def __temper_init__() do
    TemperCore.init_once(:"Temper.Std", fn ->
      TemperCore.Global.put(:"Temper.Std.NullInterchangeContext.instance", Temper.Std.NullInterchangeContext.new())
      TemperCore.Global.put(:"Temper.Std.hexDigits", %TemperCore.Vec{t: {"0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"}})
      TemperCore.Global.put(:"Temper.Std.daysInMonth", %TemperCore.Vec{t: {0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}})
      TemperCore.Global.put(:"Temper.Std.dayOfWeekLookupTableLeapy", %TemperCore.Vec{t: {0, 0, 3, 4, 0, 2, 5, 0, 3, 6, 1, 4, 6}})
      TemperCore.Global.put(:"Temper.Std.dayOfWeekLookupTableNotLeapy", %TemperCore.Vec{t: {0, 0, 3, 3, 6, 1, 4, 6, 2, 5, 0, 3, 5}})
      TemperCore.Global.put(:"Temper.Std.Codes.ampersand", 38)
      TemperCore.Global.put(:"Temper.Std.Codes.backslash", 92)
      TemperCore.Global.put(:"Temper.Std.Codes.caret", 94)
      TemperCore.Global.put(:"Temper.Std.Codes.carriageReturn", 13)
      TemperCore.Global.put(:"Temper.Std.Codes.curlyLeft", 123)
      TemperCore.Global.put(:"Temper.Std.Codes.curlyRight", 125)
      TemperCore.Global.put(:"Temper.Std.Codes.dash", 45)
      TemperCore.Global.put(:"Temper.Std.Codes.dot", 46)
      TemperCore.Global.put(:"Temper.Std.Codes.highControlMin", 127)
      TemperCore.Global.put(:"Temper.Std.Codes.highControlMax", 159)
      TemperCore.Global.put(:"Temper.Std.Codes.digit0", 48)
      TemperCore.Global.put(:"Temper.Std.Codes.digit9", 57)
      TemperCore.Global.put(:"Temper.Std.Codes.lowerA", 97)
      TemperCore.Global.put(:"Temper.Std.Codes.lowerZ", 122)
      TemperCore.Global.put(:"Temper.Std.Codes.newline", 10)
      TemperCore.Global.put(:"Temper.Std.Codes.peso", 36)
      TemperCore.Global.put(:"Temper.Std.Codes.pipe", 124)
      TemperCore.Global.put(:"Temper.Std.Codes.plus", 43)
      TemperCore.Global.put(:"Temper.Std.Codes.question", 63)
      TemperCore.Global.put(:"Temper.Std.Codes.roundLeft", 40)
      TemperCore.Global.put(:"Temper.Std.Codes.roundRight", 41)
      TemperCore.Global.put(:"Temper.Std.Codes.slash", 47)
      TemperCore.Global.put(:"Temper.Std.Codes.squareLeft", 91)
      TemperCore.Global.put(:"Temper.Std.Codes.squareRight", 93)
      TemperCore.Global.put(:"Temper.Std.Codes.star", 42)
      TemperCore.Global.put(:"Temper.Std.Codes.tab", 9)
      TemperCore.Global.put(:"Temper.Std.Codes.tilde", 42)
      TemperCore.Global.put(:"Temper.Std.Codes.upperA", 65)
      TemperCore.Global.put(:"Temper.Std.Codes.upperZ", 90)
      TemperCore.Global.put(:"Temper.Std.Codes.space", 32)
      TemperCore.Global.put(:"Temper.Std.Codes.surrogateMin", 55296)
      TemperCore.Global.put(:"Temper.Std.Codes.surrogateMax", 57343)
      TemperCore.Global.put(:"Temper.Std.Codes.supplementalMin", 65536)
      TemperCore.Global.put(:"Temper.Std.Codes.uint16Max", 65535)
      TemperCore.Global.put(:"Temper.Std.Codes.underscore", 95)
      TemperCore.Global.put(:"Temper.Std.return", Temper.Std.Begin.new())
      TemperCore.Global.put(:"Temper.Std.v_Begin", TemperCore.Global.get(:"Temper.Std.return"))
      TemperCore.Global.put(:"Temper.Std.return__2", Temper.Std.Dot.new())
      TemperCore.Global.put(:"Temper.Std.v_Dot", TemperCore.Global.get(:"Temper.Std.return__2"))
      TemperCore.Global.put(:"Temper.Std.return__3", Temper.Std.End.new())
      TemperCore.Global.put(:"Temper.Std.v_End", TemperCore.Global.get(:"Temper.Std.return__3"))
      TemperCore.Global.put(:"Temper.Std.return__4", Temper.Std.WordBoundary.new())
      TemperCore.Global.put(:"Temper.Std.v_WordBoundary", TemperCore.Global.get(:"Temper.Std.return__4"))
      TemperCore.Global.put(:"Temper.Std.return__5", Temper.Std.Digit.new())
      TemperCore.Global.put(:"Temper.Std.v_Digit", TemperCore.Global.get(:"Temper.Std.return__5"))
      TemperCore.Global.put(:"Temper.Std.return__6", Temper.Std.Space.new())
      TemperCore.Global.put(:"Temper.Std.v_Space", TemperCore.Global.get(:"Temper.Std.return__6"))
      TemperCore.Global.put(:"Temper.Std.return__7", Temper.Std.Word.new())
      TemperCore.Global.put(:"Temper.Std.v_Word", TemperCore.Global.get(:"Temper.Std.return__7"))
      TemperCore.Global.put(:"Temper.Std.escapeNeeds", Temper.Std.buildEscapeNeeds())
      TemperCore.Global.put(:"Temper.Std.regexRefs", Temper.Std.RegexRefs.new(nil, nil, nil, nil))
      nil
    end)
  end
  def main() do
    Temper.Std.__temper_init__()
    TemperCore.Async.drain()
  end
end
