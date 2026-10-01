defmodule Temper.Std.Tests do
  def sendRequest__16(_url, _method, _bodyContent, _bodyMimeType) do
    raise(TemperCore.Panic)
  end
  def __temper_init__() do
    TemperCore.init_once(:"Temper.Std.Tests", fn ->
      Temper.Std.__temper_init__()
      TemperCore.Global.put(:"Temper.Std.v_JSON_STATE_OPEN_OBJECT__379", 0)
      TemperCore.Global.put(:"Temper.Std.v_JSON_STATE_AFTER_KEY__380", 1)
      TemperCore.Global.put(:"Temper.Std.v_JSON_STATE_AFTER_PROPERTY__381", 2)
      TemperCore.Global.put(:"Temper.Std.v_JSON_STATE_OPEN_ARRAY__382", 3)
      TemperCore.Global.put(:"Temper.Std.v_JSON_STATE_AFTER_ELEMENT__383", 4)
      TemperCore.Global.put(:"Temper.Std.v_JSON_STATE_NO_VALUE__384", 5)
      TemperCore.Global.put(:"Temper.Std.v_JSON_STATE_ONE_VALUE__385", 6)
      TemperCore.Global.put(:"Temper.Std.minInt64__387", -9223372036854775808)
      TemperCore.Global.put(:"Temper.Std.needsNoEscape__166", 0)
      TemperCore.Global.put(:"Temper.Std.needsSimpleEscape__168", 2)
      TemperCore.Global.put(:"Temper.Std.needsNumericEscape__167", 1)
      nil
    end)
  end
end
