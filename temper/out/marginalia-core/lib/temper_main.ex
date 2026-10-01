defmodule Temper.MarginaliaCore.Row do
  defstruct [:kind, :left, :right]
  def __temper_supertypes__() do
    [Temper.MarginaliaCore.Row]
  end
  def new(kind, left, right) do
    Temper.MarginaliaCore.__temper_init__()
    this = %Temper.MarginaliaCore.Row{}
    this = %{this | :kind => kind}
    this = %{this | :left => left}
    this = %{this | :right => right}
    this
  end
  def get_kind(this) do
    this.kind
  end
  def get_left(this) do
    this.left
  end
  def get_right(this) do
    this.right
  end
end
defmodule Temper.MarginaliaCore.Part do
  defstruct [:kind, :text]
  def __temper_supertypes__() do
    [Temper.MarginaliaCore.Part]
  end
  def new(kind, text) do
    Temper.MarginaliaCore.__temper_init__()
    this = %Temper.MarginaliaCore.Part{}
    this = %{this | :kind => kind}
    this = %{this | :text => text}
    this
  end
  def get_kind(this) do
    this.kind
  end
  def get_text(this) do
    this.text
  end
end
defmodule Temper.MarginaliaCore.Edit do
  defstruct [:kind, :word, :before]
  def __temper_supertypes__() do
    [Temper.MarginaliaCore.Edit]
  end
  def new(kind, word, before) do
    this = %Temper.MarginaliaCore.Edit{}
    this = %{this | :kind => kind}
    this = %{this | :word => word}
    this = %{this | :before => before}
    this
  end
  def get_kind(this) do
    this.kind
  end
  def get_word(this) do
    this.word
  end
  def get_before(this) do
    this.before
  end
end
defmodule Temper.MarginaliaCore.Path do
  defstruct [:y, :i, :j, :edits]
  def __temper_supertypes__() do
    [Temper.MarginaliaCore.Path]
  end
  def new(y, i, j, edits) do
    this = %Temper.MarginaliaCore.Path{}
    this = %{this | :y => y}
    this = %{this | :i => i}
    this = %{this | :j => j}
    this = %{this | :edits => edits}
    this
  end
  def get_y(this) do
    this.y
  end
  def get_i(this) do
    this.i
  end
  def get_j(this) do
    this.j
  end
  def get_edits(this) do
    this.edits
  end
end
defmodule Temper.MarginaliaCore.Chunk do
  def __temper_supertypes__() do
    [Temper.MarginaliaCore.Chunk]
  end
  def new(kind, words) do
    this = TemperCore.Heap.new(Temper.MarginaliaCore.Chunk, %{:kind => nil, :words => nil})
    TemperCore.Heap.put(this, :kind, kind)
    TemperCore.Heap.put(this, :words, words)
    this
  end
  def get_kind(this) do
    TemperCore.Heap.get(this, :kind)
  end
  def get_words(this) do
    TemperCore.Heap.get(this, :words)
  end
end
defmodule Temper.MarginaliaCore do
  def reflow(text) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      try do
        _return = nil
        return = if true do
          if TemperCore.String.is_empty(text) do
            return = ""
            return
          else
            fn_ = fn b ->
              Temper.MarginaliaCore.reflowBlock(b)
            end
            throw({:temper_return, :ex_return_4, Temper.MarginaliaCore.joinWith(TemperCore.List.map(Temper.MarginaliaCore.blocks(text), fn_), "\n\n")})
          end
        end
        return
      catch
        {:temper_return, :ex_return_4, ex_value_7} ->
          ex_value_7
      end
    end)
  end
  def startsWith(s, prefix) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      try do
        return = nil
        return = try do
          i = TemperCore.String.begin()
          j = TemperCore.String.begin()
          ex_loop_25 = fn ex_loop_25, i, j, return ->
            if TemperCore.String.has_index(prefix, j) do
              _t = nil
              t = if not TemperCore.String.has_index(s, i) do
                t = true
                t
              else
                t = TemperCore.String.get(s, i) != TemperCore.String.get(prefix, j)
                t
              end
              if t do
                return = false
                throw({:temper_break, :ex_block_24, return})
              else
                i = TemperCore.String.next(s, i)
                j = TemperCore.String.next(prefix, j)
                ex_loop_25.(ex_loop_25, i, j, return)
              end
            else
              {i, j, return}
            end
          end
          {_i, _j, _return} = ex_loop_25.(ex_loop_25, i, j, return)
          throw({:temper_return, :ex_return_23, true})
        catch
          {:temper_break, :ex_block_24, ex_vars_27} ->
            ex_vars_27
        end
        return
      catch
        {:temper_return, :ex_return_23, ex_value_28} ->
          ex_value_28
      end
    end)
  end
  def isRegexSpace(cp) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      cond do
        cp == 32 ->
          true
        cp >= 9 ->
          cp <= 13
        true ->
          false
      end
    end)
  end
  def isTrimSpace(cp) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      cond do
        Temper.MarginaliaCore.isRegexSpace(cp) ->
          true
        cp == 133 ->
          true
        cp == 160 ->
          true
        cp == 5760 ->
          true
        true ->
          _t = nil
          t = if cp >= 8192 do
            t = cp <= 8202
            t
          else
            t = false
            t
          end
          cond do
            t ->
              true
            cp == 8232 ->
              true
            cp == 8233 ->
              true
            cp == 8239 ->
              true
            cp == 8287 ->
              true
            true ->
              cp == 12288
          end
      end
    end)
  end
  def leadingEnd(s) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      b = TemperCore.String.begin()
      ex_loop_32 = fn ex_loop_32, b ->
        if true do
          _t = nil
          t = if TemperCore.String.has_index(s, b) do
            t = Temper.MarginaliaCore.isTrimSpace(TemperCore.String.get(s, b))
            t
          else
            t = false
            t
          end
          if not t do
            b
          else
            b = TemperCore.String.next(s, b)
            ex_loop_32.(ex_loop_32, b)
          end
        else
          b
        end
      end
      b = ex_loop_32.(ex_loop_32, b)
      b
    end)
  end
  def trimLeading(s) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      TemperCore.String.slice(s, Temper.MarginaliaCore.leadingEnd(s), TemperCore.String.end_of(s))
    end)
  end
  def joinWith(parts, sep) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      fn_ = fn p ->
        p
      end
      TemperCore.List.join(parts, sep, fn_)
    end)
  end
  def flushBlock__316(current, out) do
    if not TemperCore.List.is_empty(current) do
      TemperCore.List.add(out, Temper.MarginaliaCore.joinWith(TemperCore.List.to_list(current), "\n"))
      TemperCore.List.clear(current)
      nil
    else
      nil
    end
    nil
  end
  def fenceOpener__317(line) do
    try do
      _return = nil
      return = if true do
        i = TemperCore.String.begin()
        ex_loop_40 = fn ex_loop_40, i ->
          if true do
            _t2 = nil
            t2 = if TemperCore.String.has_index(line, i) do
              t2 = Temper.MarginaliaCore.isRegexSpace(TemperCore.String.get(line, i))
              t2
            else
              t2 = false
              t2
            end
            if not t2 do
              i
            else
              i = TemperCore.String.next(line, i)
              ex_loop_40.(ex_loop_40, i)
            end
          else
            i
          end
        end
        i = ex_loop_40.(ex_loop_40, i)
        if not TemperCore.String.has_index(line, i) do
          return = nil
          return
        else
          mark = TemperCore.String.get(line, i)
          _t1 = nil
          t1 = if mark != 96 do
            t1 = mark != 126
            t1
          else
            t1 = false
            t1
          end
          if t1 do
            return = nil
            return
          else
            start = i
            count = 0
            ex_loop_42 = fn ex_loop_42, count, i ->
              if true do
                _t3 = nil
                t3 = if TemperCore.String.has_index(line, i) do
                  t3 = TemperCore.String.get(line, i) == mark
                  t3
                else
                  t3 = false
                  t3
                end
                if not t3 do
                  {count, i}
                else
                  count = TemperCore.int32(count + 1)
                  i = TemperCore.String.next(line, i)
                  ex_loop_42.(ex_loop_42, count, i)
                end
              else
                {count, i}
              end
            end
            {count, i} = ex_loop_42.(ex_loop_42, count, i)
            if count >= 3 do
              throw({:temper_return, :ex_return_38, TemperCore.String.slice(line, start, i)})
            else
              throw({:temper_return, :ex_return_38, nil})
            end
          end
        end
      end
      return
    catch
      {:temper_return, :ex_return_38, ex_value_44} ->
        ex_value_44
    end
  end
  def trim(s) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      b = TemperCore.String.begin()
      ex_loop_46 = fn ex_loop_46, b ->
        if true do
          _t1 = nil
          t1 = if TemperCore.String.has_index(s, b) do
            t1 = Temper.MarginaliaCore.isTrimSpace(TemperCore.String.get(s, b))
            t1
          else
            t1 = false
            t1
          end
          if not t1 do
            b
          else
            b = TemperCore.String.next(s, b)
            ex_loop_46.(ex_loop_46, b)
          end
        else
          b
        end
      end
      b = ex_loop_46.(ex_loop_46, b)
      e = TemperCore.String.end_of(s)
      ex_loop_48 = fn ex_loop_48, e ->
        if true do
          _t2 = nil
          t2 = if e > b do
            t2 = Temper.MarginaliaCore.isTrimSpace(TemperCore.String.get(s, TemperCore.String.prev(s, e)))
            t2
          else
            t2 = false
            t2
          end
          if not t2 do
            e
          else
            e = TemperCore.String.prev(s, e)
            ex_loop_48.(ex_loop_48, e)
          end
        else
          e
        end
      end
      e = ex_loop_48.(ex_loop_48, e)
      TemperCore.String.slice(s, b, e)
    end)
  end
  def trailingStart(s) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      e = TemperCore.String.end_of(s)
      ex_loop_51 = fn ex_loop_51, e ->
        if true do
          _t = nil
          t = if e > TemperCore.String.begin() do
            t = Temper.MarginaliaCore.isTrimSpace(TemperCore.String.get(s, TemperCore.String.prev(s, e)))
            t
          else
            t = false
            t
          end
          if not t do
            e
          else
            e = TemperCore.String.prev(s, e)
            ex_loop_51.(ex_loop_51, e)
          end
        else
          e
        end
      end
      e = ex_loop_51.(ex_loop_51, e)
      e
    end)
  end
  def trimTrailing(s) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      TemperCore.String.slice(s, TemperCore.String.begin(), Temper.MarginaliaCore.trailingStart(s))
    end)
  end
  def blocks(body) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      out = TemperCore.List.builder()
      current = TemperCore.List.builder()
      fence = nil
      lines = TemperCore.String.split(body, "\n")
      k1 = 0
      ex_loop_55 = fn ex_loop_55, fence, k1 ->
        if k1 < TemperCore.List.length(lines) do
          line = TemperCore.List.get(lines, k1)
          open1 = fence
          fence = if not (open1 === nil) do
            open2 = open1
            TemperCore.List.add(current, line)
            if Temper.MarginaliaCore.startsWith(Temper.MarginaliaCore.trimLeading(line), open2) do
              Temper.MarginaliaCore.flushBlock__316(current, out)
              fence = nil
              fence
            else
              fence
            end
          else
            opener1 = Temper.MarginaliaCore.fenceOpener__317(line)
            cond do
              not (opener1 === nil) ->
                opener2 = opener1
                Temper.MarginaliaCore.flushBlock__316(current, out)
                TemperCore.List.add(current, line)
                fence = opener2
                fence
              TemperCore.String.is_empty(Temper.MarginaliaCore.trim(line)) ->
                Temper.MarginaliaCore.flushBlock__316(current, out)
                fence
              true ->
                TemperCore.List.add(current, line)
                fence
            end
          end
          k1 = TemperCore.int32(k1 + 1)
          ex_loop_55.(ex_loop_55, fence, k1)
        else
          {fence, k1}
        end
      end
      {_fence, _k1} = ex_loop_55.(ex_loop_55, fence, k1)
      Temper.MarginaliaCore.flushBlock__316(current, out)
      kept = TemperCore.List.builder()
      all = TemperCore.List.to_list(out)
      k2 = 0
      ex_loop_57 = fn ex_loop_57, k2 ->
        if k2 < TemperCore.List.length(all) do
          block = Temper.MarginaliaCore.trimTrailing(TemperCore.List.get(all, k2))
          if not TemperCore.String.is_empty(Temper.MarginaliaCore.trim(block)) do
            TemperCore.List.add(kept, block)
            nil
          else
            nil
          end
          k2 = TemperCore.int32(k2 + 1)
          ex_loop_57.(ex_loop_57, k2)
        else
          k2
        end
      end
      _k2 = ex_loop_57.(ex_loop_57, k2)
      TemperCore.List.to_list(kept)
    end)
  end
  def flushParagraph__318(piece, out) do
    p = Temper.MarginaliaCore.trim(TemperCore.StringBuilder.to_string(piece))
    if not TemperCore.String.is_empty(p) do
      TemperCore.List.add(out, p)
      nil
    else
      nil
    end
    TemperCore.StringBuilder.clear(piece)
    nil
  end
  def paragraphs(text) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      out = TemperCore.List.builder()
      piece = TemperCore.StringBuilder.new()
      newlines = 0
      i = TemperCore.String.begin()
      ex_loop_61 = fn ex_loop_61, i, newlines ->
        if TemperCore.String.has_index(text, i) do
          cp = TemperCore.String.get(text, i)
          after_ = TemperCore.String.next(text, i)
          _t = nil
          t = if cp == 13 do
            if TemperCore.String.has_index(text, after_) do
              t = TemperCore.String.get(text, after_) == 10
              t
            else
              t = false
              t
            end
          else
            t = false
            t
          end
          {cp, i} = if t do
            i = after_
            cp = 10
            {cp, i}
          else
            {cp, i}
          end
          newlines = if cp == 10 do
            newlines = TemperCore.int32(newlines + 1)
            newlines
          else
            cond do
              newlines >= 2 ->
                Temper.MarginaliaCore.flushParagraph__318(piece, out)
                nil
              newlines == 1 ->
                TemperCore.StringBuilder.append(piece, "\n")
                nil
              true ->
                nil
            end
            newlines = 0
            try do
              TemperCore.StringBuilder.append_code_point(piece, cp)
              nil
            rescue
              _ in TemperCore.Bubble ->
                raise(TemperCore.Bubble)
            end
            newlines
          end
          i = TemperCore.String.next(text, i)
          ex_loop_61.(ex_loop_61, i, newlines)
        else
          {i, newlines}
        end
      end
      {_i, newlines} = ex_loop_61.(ex_loop_61, i, newlines)
      if newlines == 1 do
        TemperCore.StringBuilder.append(piece, "\n")
        nil
      else
        nil
      end
      Temper.MarginaliaCore.flushParagraph__318(piece, out)
      TemperCore.List.to_list(out)
    end)
  end
  def alignmentKey__319(p) do
    out = TemperCore.StringBuilder.new()
    inSpace = false
    i = TemperCore.String.begin()
    ex_loop_64 = fn ex_loop_64, i, inSpace ->
      if TemperCore.String.has_index(p, i) do
        cp = TemperCore.String.get(p, i)
        inSpace = if Temper.MarginaliaCore.isRegexSpace(cp) do
          inSpace = true
          inSpace
        else
          if inSpace do
            TemperCore.StringBuilder.append(out, " ")
            nil
          else
            nil
          end
          inSpace = false
          try do
            TemperCore.StringBuilder.append_code_point(out, cp)
            nil
          rescue
            _ in TemperCore.Bubble ->
              raise(TemperCore.Bubble)
          end
          inSpace
        end
        i = TemperCore.String.next(p, i)
        ex_loop_64.(ex_loop_64, i, inSpace)
      else
        {i, inSpace}
      end
    end
    {_i, inSpace} = ex_loop_64.(ex_loop_64, i, inSpace)
    if inSpace do
      TemperCore.StringBuilder.append(out, " ")
      nil
    else
      nil
    end
    Temper.MarginaliaCore.trim(TemperCore.StringBuilder.to_string(out))
  end
  def flushRun__320(dels, ins, out) do
    _longer = nil
    longer = if TemperCore.List.length(dels) > TemperCore.List.length(ins) do
      longer = TemperCore.List.length(dels)
      longer
    else
      longer = TemperCore.List.length(ins)
      longer
    end
    k = 0
    ex_loop_67 = fn ex_loop_67, k ->
      if k < longer do
        _t = nil
        t = if k < TemperCore.List.length(dels) do
          t = k < TemperCore.List.length(ins)
          t
        else
          t = false
          t
        end
        cond do
          t ->
            TemperCore.List.add(out, Temper.MarginaliaCore.Row.new("change", TemperCore.List.get(dels, k), TemperCore.List.get(ins, k)))
            nil
          k < TemperCore.List.length(dels) ->
            TemperCore.List.add(out, Temper.MarginaliaCore.Row.new("del", TemperCore.List.get(dels, k), nil))
            nil
          true ->
            TemperCore.List.add(out, Temper.MarginaliaCore.Row.new("ins", nil, TemperCore.List.get(ins, k)))
            nil
        end
        k = TemperCore.int32(k + 1)
        ex_loop_67.(ex_loop_67, k)
      else
        k
      end
    end
    _k = ex_loop_67.(ex_loop_67, k)
    TemperCore.List.clear(dels)
    TemperCore.List.clear(ins)
    nil
  end
  def rows(before, after_) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      a = Temper.MarginaliaCore.paragraphs(before)
      b = Temper.MarginaliaCore.paragraphs(after_)
      fn_1 = fn p1 ->
        Temper.MarginaliaCore.alignmentKey__319(p1)
      end
      ak = TemperCore.List.map(a, fn_1)
      fn_2 = fn p2 ->
        Temper.MarginaliaCore.alignmentKey__319(p2)
      end
      bk = TemperCore.List.map(b, fn_2)
      n = TemperCore.List.length(a)
      m = TemperCore.List.length(b)
      width = TemperCore.int32(m + 1)
      table = TemperCore.List.builder()
      k = 0
      ex_loop_72 = fn ex_loop_72, k ->
        if k < TemperCore.int32(TemperCore.int32(n + 1) * width) do
          TemperCore.List.add(table, 0)
          k = TemperCore.int32(k + 1)
          ex_loop_72.(ex_loop_72, k)
        else
          k
        end
      end
      _k = ex_loop_72.(ex_loop_72, k)
      i1 = TemperCore.int32(n - 1)
      ex_loop_74 = fn ex_loop_74, i1 ->
        if i1 >= 0 do
          j2 = TemperCore.int32(m - 1)
          ex_loop_76 = fn ex_loop_76, j2 ->
            if j2 >= 0 do
              _value = nil
              value = if TemperCore.List.get(ak, i1) == TemperCore.List.get(bk, j2) do
                value = TemperCore.int32(1 + TemperCore.List.get(table, TemperCore.int32(TemperCore.int32(TemperCore.int32(TemperCore.int32(i1 + 1) * width) + j2) + 1)))
                value
              else
                _t4 = nil
                down = TemperCore.List.get(table, TemperCore.int32(TemperCore.int32(TemperCore.int32(i1 + 1) * width) + j2))
                across = TemperCore.List.get(table, TemperCore.int32(TemperCore.int32(TemperCore.int32(i1 * width) + j2) + 1))
                t4 = if down > across do
                  t4 = down
                  t4
                else
                  t4 = across
                  t4
                end
                value = t4
                value
              end
              TemperCore.List.set(table, TemperCore.int32(TemperCore.int32(i1 * width) + j2), value)
              j2 = TemperCore.int32(j2 - 1)
              ex_loop_76.(ex_loop_76, j2)
            else
              j2
            end
          end
          _j2 = ex_loop_76.(ex_loop_76, j2)
          i1 = TemperCore.int32(i1 - 1)
          ex_loop_74.(ex_loop_74, i1)
        else
          i1
        end
      end
      _i1 = ex_loop_74.(ex_loop_74, i1)
      out = TemperCore.List.builder()
      dels = TemperCore.List.builder()
      ins = TemperCore.List.builder()
      i2 = 0
      j1 = 0
      ex_loop_78 = fn ex_loop_78, i2, j1 ->
        if true do
          _t1 = nil
          t1 = if i2 < n do
            t1 = true
            t1
          else
            t1 = j1 < m
            t1
          end
          if not t1 do
            {i2, j1}
          else
            _t2 = nil
            t2 = if i2 < n do
              if j1 < m do
                t2 = TemperCore.List.get(ak, i2) == TemperCore.List.get(bk, j1)
                t2
              else
                t2 = false
                t2
              end
            else
              t2 = false
              t2
            end
            if t2 do
              Temper.MarginaliaCore.flushRun__320(dels, ins, out)
              TemperCore.List.add(out, Temper.MarginaliaCore.Row.new("same", TemperCore.List.get(a, i2), TemperCore.List.get(a, i2)))
              i2 = TemperCore.int32(i2 + 1)
              j1 = TemperCore.int32(j1 + 1)
              ex_loop_78.(ex_loop_78, i2, j1)
            else
              _t3 = nil
              t3 = if j1 < m do
                if i2 >= n do
                  t3 = true
                  t3
                else
                  t3 = TemperCore.List.get(table, TemperCore.int32(TemperCore.int32(TemperCore.int32(i2 * width) + j1) + 1)) >= TemperCore.List.get(table, TemperCore.int32(TemperCore.int32(TemperCore.int32(i2 + 1) * width) + j1))
                  t3
                end
              else
                t3 = false
                t3
              end
              if t3 do
                TemperCore.List.add(ins, TemperCore.List.get(b, j1))
                j1 = TemperCore.int32(j1 + 1)
                ex_loop_78.(ex_loop_78, i2, j1)
              else
                TemperCore.List.add(dels, TemperCore.List.get(a, i2))
                i2 = TemperCore.int32(i2 + 1)
                ex_loop_78.(ex_loop_78, i2, j1)
              end
            end
          end
        else
          {i2, j1}
        end
      end
      {_i2, _j1} = ex_loop_78.(ex_loop_78, i2, j1)
      Temper.MarginaliaCore.flushRun__320(dels, ins, out)
      TemperCore.List.to_list(out)
    end)
  end
  def isUnicodeLetter(cp) do
    TemperConnected.isUnicodeLetter(cp)
  end
  def isUnicodeNumber(cp) do
    TemperConnected.isUnicodeNumber(cp)
  end
  def isUpcaseFixed(cp) do
    TemperConnected.isUpcaseFixed(cp)
  end
  def downcase(s) do
    TemperConnected.downcase(s)
  end
  def graphemeLength(s) do
    TemperConnected.graphemeLength(s)
  end
  def isWrapped(text) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      lines = TemperCore.String.split(text, "\n")
      nonBlank = 0
      k = 0
      ex_loop_81 = fn ex_loop_81, k, nonBlank ->
        if k < TemperCore.List.length(lines) do
          nonBlank = if not TemperCore.String.is_empty(Temper.MarginaliaCore.trim(TemperCore.List.get(lines, k))) do
            nonBlank = TemperCore.int32(nonBlank + 1)
            nonBlank
          else
            nonBlank
          end
          k = TemperCore.int32(k + 1)
          ex_loop_81.(ex_loop_81, k, nonBlank)
        else
          {k, nonBlank}
        end
      end
      {_k, nonBlank} = ex_loop_81.(ex_loop_81, k, nonBlank)
      gaps = 0
      i = TemperCore.String.begin()
      ex_loop_83 = fn ex_loop_83, gaps, i ->
        if TemperCore.String.has_index(text, i) do
          if Temper.MarginaliaCore.isRegexSpace(TemperCore.String.get(text, i)) do
            newlines = 0
            ex_loop_85 = fn ex_loop_85, i, newlines ->
              if true do
                _t = nil
                t = if TemperCore.String.has_index(text, i) do
                  t = Temper.MarginaliaCore.isRegexSpace(TemperCore.String.get(text, i))
                  t
                else
                  t = false
                  t
                end
                if not t do
                  {i, newlines}
                else
                  newlines = if TemperCore.String.get(text, i) == 10 do
                    newlines = TemperCore.int32(newlines + 1)
                    newlines
                  else
                    newlines
                  end
                  i = TemperCore.String.next(text, i)
                  ex_loop_85.(ex_loop_85, i, newlines)
                end
              else
                {i, newlines}
              end
            end
            {i, newlines} = ex_loop_85.(ex_loop_85, i, newlines)
            if newlines >= 2 do
              gaps = TemperCore.int32(gaps + 1)
              ex_loop_83.(ex_loop_83, gaps, i)
            else
              ex_loop_83.(ex_loop_83, gaps, i)
            end
          else
            i = TemperCore.String.next(text, i)
            ex_loop_83.(ex_loop_83, gaps, i)
          end
        else
          {gaps, i}
        end
      end
      {gaps, _i} = ex_loop_83.(ex_loop_83, gaps, i)
      if nonBlank >= 12 do
        gaps <= TemperCore.int32(div(nonBlank, 12))
      else
        false
      end
    end)
  end
  def isWordChar__333(cp) do
    cond do
      cp == 8217 ->
        true
      cp == 39 ->
        true
      Temper.MarginaliaCore.isUnicodeLetter(cp) ->
        true
      true ->
        Temper.MarginaliaCore.isUnicodeNumber(cp)
    end
  end
  def intactHyphens__334(text) do
    found = TemperCore.Map.builder()
    i = TemperCore.String.begin()
    ex_loop_89 = fn ex_loop_89, i ->
      if TemperCore.String.has_index(text, i) do
        if not Temper.MarginaliaCore.isWordChar__333(TemperCore.String.get(text, i)) do
          i = TemperCore.String.next(text, i)
          ex_loop_89.(ex_loop_89, i)
        else
          start = i
          ex_loop_91 = fn ex_loop_91, i ->
            if true do
              _t2 = nil
              t2 = if TemperCore.String.has_index(text, i) do
                t2 = Temper.MarginaliaCore.isWordChar__333(TemperCore.String.get(text, i))
                t2
              else
                t2 = false
                t2
              end
              if not t2 do
                i
              else
                i = TemperCore.String.next(text, i)
                ex_loop_91.(ex_loop_91, i)
              end
            else
              i
            end
          end
          i = ex_loop_91.(ex_loop_91, i)
          _t1 = nil
          t1 = if TemperCore.String.has_index(text, i) do
            t1 = TemperCore.String.get(text, i) == 45
            t1
          else
            t1 = false
            t1
          end
          if t1 do
            after_ = TemperCore.String.next(text, i)
            _t3 = nil
            t3 = if TemperCore.String.has_index(text, after_) do
              t3 = Temper.MarginaliaCore.isWordChar__333(TemperCore.String.get(text, after_))
              t3
            else
              t3 = false
              t3
            end
            if t3 do
              e = after_
              ex_loop_93 = fn ex_loop_93, e ->
                if true do
                  _t4 = nil
                  t4 = if TemperCore.String.has_index(text, e) do
                    t4 = Temper.MarginaliaCore.isWordChar__333(TemperCore.String.get(text, e))
                    t4
                  else
                    t4 = false
                    t4
                  end
                  if not t4 do
                    e
                  else
                    e = TemperCore.String.next(text, e)
                    ex_loop_93.(ex_loop_93, e)
                  end
                else
                  e
                end
              end
              e = ex_loop_93.(ex_loop_93, e)
              TemperCore.Map.set(found, Temper.MarginaliaCore.downcase(TemperCore.String.slice(text, start, e)), true)
              i = e
              ex_loop_89.(ex_loop_89, i)
            else
              ex_loop_89.(ex_loop_89, i)
            end
          else
            ex_loop_89.(ex_loop_89, i)
          end
        end
      else
        i
      end
    end
    _i = ex_loop_89.(ex_loop_89, i)
    found
  end
  def normalizeNewlines__321(text) do
    Temper.MarginaliaCore.joinWith(TemperCore.String.split(text, "\r\n"), "\n")
  end
  def isJudgeLine__330(line) do
    try do
      _return = nil
      return = if true do
        i = TemperCore.String.begin()
        names = 0
        ex_loop_98 = fn ex_loop_98, i, names ->
          if true do
            j = i
            caps = 0
            ex_loop_100 = fn ex_loop_100, caps, j ->
              if true do
                _t4 = nil
                t4 = if TemperCore.String.has_index(line, j) do
                  if TemperCore.String.get(line, j) >= 65 do
                    t4 = TemperCore.String.get(line, j) <= 90
                    t4
                  else
                    t4 = false
                    t4
                  end
                else
                  t4 = false
                  t4
                end
                if not t4 do
                  {caps, j}
                else
                  caps = TemperCore.int32(caps + 1)
                  j = TemperCore.String.next(line, j)
                  ex_loop_100.(ex_loop_100, caps, j)
                end
              else
                {caps, j}
              end
            end
            {caps, j} = ex_loop_100.(ex_loop_100, caps, j)
            _t1 = nil
            t1 = cond do
              caps == 0 ->
                t1 = true
                t1
              not TemperCore.String.has_index(line, j) ->
                t1 = true
                t1
              true ->
                t1 = TemperCore.String.get(line, j) != 44
                t1
            end
            if t1 do
              {i, names}
            else
              space = TemperCore.String.next(line, j)
              _t2 = nil
              t2 = if not TemperCore.String.has_index(line, space) do
                t2 = true
                t2
              else
                t2 = TemperCore.String.get(line, space) != 32
                t2
              end
              if t2 do
                {i, names}
              else
                names = TemperCore.int32(names + 1)
                i = TemperCore.String.next(line, space)
                ex_loop_98.(ex_loop_98, i, names)
              end
            end
          else
            {i, names}
          end
        end
        {i, names} = ex_loop_98.(ex_loop_98, i, names)
        if names == 0 do
          return = false
          return
        else
          rest = TemperCore.String.slice(line, i, TemperCore.String.end_of(line))
          at = TemperCore.String.begin()
          at = if Temper.MarginaliaCore.startsWith(rest, "C. ") do
            at = TemperCore.String.step(rest, at, 3)
            at
          else
            at
          end
          tail = TemperCore.String.slice(rest, at, TemperCore.String.end_of(rest))
          if not Temper.MarginaliaCore.startsWith(tail, "J.,") do
            return = false
            return
          else
            k = TemperCore.String.step(tail, TemperCore.String.begin(), 3)
            spaces = 0
            ex_loop_102 = fn ex_loop_102, k, spaces ->
              if true do
                _t3 = nil
                t3 = if TemperCore.String.has_index(tail, k) do
                  t3 = Temper.MarginaliaCore.isRegexSpace(TemperCore.String.get(tail, k))
                  t3
                else
                  t3 = false
                  t3
                end
                if not t3 do
                  {k, spaces}
                else
                  spaces = TemperCore.int32(spaces + 1)
                  k = TemperCore.String.next(tail, k)
                  ex_loop_102.(ex_loop_102, k, spaces)
                end
              else
                {k, spaces}
              end
            end
            {k, spaces} = ex_loop_102.(ex_loop_102, k, spaces)
            word = TemperCore.String.slice(tail, k, TemperCore.String.end_of(tail))
            if spaces >= 1 do
              if Temper.MarginaliaCore.startsWith(word, "concurring") do
                throw({:temper_return, :ex_return_96, true})
              else
                throw({:temper_return, :ex_return_96, Temper.MarginaliaCore.startsWith(word, "dissenting")})
              end
            else
              throw({:temper_return, :ex_return_96, false})
            end
          end
        end
      end
      return
    catch
      {:temper_return, :ex_return_96, ex_value_104} ->
        ex_value_104
    end
  end
  def allAsciiDigits__329(s, from, to) do
    try do
      return = nil
      return = try do
        i = from
        ex_loop_107 = fn ex_loop_107, i, return ->
          if i < to do
            _t = nil
            t = if TemperCore.String.get(s, i) < 48 do
              t = true
              t
            else
              t = TemperCore.String.get(s, i) > 57
              t
            end
            if t do
              return = false
              throw({:temper_break, :ex_block_106, return})
            else
              i = TemperCore.String.next(s, i)
              ex_loop_107.(ex_loop_107, i, return)
            end
          else
            {i, return}
          end
        end
        {_i, _return} = ex_loop_107.(ex_loop_107, i, return)
        throw({:temper_return, :ex_return_105, true})
      catch
        {:temper_break, :ex_block_106, ex_vars_109} ->
          ex_vars_109
      end
      return
    catch
      {:temper_return, :ex_return_105, ex_value_110} ->
        ex_value_110
    end
  end
  def isPageNumber__328(line) do
    n = TemperCore.String.count_between(line, TemperCore.String.begin(), TemperCore.String.end_of(line))
    if n >= 1 do
      if n <= 3 do
        Temper.MarginaliaCore.allAsciiDigits__329(line, TemperCore.String.begin(), TemperCore.String.end_of(line))
      else
        false
      end
    else
      false
    end
  end
  def withoutPageNumbers__332(line) do
    s = line
    i = TemperCore.String.begin()
    digits = 0
    ex_loop_113 = fn ex_loop_113, digits, i ->
      if true do
        _t3 = nil
        t3 = if TemperCore.String.has_index(s, i) do
          if TemperCore.String.get(s, i) >= 48 do
            if TemperCore.String.get(s, i) <= 57 do
              t3 = digits < 4
              t3
            else
              t3 = false
              t3
            end
          else
            t3 = false
            t3
          end
        else
          t3 = false
          t3
        end
        if not t3 do
          {digits, i}
        else
          digits = TemperCore.int32(digits + 1)
          i = TemperCore.String.next(s, i)
          ex_loop_113.(ex_loop_113, digits, i)
        end
      else
        {digits, i}
      end
    end
    {digits, i} = ex_loop_113.(ex_loop_113, digits, i)
    _t1 = nil
    t1 = if digits >= 1 do
      if digits <= 3 do
        if TemperCore.String.has_index(s, i) do
          t1 = Temper.MarginaliaCore.isRegexSpace(TemperCore.String.get(s, i))
          t1
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
    {_i, s} = if t1 do
      ex_loop_115 = fn ex_loop_115, i ->
        if true do
          _t5 = nil
          t5 = if TemperCore.String.has_index(s, i) do
            t5 = Temper.MarginaliaCore.isRegexSpace(TemperCore.String.get(s, i))
            t5
          else
            t5 = false
            t5
          end
          if not t5 do
            i
          else
            i = TemperCore.String.next(s, i)
            ex_loop_115.(ex_loop_115, i)
          end
        else
          i
        end
      end
      i = ex_loop_115.(ex_loop_115, i)
      s = TemperCore.String.slice(s, i, TemperCore.String.end_of(s))
      {i, s}
    else
      {i, s}
    end
    e = TemperCore.String.end_of(s)
    tailDigits = 0
    ex_loop_117 = fn ex_loop_117, e, tailDigits ->
      if true do
        _t4 = nil
        t4 = if e > TemperCore.String.begin() do
          if TemperCore.String.get(s, TemperCore.String.prev(s, e)) >= 48 do
            if TemperCore.String.get(s, TemperCore.String.prev(s, e)) <= 57 do
              t4 = tailDigits < 4
              t4
            else
              t4 = false
              t4
            end
          else
            t4 = false
            t4
          end
        else
          t4 = false
          t4
        end
        if not t4 do
          {e, tailDigits}
        else
          tailDigits = TemperCore.int32(tailDigits + 1)
          e = TemperCore.String.prev(s, e)
          ex_loop_117.(ex_loop_117, e, tailDigits)
        end
      else
        {e, tailDigits}
      end
    end
    {e, tailDigits} = ex_loop_117.(ex_loop_117, e, tailDigits)
    _t2 = nil
    t2 = if tailDigits >= 1 do
      if tailDigits <= 3 do
        if e > TemperCore.String.begin() do
          t2 = Temper.MarginaliaCore.isRegexSpace(TemperCore.String.get(s, TemperCore.String.prev(s, e)))
          t2
        else
          t2 = false
          t2
        end
      else
        t2 = false
        t2
      end
    else
      t2 = false
      t2
    end
    {_e, s} = if t2 do
      ex_loop_119 = fn ex_loop_119, e ->
        if true do
          _t6 = nil
          t6 = if e > TemperCore.String.begin() do
            t6 = Temper.MarginaliaCore.isRegexSpace(TemperCore.String.get(s, TemperCore.String.prev(s, e)))
            t6
          else
            t6 = false
            t6
          end
          if not t6 do
            e
          else
            e = TemperCore.String.prev(s, e)
            ex_loop_119.(ex_loop_119, e)
          end
        else
          e
        end
      end
      e = ex_loop_119.(ex_loop_119, e)
      s = TemperCore.String.slice(s, TemperCore.String.begin(), e)
      {e, s}
    else
      {e, s}
    end
    s
  end
  def isCaption__331(line) do
    try do
      _return = nil
      return = if true do
        body = Temper.MarginaliaCore.withoutPageNumbers__332(line)
        letters = 0
        upper = 0
        i = TemperCore.String.begin()
        ex_loop_123 = fn ex_loop_123, i, letters, upper ->
          if TemperCore.String.has_index(body, i) do
            cp = TemperCore.String.get(body, i)
            {letters, upper} = if Temper.MarginaliaCore.isUnicodeLetter(cp) do
              letters = TemperCore.int32(letters + 1)
              if Temper.MarginaliaCore.isUpcaseFixed(cp) do
                upper = TemperCore.int32(upper + 1)
                {letters, upper}
              else
                {letters, upper}
              end
            else
              {letters, upper}
            end
            i = TemperCore.String.next(body, i)
            ex_loop_123.(ex_loop_123, i, letters, upper)
          else
            {i, letters, upper}
          end
        end
        {_i, letters, upper} = ex_loop_123.(ex_loop_123, i, letters, upper)
        if letters < 8 do
          return = false
          return
        else
          ratio = nil
          ratio = try do
            ratio = TemperCore.Float.divide(TemperCore.int_to_float(upper), TemperCore.int_to_float(letters))
            ratio
          rescue
            _ in TemperCore.Bubble ->
              raise(TemperCore.Panic)
              ratio
          end
          throw({:temper_return, :ex_return_121, TemperCore.Float.ge(ratio, 0.75)})
        end
      end
      return
    catch
      {:temper_return, :ex_return_121, ex_value_125} ->
        ex_value_125
    end
  end
  def isFurniture__327(line) do
    cond do
      Temper.MarginaliaCore.startsWith(line, "Cite as:") ->
        true
      line == "Opinion of the Court" ->
        true
      line == "Syllabus" ->
        true
      line == "Per Curiam" ->
        true
      Temper.MarginaliaCore.isJudgeLine__330(line) ->
        true
      Temper.MarginaliaCore.isPageNumber__328(line) ->
        true
      true ->
        Temper.MarginaliaCore.isCaption__331(line)
    end
  end
  def contains__326(chars, cp) do
    try do
      return = nil
      return = try do
        i = TemperCore.String.begin()
        ex_loop_129 = fn ex_loop_129, i, return ->
          if TemperCore.String.has_index(chars, i) do
            if TemperCore.String.get(chars, i) == cp do
              return = true
              throw({:temper_break, :ex_block_128, return})
            else
              i = TemperCore.String.next(chars, i)
              ex_loop_129.(ex_loop_129, i, return)
            end
          else
            {i, return}
          end
        end
        {_i, _return} = ex_loop_129.(ex_loop_129, i, return)
        throw({:temper_return, :ex_return_127, false})
      catch
        {:temper_break, :ex_block_128, ex_vars_131} ->
          ex_vars_131
      end
      return
    catch
      {:temper_return, :ex_return_127, ex_value_132} ->
        ex_value_132
    end
  end
  def allIn__325(s, chars) do
    try do
      return = nil
      return = try do
        i = TemperCore.String.begin()
        ex_loop_135 = fn ex_loop_135, i, return ->
          if TemperCore.String.has_index(s, i) do
            if not Temper.MarginaliaCore.contains__326(chars, TemperCore.String.get(s, i)) do
              return = false
              throw({:temper_break, :ex_block_134, return})
            else
              i = TemperCore.String.next(s, i)
              ex_loop_135.(ex_loop_135, i, return)
            end
          else
            {i, return}
          end
        end
        {_i, _return} = ex_loop_135.(ex_loop_135, i, return)
        throw({:temper_return, :ex_return_133, true})
      catch
        {:temper_break, :ex_block_134, ex_vars_137} ->
          ex_vars_137
      end
      return
    catch
      {:temper_return, :ex_return_133, ex_value_138} ->
        ex_value_138
    end
  end
  def isHeading__324(line) do
    try do
      return = nil
      return = try do
        i = TemperCore.String.begin()
        hashes = 0
        ex_loop_141 = fn ex_loop_141, hashes, i ->
          if true do
            _t3 = nil
            t3 = if TemperCore.String.has_index(line, i) do
              t3 = TemperCore.String.get(line, i) == 35
              t3
            else
              t3 = false
              t3
            end
            if not t3 do
              {hashes, i}
            else
              hashes = TemperCore.int32(hashes + 1)
              i = TemperCore.String.next(line, i)
              ex_loop_141.(ex_loop_141, hashes, i)
            end
          else
            {hashes, i}
          end
        end
        {hashes, i} = ex_loop_141.(ex_loop_141, hashes, i)
        _t1 = nil
        t1 = if hashes >= 1 do
          if hashes <= 6 do
            if TemperCore.String.has_index(line, i) do
              t1 = Temper.MarginaliaCore.isRegexSpace(TemperCore.String.get(line, i))
              t1
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
        {_i, _return} = if t1 do
          ex_loop_143 = fn ex_loop_143, i ->
            if true do
              _t4 = nil
              t4 = if TemperCore.String.has_index(line, i) do
                t4 = Temper.MarginaliaCore.isRegexSpace(TemperCore.String.get(line, i))
                t4
              else
                t4 = false
                t4
              end
              if not t4 do
                i
              else
                i = TemperCore.String.next(line, i)
                ex_loop_143.(ex_loop_143, i)
              end
            else
              i
            end
          end
          i = ex_loop_143.(ex_loop_143, i)
          if TemperCore.String.has_index(line, i) do
            return = true
            throw({:temper_break, :ex_block_140, return})
          else
            {i, return}
          end
        else
          {i, return}
        end
        n = TemperCore.String.count_between(line, TemperCore.String.begin(), TemperCore.String.end_of(line))
        _t2 = nil
        t2 = if n >= 1 do
          if n <= 5 do
            t2 = Temper.MarginaliaCore.allIn__325(line, "IVXL")
            t2
          else
            t2 = false
            t2
          end
        else
          t2 = false
          t2
        end
        cond do
          t2 ->
            return = true
            return
          n == 1 ->
            if TemperCore.String.get(line, TemperCore.String.begin()) >= 65 do
              throw({:temper_return, :ex_return_139, TemperCore.String.get(line, TemperCore.String.begin()) <= 90})
            else
              throw({:temper_return, :ex_return_139, false})
            end
          true ->
            throw({:temper_return, :ex_return_139, false})
        end
      catch
        {:temper_break, :ex_block_140, ex_vars_145} ->
          ex_vars_145
      end
      return
    catch
      {:temper_return, :ex_return_139, ex_value_146} ->
        ex_value_146
    end
  end
  def chunkParagraphs__323(lines, measure) do
    done = TemperCore.List.builder()
    current = TemperCore.List.builder()
    k = 0
    ex_loop_148 = fn ex_loop_148, k ->
      if k < TemperCore.List.length(lines) do
        line = TemperCore.List.get(lines, k)
        cond do
          Temper.MarginaliaCore.isHeading__324(line) ->
            TemperCore.List.add(done, TemperCore.List.to_list(current))
            TemperCore.List.add(done, %TemperCore.Vec{t: {line}})
            TemperCore.List.clear(current)
            nil
          TemperCore.Float.lt(TemperCore.int_to_float(Temper.MarginaliaCore.graphemeLength(line)), TemperCore.Float.mul(TemperCore.int_to_float(measure), 0.78)) ->
            TemperCore.List.add(current, line)
            TemperCore.List.add(done, TemperCore.List.to_list(current))
            TemperCore.List.clear(current)
            nil
          true ->
            TemperCore.List.add(current, line)
            nil
        end
        k = TemperCore.int32(k + 1)
        ex_loop_148.(ex_loop_148, k)
      else
        k
      end
    end
    _k = ex_loop_148.(ex_loop_148, k)
    TemperCore.List.add(done, TemperCore.List.to_list(current))
    fn_ = fn p ->
      not TemperCore.List.is_empty(p)
    end
    TemperCore.List.filter(TemperCore.List.to_list(done), fn_)
  end
  def measure__322(lines) do
    try do
      _return = nil
      return = if true do
        if TemperCore.List.is_empty(lines) do
          return = 0
          return
        else
          fn_1 = fn l ->
            Temper.MarginaliaCore.graphemeLength(l)
          end
          fn_2 = fn a, b ->
            TemperCore.int32(a - b)
          end
          lengths = TemperCore.List.sorted(TemperCore.List.map(lines, fn_1), fn_2)
          throw({:temper_return, :ex_return_151, TemperCore.List.get(lengths, TemperCore.int32(div(TemperCore.int32(TemperCore.List.length(lengths) * 2), 3)))})
        end
      end
      return
    catch
      {:temper_return, :ex_return_151, ex_value_155} ->
        ex_value_155
    end
  end
  def endsWithAt(s, end_, suffix) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      try do
        return = nil
        return = try do
          i = end_
          j = TemperCore.String.end_of(suffix)
          ex_loop_158 = fn ex_loop_158, i, j, return ->
            if j > TemperCore.String.begin() do
              if i <= TemperCore.String.begin() do
                return = false
                throw({:temper_break, :ex_block_157, return})
              else
                i = TemperCore.String.prev(s, i)
                j = TemperCore.String.prev(suffix, j)
                if TemperCore.String.get(s, i) != TemperCore.String.get(suffix, j) do
                  return = false
                  throw({:temper_break, :ex_block_157, return})
                else
                  ex_loop_158.(ex_loop_158, i, j, return)
                end
              end
            else
              {i, j, return}
            end
          end
          {_i, _j, _return} = ex_loop_158.(ex_loop_158, i, j, return)
          throw({:temper_return, :ex_return_156, true})
        catch
          {:temper_break, :ex_block_157, ex_vars_160} ->
            ex_vars_160
        end
        return
      catch
        {:temper_return, :ex_return_156, ex_value_161} ->
          ex_value_161
      end
    end)
  end
  def withoutTrailingHyphens__337(s) do
    e = TemperCore.String.end_of(s)
    ex_loop_163 = fn ex_loop_163, e ->
      if true do
        _t = nil
        t = if e > TemperCore.String.begin() do
          t = TemperCore.String.get(s, TemperCore.String.prev(s, e)) == 45
          t
        else
          t = false
          t
        end
        if not t do
          e
        else
          e = TemperCore.String.prev(s, e)
          ex_loop_163.(ex_loop_163, e)
        end
      else
        e
      end
    end
    e = ex_loop_163.(ex_loop_163, e)
    TemperCore.String.slice(s, TemperCore.String.begin(), e)
  end
  def lastAsciiSpaceField__338(s) do
    b = TemperCore.String.end_of(s)
    ex_loop_166 = fn ex_loop_166, b ->
      if true do
        _t = nil
        t = if b > TemperCore.String.begin() do
          t = not Temper.MarginaliaCore.isRegexSpace(TemperCore.String.get(s, TemperCore.String.prev(s, b)))
          t
        else
          t = false
          t
        end
        if not t do
          b
        else
          b = TemperCore.String.prev(s, b)
          ex_loop_166.(ex_loop_166, b)
        end
      else
        b
      end
    end
    b = ex_loop_166.(ex_loop_166, b)
    TemperCore.String.slice(s, b, TemperCore.String.end_of(s))
  end
  def firstAsciiSpaceField__339(s) do
    e = TemperCore.String.begin()
    ex_loop_169 = fn ex_loop_169, e ->
      if true do
        _t = nil
        t = if TemperCore.String.has_index(s, e) do
          t = not Temper.MarginaliaCore.isRegexSpace(TemperCore.String.get(s, e))
          t
        else
          t = false
          t
        end
        if not t do
          e
        else
          e = TemperCore.String.next(s, e)
          ex_loop_169.(ex_loop_169, e)
        end
      else
        e
      end
    end
    e = ex_loop_169.(ex_loop_169, e)
    TemperCore.String.slice(s, TemperCore.String.begin(), e)
  end
  def stripTrailingPunct__340(word) do
    e = TemperCore.String.end_of(word)
    ex_loop_172 = fn ex_loop_172, e ->
      if true do
        _t = nil
        t = if e > TemperCore.String.begin() do
          if not Temper.MarginaliaCore.isWordChar__333(TemperCore.String.get(word, TemperCore.String.prev(word, e))) do
            t = TemperCore.String.get(word, TemperCore.String.prev(word, e)) != 45
            t
          else
            t = false
            t
          end
        else
          t = false
          t
        end
        if not t do
          e
        else
          e = TemperCore.String.prev(word, e)
          ex_loop_172.(ex_loop_172, e)
        end
      else
        e
      end
    end
    e = ex_loop_172.(ex_loop_172, e)
    TemperCore.String.slice(word, TemperCore.String.begin(), e)
  end
  def mend__336(acc, line, keep) do
    unhyphened = Temper.MarginaliaCore.withoutTrailingHyphens__337(acc)
    stem = Temper.MarginaliaCore.lastAsciiSpaceField__338(unhyphened)
    head = Temper.MarginaliaCore.firstAsciiSpaceField__339(line)
    word = Temper.MarginaliaCore.downcase(stem <> "-" <> Temper.MarginaliaCore.stripTrailingPunct__340(head))
    if TemperCore.Map.has(keep, word) do
      acc <> line
    else
      unhyphened <> line
    end
  end
  def join__335(lines, keep) do
    acc = ""
    k = 0
    ex_loop_176 = fn ex_loop_176, acc, k ->
      if k < TemperCore.List.length(lines) do
        line = TemperCore.List.get(lines, k)
        acc = cond do
          TemperCore.String.is_empty(acc) ->
            acc = line
            acc
          Temper.MarginaliaCore.endsWithAt(acc, TemperCore.String.end_of(acc), "-") ->
            acc = Temper.MarginaliaCore.mend__336(acc, line, keep)
            acc
          true ->
            acc = acc <> " " <> line
            acc
        end
        k = TemperCore.int32(k + 1)
        ex_loop_176.(ex_loop_176, acc, k)
      else
        {acc, k}
      end
    end
    {acc, _k} = ex_loop_176.(ex_loop_176, acc, k)
    Temper.MarginaliaCore.trim(acc)
  end
  def reflowPage(text) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      try do
        _return = nil
        return = if true do
          if not Temper.MarginaliaCore.isWrapped(text) do
            return = text
            return
          else
            keep = Temper.MarginaliaCore.intactHyphens__334(text)
            raw = TemperCore.String.split(Temper.MarginaliaCore.normalizeNewlines__321(text), "\n")
            lines = TemperCore.List.builder()
            k1 = 0
            ex_loop_180 = fn ex_loop_180, k1 ->
              if k1 < TemperCore.List.length(raw) do
                line = Temper.MarginaliaCore.trim(TemperCore.List.get(raw, k1))
                _t = nil
                t = if not Temper.MarginaliaCore.isFurniture__327(line) do
                  t = not TemperCore.String.is_empty(line)
                  t
                else
                  t = false
                  t
                end
                if t do
                  TemperCore.List.add(lines, line)
                  nil
                else
                  nil
                end
                k1 = TemperCore.int32(k1 + 1)
                ex_loop_180.(ex_loop_180, k1)
              else
                k1
              end
            end
            _k1 = ex_loop_180.(ex_loop_180, k1)
            all = TemperCore.List.to_list(lines)
            paragraphs = Temper.MarginaliaCore.chunkParagraphs__323(all, Temper.MarginaliaCore.measure__322(all))
            out = TemperCore.List.builder()
            k2 = 0
            ex_loop_182 = fn ex_loop_182, k2 ->
              if k2 < TemperCore.List.length(paragraphs) do
                p = Temper.MarginaliaCore.join__335(TemperCore.List.get(paragraphs, k2), keep)
                if not TemperCore.String.is_empty(p) do
                  TemperCore.List.add(out, p)
                  nil
                else
                  nil
                end
                k2 = TemperCore.int32(k2 + 1)
                ex_loop_182.(ex_loop_182, k2)
              else
                k2
              end
            end
            _k2 = ex_loop_182.(ex_loop_182, k2)
            throw({:temper_return, :ex_return_178, Temper.MarginaliaCore.joinWith(TemperCore.List.to_list(out), "\n\n")})
          end
        end
        return
      catch
        {:temper_return, :ex_return_178, ex_value_184} ->
          ex_value_184
      end
    end)
  end
  def align(quote_, source) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      raw = TemperCore.String.split(Temper.MarginaliaCore.normalizeNewlines__321(quote_), "\n")
      lines = TemperCore.List.builder()
      k = 0
      ex_loop_186 = fn ex_loop_186, k ->
        if k < TemperCore.List.length(raw) do
          line = Temper.MarginaliaCore.trim(TemperCore.List.get(raw, k))
          if not TemperCore.String.is_empty(line) do
            TemperCore.List.add(lines, line)
            nil
          else
            nil
          end
          k = TemperCore.int32(k + 1)
          ex_loop_186.(ex_loop_186, k)
        else
          k
        end
      end
      _k = ex_loop_186.(ex_loop_186, k)
      Temper.MarginaliaCore.join__335(TemperCore.List.to_list(lines), Temper.MarginaliaCore.intactHyphens__334(source))
    end)
  end
  def isUnicodeSpace(cp) do
    TemperConnected.isUnicodeSpace(cp)
  end
  def isUnicodeUpper(cp) do
    TemperConnected.isUnicodeUpper(cp)
  end
  def isUnicodeDigit(cp) do
    TemperConnected.isUnicodeDigit(cp)
  end
  def isCloser__341(cp) do
    cond do
      cp == 34 ->
        true
      cp == 39 ->
        true
      cp == 8221 ->
        true
      cp == 8217 ->
        true
      cp == 41 ->
        true
      true ->
        cp == 93
    end
  end
  def isOpener__342(cp) do
    cond do
      cp == 34 ->
        true
      cp == 39 ->
        true
      cp == 8220 ->
        true
      cp == 8216 ->
        true
      cp == 40 ->
        true
      cp == 91 ->
        true
      cp == 42 ->
        true
      cp == 95 ->
        true
      true ->
        cp == 96
    end
  end
  def allOf__355(s, from, to, cp) do
    try do
      return = nil
      return = try do
        i = from
        ex_loop_192 = fn ex_loop_192, i, return ->
          if i < to do
            if TemperCore.String.get(s, i) != cp do
              return = false
              throw({:temper_break, :ex_block_191, return})
            else
              i = TemperCore.String.next(s, i)
              ex_loop_192.(ex_loop_192, i, return)
            end
          else
            {i, return}
          end
        end
        {_i, _return} = ex_loop_192.(ex_loop_192, i, return)
        throw({:temper_return, :ex_return_190, true})
      catch
        {:temper_break, :ex_block_191, ex_vars_194} ->
          ex_vars_194
      end
      return
    catch
      {:temper_return, :ex_return_190, ex_value_195} ->
        ex_value_195
    end
  end
  def isUnderline__354(s) do
    try do
      _return = nil
      return = if true do
        if TemperCore.String.is_empty(s) do
          return = false
          return
        else
          mark = TemperCore.String.get(s, TemperCore.String.begin())
          _t = nil
          t = if mark != 61 do
            t = mark != 45
            t
          else
            t = false
            t
          end
          if t do
            return = false
            return
          else
            throw({:temper_return, :ex_return_196, Temper.MarginaliaCore.allOf__355(s, TemperCore.String.begin(), TemperCore.String.end_of(s), mark)})
          end
        end
      end
      return
    catch
      {:temper_return, :ex_return_196, ex_value_198} ->
        ex_value_198
    end
  end
  def delimiterCell__357(s, at) do
    try do
      _return = nil
      return = if true do
        i = at
        ex_loop_201 = fn ex_loop_201, i ->
          if true do
            _t3 = nil
            t3 = if TemperCore.String.has_index(s, i) do
              t3 = Temper.MarginaliaCore.isRegexSpace(TemperCore.String.get(s, i))
              t3
            else
              t3 = false
              t3
            end
            if not t3 do
              i
            else
              i = TemperCore.String.next(s, i)
              ex_loop_201.(ex_loop_201, i)
            end
          else
            i
          end
        end
        i = ex_loop_201.(ex_loop_201, i)
        _t1 = nil
        t1 = if TemperCore.String.has_index(s, i) do
          t1 = TemperCore.String.get(s, i) == 58
          t1
        else
          t1 = false
          t1
        end
        i = if t1 do
          i = TemperCore.String.next(s, i)
          i
        else
          i
        end
        dashes = 0
        ex_loop_203 = fn ex_loop_203, dashes, i ->
          if true do
            _t4 = nil
            t4 = if TemperCore.String.has_index(s, i) do
              t4 = TemperCore.String.get(s, i) == 45
              t4
            else
              t4 = false
              t4
            end
            if not t4 do
              {dashes, i}
            else
              dashes = TemperCore.int32(dashes + 1)
              i = TemperCore.String.next(s, i)
              ex_loop_203.(ex_loop_203, dashes, i)
            end
          else
            {dashes, i}
          end
        end
        {dashes, i} = ex_loop_203.(ex_loop_203, dashes, i)
        if dashes < 3 do
          return = nil
          return
        else
          _t2 = nil
          t2 = if TemperCore.String.has_index(s, i) do
            t2 = TemperCore.String.get(s, i) == 58
            t2
          else
            t2 = false
            t2
          end
          i = if t2 do
            i = TemperCore.String.next(s, i)
            i
          else
            i
          end
          ex_loop_205 = fn ex_loop_205, i ->
            if true do
              _t5 = nil
              t5 = if TemperCore.String.has_index(s, i) do
                t5 = Temper.MarginaliaCore.isRegexSpace(TemperCore.String.get(s, i))
                t5
              else
                t5 = false
                t5
              end
              if not t5 do
                i
              else
                i = TemperCore.String.next(s, i)
                ex_loop_205.(ex_loop_205, i)
              end
            else
              i
            end
          end
          i = ex_loop_205.(ex_loop_205, i)
          throw({:temper_return, :ex_return_199, i})
        end
      end
      return
    catch
      {:temper_return, :ex_return_199, ex_value_207} ->
        ex_value_207
    end
  end
  def isTableDelimiter__356(s) do
    return = nil
    return = if true do
      t1 = nil
      i = TemperCore.String.begin()
      _t2 = nil
      t2 = if TemperCore.String.has_index(s, i) do
        t2 = TemperCore.String.get(s, i) == 124
        t2
      else
        t2 = false
        t2
      end
      i = if t2 do
        i = TemperCore.String.next(s, i)
        i
      else
        i
      end
      first = Temper.MarginaliaCore.delimiterCell__357(s, i)
      if first === nil do
        return = false
        return
      else
        t1 = try do
          if first === nil do
            raise(TemperCore.Bubble)
          else
            t1 = first
            t1
          end
        rescue
          _ in TemperCore.Bubble ->
            raise(TemperCore.Panic)
            t1
        end
        i = t1
        ex_loop_210 = fn ex_loop_210, i, return ->
          if true do
            cond do
              not TemperCore.String.has_index(s, i) ->
                return = true
                {i, return}
              TemperCore.String.get(s, i) != 124 ->
                return = false
                {i, return}
              true ->
                after_ = TemperCore.String.next(s, i)
                cell = Temper.MarginaliaCore.delimiterCell__357(s, after_)
                if cell === nil do
                  return = not TemperCore.String.has_index(s, after_)
                  {i, return}
                else
                  i = try do
                    if cell === nil do
                      raise(TemperCore.Bubble)
                    else
                      i = cell
                      i
                    end
                  rescue
                    _ in TemperCore.Bubble ->
                      raise(TemperCore.Panic)
                      i
                  end
                  ex_loop_210.(ex_loop_210, i, return)
                end
            end
          else
            {i, return}
          end
        end
        {_i, return} = ex_loop_210.(ex_loop_210, i, return)
        return
      end
    end
    return
  end
  def isAtxHeading__358(s) do
    i = TemperCore.String.begin()
    hashes = 0
    ex_loop_213 = fn ex_loop_213, hashes, i ->
      if true do
        _t = nil
        t = if TemperCore.String.has_index(s, i) do
          t = TemperCore.String.get(s, i) == 35
          t
        else
          t = false
          t
        end
        if not t do
          {hashes, i}
        else
          hashes = TemperCore.int32(hashes + 1)
          i = TemperCore.String.next(s, i)
          ex_loop_213.(ex_loop_213, hashes, i)
        end
      else
        {hashes, i}
      end
    end
    {hashes, i} = ex_loop_213.(ex_loop_213, hashes, i)
    if hashes >= 1 do
      if hashes <= 6 do
        if TemperCore.String.has_index(s, i) do
          Temper.MarginaliaCore.isRegexSpace(TemperCore.String.get(s, i))
        else
          false
        end
      else
        false
      end
    else
      false
    end
  end
  def isIndentedCode__359(block) do
    try do
      _return = nil
      return = if true do
        _t1 = nil
        t1 = if TemperCore.String.has_index(block, TemperCore.String.begin()) do
          t1 = TemperCore.String.get(block, TemperCore.String.begin()) == 9
          t1
        else
          t1 = false
          t1
        end
        if t1 do
          return = true
          return
        else
          i = TemperCore.String.begin()
          spaces = 0
          ex_loop_217 = fn ex_loop_217, i, spaces ->
            if true do
              _t2 = nil
              t2 = if TemperCore.String.has_index(block, i) do
                if Temper.MarginaliaCore.isRegexSpace(TemperCore.String.get(block, i)) do
                  t2 = spaces < 4
                  t2
                else
                  t2 = false
                  t2
                end
              else
                t2 = false
                t2
              end
              if not t2 do
                {i, spaces}
              else
                spaces = TemperCore.int32(spaces + 1)
                i = TemperCore.String.next(block, i)
                ex_loop_217.(ex_loop_217, i, spaces)
              end
            else
              {i, spaces}
            end
          end
          {_i, spaces} = ex_loop_217.(ex_loop_217, i, spaces)
          throw({:temper_return, :ex_return_215, spaces >= 4})
        end
      end
      return
    catch
      {:temper_return, :ex_return_215, ex_value_219} ->
        ex_value_219
    end
  end
  def isListItem__360(s) do
    try do
      _return = nil
      return = if true do
        if not TemperCore.String.has_index(s, TemperCore.String.begin()) do
          return = false
          return
        else
          c = TemperCore.String.get(s, TemperCore.String.begin())
          after_ = TemperCore.String.next(s, TemperCore.String.begin())
          _t1 = nil
          _t2 = nil
          t2 = cond do
            c == 45 ->
              t2 = true
              t2
            c == 42 ->
              t2 = true
              t2
            true ->
              t2 = c == 43
              t2
          end
          t1 = if t2 do
            if TemperCore.String.has_index(s, after_) do
              t1 = Temper.MarginaliaCore.isRegexSpace(TemperCore.String.get(s, after_))
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
            return = true
            return
          else
            i = TemperCore.String.begin()
            digits = 0
            ex_loop_222 = fn ex_loop_222, digits, i ->
              if true do
                _t4 = nil
                t4 = if TemperCore.String.has_index(s, i) do
                  if TemperCore.String.get(s, i) >= 48 do
                    t4 = TemperCore.String.get(s, i) <= 57
                    t4
                  else
                    t4 = false
                    t4
                  end
                else
                  t4 = false
                  t4
                end
                if not t4 do
                  {digits, i}
                else
                  digits = TemperCore.int32(digits + 1)
                  i = TemperCore.String.next(s, i)
                  ex_loop_222.(ex_loop_222, digits, i)
                end
              else
                {digits, i}
              end
            end
            {digits, i} = ex_loop_222.(ex_loop_222, digits, i)
            _t3 = nil
            t3 = cond do
              digits == 0 ->
                t3 = true
                t3
              not TemperCore.String.has_index(s, i) ->
                t3 = true
                t3
              TemperCore.String.get(s, i) != 46 ->
                t3 = TemperCore.String.get(s, i) != 41
                t3
              true ->
                t3 = false
                t3
            end
            if t3 do
              return = false
              return
            else
              next = TemperCore.String.next(s, i)
              if TemperCore.String.has_index(s, next) do
                throw({:temper_return, :ex_return_220, Temper.MarginaliaCore.isRegexSpace(TemperCore.String.get(s, next))})
              else
                throw({:temper_return, :ex_return_220, false})
              end
            end
          end
        end
      end
      return
    catch
      {:temper_return, :ex_return_220, ex_value_224} ->
        ex_value_224
    end
  end
  def isHtml__361(s) do
    try do
      _return = nil
      return = if true do
        _t1 = nil
        t1 = if not TemperCore.String.has_index(s, TemperCore.String.begin()) do
          t1 = true
          t1
        else
          t1 = TemperCore.String.get(s, TemperCore.String.begin()) != 60
          t1
        end
        if t1 do
          return = false
          return
        else
          next = TemperCore.String.next(s, TemperCore.String.begin())
          if not TemperCore.String.has_index(s, next) do
            return = false
            return
          else
            c = TemperCore.String.get(s, next)
            _t2 = nil
            t2 = if c >= 97 do
              t2 = c <= 122
              t2
            else
              t2 = false
              t2
            end
            if t2 do
              throw({:temper_return, :ex_return_225, true})
            else
              _t3 = nil
              t3 = if c >= 65 do
                t3 = c <= 90
                t3
              else
                t3 = false
                t3
              end
              cond do
                t3 ->
                  throw({:temper_return, :ex_return_225, true})
                c == 33 ->
                  throw({:temper_return, :ex_return_225, true})
                true ->
                  throw({:temper_return, :ex_return_225, c == 47})
              end
            end
          end
        end
      end
      return
    catch
      {:temper_return, :ex_return_225, ex_value_227} ->
        ex_value_227
    end
  end
  def isLoneLinkOrImage__362(block) do
    try do
      _return = nil
      return = if true do
        i = TemperCore.String.begin()
        _t1 = nil
        t1 = if TemperCore.String.has_index(block, i) do
          t1 = TemperCore.String.get(block, i) == 33
          t1
        else
          t1 = false
          t1
        end
        i = if t1 do
          i = TemperCore.String.next(block, i)
          i
        else
          i
        end
        _t2 = nil
        t2 = if not TemperCore.String.has_index(block, i) do
          t2 = true
          t2
        else
          t2 = TemperCore.String.get(block, i) != 91
          t2
        end
        if t2 do
          return = false
          return
        else
          i = TemperCore.String.next(block, i)
          ex_loop_230 = fn ex_loop_230, i ->
            if true do
              _t4 = nil
              t4 = if TemperCore.String.has_index(block, i) do
                t4 = TemperCore.String.get(block, i) != 93
                t4
              else
                t4 = false
                t4
              end
              if not t4 do
                i
              else
                i = TemperCore.String.next(block, i)
                ex_loop_230.(ex_loop_230, i)
              end
            else
              i
            end
          end
          i = ex_loop_230.(ex_loop_230, i)
          if not TemperCore.String.has_index(block, i) do
            return = false
            return
          else
            i = TemperCore.String.next(block, i)
            _t3 = nil
            t3 = if not TemperCore.String.has_index(block, i) do
              t3 = true
              t3
            else
              t3 = TemperCore.String.get(block, i) != 40
              t3
            end
            if t3 do
              return = false
              return
            else
              i = TemperCore.String.next(block, i)
              ex_loop_232 = fn ex_loop_232, i ->
                if true do
                  _t5 = nil
                  t5 = if TemperCore.String.has_index(block, i) do
                    t5 = TemperCore.String.get(block, i) != 41
                    t5
                  else
                    t5 = false
                    t5
                  end
                  if not t5 do
                    i
                  else
                    i = TemperCore.String.next(block, i)
                    ex_loop_232.(ex_loop_232, i)
                  end
                else
                  i
                end
              end
              i = ex_loop_232.(ex_loop_232, i)
              if not TemperCore.String.has_index(block, i) do
                return = false
                return
              else
                i = TemperCore.String.next(block, i)
                ex_loop_234 = fn ex_loop_234, i ->
                  if true do
                    _t6 = nil
                    t6 = if TemperCore.String.has_index(block, i) do
                      t6 = Temper.MarginaliaCore.isRegexSpace(TemperCore.String.get(block, i))
                      t6
                    else
                      t6 = false
                      t6
                    end
                    if not t6 do
                      i
                    else
                      i = TemperCore.String.next(block, i)
                      ex_loop_234.(ex_loop_234, i)
                    end
                  else
                    i
                  end
                end
                i = ex_loop_234.(ex_loop_234, i)
                throw({:temper_return, :ex_return_228, not TemperCore.String.has_index(block, i)})
              end
            end
          end
        end
      end
      return
    catch
      {:temper_return, :ex_return_228, ex_value_236} ->
        ex_value_236
    end
  end
  def isRule__363(s) do
    try do
      _return = nil
      return = if true do
        if not TemperCore.String.has_index(s, TemperCore.String.begin()) do
          return = false
          return
        else
          mark = TemperCore.String.get(s, TemperCore.String.begin())
          _t1 = nil
          t1 = if mark != 45 do
            if mark != 42 do
              t1 = mark != 95
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
            return = false
            return
          else
            i = TemperCore.String.begin()
            count = 0
            ex_loop_239 = fn ex_loop_239, count, i ->
              if true do
                _t2 = nil
                t2 = if TemperCore.String.has_index(s, i) do
                  t2 = TemperCore.String.get(s, i) == mark
                  t2
                else
                  t2 = false
                  t2
                end
                if not t2 do
                  {count, i}
                else
                  count = TemperCore.int32(count + 1)
                  i = TemperCore.String.next(s, i)
                  ex_loop_239.(ex_loop_239, count, i)
                end
              else
                {count, i}
              end
            end
            {count, i} = ex_loop_239.(ex_loop_239, count, i)
            ex_loop_241 = fn ex_loop_241, i ->
              if true do
                _t3 = nil
                t3 = if TemperCore.String.has_index(s, i) do
                  t3 = Temper.MarginaliaCore.isRegexSpace(TemperCore.String.get(s, i))
                  t3
                else
                  t3 = false
                  t3
                end
                if not t3 do
                  i
                else
                  i = TemperCore.String.next(s, i)
                  ex_loop_241.(ex_loop_241, i)
                end
              else
                i
              end
            end
            i = ex_loop_241.(ex_loop_241, i)
            if count >= 3 do
              throw({:temper_return, :ex_return_237, not TemperCore.String.has_index(s, i)})
            else
              throw({:temper_return, :ex_return_237, false})
            end
          end
        end
      end
      return
    catch
      {:temper_return, :ex_return_237, ex_value_243} ->
        ex_value_243
    end
  end
  def isProse__353(block) do
    try do
      _return = nil
      return = if true do
        lines = TemperCore.String.split(block, "\n")
        first = Temper.MarginaliaCore.trimLeading(TemperCore.List.get(lines, 0))
        _second = nil
        second = if TemperCore.List.length(lines) > 1 do
          second = Temper.MarginaliaCore.trim(TemperCore.List.get(lines, 1))
          second
        else
          second = ""
          second
        end
        cond do
          Temper.MarginaliaCore.isUnderline__354(second) ->
            return = false
            return
          Temper.MarginaliaCore.isTableDelimiter__356(second) ->
            return = false
            return
          true ->
            _t = nil
            t = if Temper.MarginaliaCore.startsWith(first, "```") do
              t = true
              t
            else
              t = Temper.MarginaliaCore.startsWith(first, "~~~")
              t
            end
            cond do
              t ->
                return = false
                return
              Temper.MarginaliaCore.isAtxHeading__358(first) ->
                return = false
                return
              Temper.MarginaliaCore.isIndentedCode__359(block) ->
                return = false
                return
              Temper.MarginaliaCore.isListItem__360(first) ->
                return = false
                return
              Temper.MarginaliaCore.isHtml__361(first) ->
                return = false
                return
              Temper.MarginaliaCore.isLoneLinkOrImage__362(block) ->
                return = false
                return
              Temper.MarginaliaCore.isRule__363(first) ->
                return = false
                return
              true ->
                allPiped = true
                k = 0
                ex_loop_246 = fn ex_loop_246, allPiped, k ->
                  if k < TemperCore.List.length(lines) do
                    allPiped = if not Temper.MarginaliaCore.startsWith(Temper.MarginaliaCore.trimLeading(TemperCore.List.get(lines, k)), "|") do
                      allPiped = false
                      allPiped
                    else
                      allPiped
                    end
                    k = TemperCore.int32(k + 1)
                    ex_loop_246.(ex_loop_246, allPiped, k)
                  else
                    {allPiped, k}
                  end
                end
                {allPiped, _k} = ex_loop_246.(ex_loop_246, allPiped, k)
                throw({:temper_return, :ex_return_244, not allPiped})
            end
        end
      end
      return
    catch
      {:temper_return, :ex_return_244, ex_value_248} ->
        ex_value_248
    end
  end
  def isQuoted__345(block) do
    i = TemperCore.String.begin()
    ex_loop_250 = fn ex_loop_250, i ->
      if true do
        _t = nil
        t = if TemperCore.String.has_index(block, i) do
          t = Temper.MarginaliaCore.isRegexSpace(TemperCore.String.get(block, i))
          t
        else
          t = false
          t
        end
        if not t do
          i
        else
          i = TemperCore.String.next(block, i)
          ex_loop_250.(ex_loop_250, i)
        end
      else
        i
      end
    end
    i = ex_loop_250.(ex_loop_250, i)
    if TemperCore.String.has_index(block, i) do
      TemperCore.String.get(block, i) == 62
    else
      false
    end
  end
  def stripQuoteMark__344(line) do
    try do
      _return = nil
      return = if true do
        i = TemperCore.String.begin()
        ex_loop_254 = fn ex_loop_254, i ->
          if true do
            _t3 = nil
            t3 = if TemperCore.String.has_index(line, i) do
              t3 = Temper.MarginaliaCore.isRegexSpace(TemperCore.String.get(line, i))
              t3
            else
              t3 = false
              t3
            end
            if not t3 do
              i
            else
              i = TemperCore.String.next(line, i)
              ex_loop_254.(ex_loop_254, i)
            end
          else
            i
          end
        end
        i = ex_loop_254.(ex_loop_254, i)
        _t1 = nil
        t1 = if not TemperCore.String.has_index(line, i) do
          t1 = true
          t1
        else
          t1 = TemperCore.String.get(line, i) != 62
          t1
        end
        if t1 do
          return = line
          return
        else
          i = TemperCore.String.next(line, i)
          _t2 = nil
          t2 = if TemperCore.String.has_index(line, i) do
            t2 = Temper.MarginaliaCore.isRegexSpace(TemperCore.String.get(line, i))
            t2
          else
            t2 = false
            t2
          end
          i = if t2 do
            i = TemperCore.String.next(line, i)
            i
          else
            i
          end
          throw({:temper_return, :ex_return_252, TemperCore.String.slice(line, i, TemperCore.String.end_of(line))})
        end
      end
      return
    catch
      {:temper_return, :ex_return_252, ex_value_256} ->
        ex_value_256
    end
  end
  def reflowQuote__343(block) do
    lines = TemperCore.String.split(block, "\n")
    fn_1 = fn l1 ->
      Temper.MarginaliaCore.stripQuoteMark__344(l1)
    end
    stripped = Temper.MarginaliaCore.joinWith(TemperCore.List.map(lines, fn_1), "\n")
    back = TemperCore.String.split(Temper.MarginaliaCore.reflow(stripped), "\n")
    fn_2 = fn l2 ->
      if TemperCore.String.is_empty(l2) do
        ">"
      else
        "> " <> l2
      end
    end
    Temper.MarginaliaCore.joinWith(TemperCore.List.map(back, fn_2), "\n")
  end
  def breakSentences__348(text) do
    out = TemperCore.StringBuilder.new()
    i = TemperCore.String.begin()
    ex_loop_261 = fn ex_loop_261, i ->
      if TemperCore.String.has_index(text, i) do
        ex_step_275 = try do
          cp = TemperCore.String.get(text, i)
          _t1 = nil
          t1 = cond do
            cp == 46 ->
              t1 = true
              t1
            cp == 33 ->
              t1 = true
              t1
            true ->
              t1 = cp == 63
              t1
          end
          i = if t1 do
            j = TemperCore.String.next(text, i)
            ex_loop_269 = fn ex_loop_269, j ->
              if true do
                _t3 = nil
                t3 = if TemperCore.String.has_index(text, j) do
                  t3 = Temper.MarginaliaCore.isCloser__341(TemperCore.String.get(text, j))
                  t3
                else
                  t3 = false
                  t3
                end
                if not t3 do
                  j
                else
                  j = TemperCore.String.next(text, j)
                  ex_loop_269.(ex_loop_269, j)
                end
              else
                j
              end
            end
            j = ex_loop_269.(ex_loop_269, j)
            k = j
            ex_loop_271 = fn ex_loop_271, k ->
              if true do
                _t4 = nil
                t4 = if TemperCore.String.has_index(text, k) do
                  t4 = Temper.MarginaliaCore.isUnicodeSpace(TemperCore.String.get(text, k))
                  t4
                else
                  t4 = false
                  t4
                end
                if not t4 do
                  k
                else
                  k = TemperCore.String.next(text, k)
                  ex_loop_271.(ex_loop_271, k)
                end
              else
                k
              end
            end
            k = ex_loop_271.(ex_loop_271, k)
            m = k
            ex_loop_273 = fn ex_loop_273, m ->
              if true do
                _t5 = nil
                t5 = if TemperCore.String.has_index(text, m) do
                  t5 = Temper.MarginaliaCore.isOpener__342(TemperCore.String.get(text, m))
                  t5
                else
                  t5 = false
                  t5
                end
                if not t5 do
                  m
                else
                  m = TemperCore.String.next(text, m)
                  ex_loop_273.(ex_loop_273, m)
                end
              else
                m
              end
            end
            m = ex_loop_273.(ex_loop_273, m)
            _t2 = nil
            t2 = if k > j do
              if TemperCore.String.has_index(text, m) do
                if Temper.MarginaliaCore.isUnicodeUpper(TemperCore.String.get(text, m)) do
                  t2 = true
                  t2
                else
                  t2 = Temper.MarginaliaCore.isUnicodeDigit(TemperCore.String.get(text, m))
                  t2
                end
              else
                t2 = false
                t2
              end
            else
              t2 = false
              t2
            end
            if t2 do
              TemperCore.StringBuilder.append(out, TemperCore.String.slice(text, i, j))
              TemperCore.StringBuilder.append(out, "\n")
              i = k
              throw({:temper_continue, :ex_loop_262, i})
            else
              i
            end
          else
            i
          end
          try do
            TemperCore.StringBuilder.append_code_point(out, cp)
            nil
          rescue
            _ in TemperCore.Bubble ->
              raise(TemperCore.Bubble)
          end
          i = TemperCore.String.next(text, i)
          {:temper_next, i}
        catch
          {:temper_continue, :ex_loop_262, ex_vars_276} ->
            {:temper_next, ex_vars_276}
          {:temper_break, :ex_loop_262, ex_vars_276} ->
            {:temper_done, ex_vars_276}
        end
        case ex_step_275 do
          {:temper_next, i} ->
            ex_loop_261.(ex_loop_261, i)
          {:temper_done, ex_vars_276} ->
            ex_vars_276
        end
      else
        i
      end
    end
    _i = ex_loop_261.(ex_loop_261, i)
    TemperCore.StringBuilder.to_string(out)
  end
  def startsAWord__352(line, at) do
    if at <= TemperCore.String.begin() do
      true
    else
      Temper.MarginaliaCore.isUnicodeSpace(TemperCore.String.get(line, TemperCore.String.prev(line, at)))
    end
  end
  def abbreviationAt__351(line, dot, word) do
    try do
      _return = nil
      return = if true do
        if not Temper.MarginaliaCore.endsWithAt(line, dot, word) do
          return = false
          return
        else
          start = dot
          k = 0
          ex_loop_280 = fn ex_loop_280, k, start ->
            if k < TemperCore.String.count_between(word, TemperCore.String.begin(), TemperCore.String.end_of(word)) do
              start = TemperCore.String.prev(line, start)
              k = TemperCore.int32(k + 1)
              ex_loop_280.(ex_loop_280, k, start)
            else
              {k, start}
            end
          end
          {_k, start} = ex_loop_280.(ex_loop_280, k, start)
          throw({:temper_return, :ex_return_278, Temper.MarginaliaCore.startsAWord__352(line, start)})
        end
      end
      return
    catch
      {:temper_return, :ex_return_278, ex_value_282} ->
        ex_value_282
    end
  end
  def endsOnAbbreviation__350(line) do
    try do
      return = nil
      return = try do
        e = TemperCore.String.end_of(line)
        ex_loop_285 = fn ex_loop_285, e ->
          if true do
            _t2 = nil
            t2 = if e > TemperCore.String.begin() do
              t2 = Temper.MarginaliaCore.isCloser__341(TemperCore.String.get(line, TemperCore.String.prev(line, e)))
              t2
            else
              t2 = false
              t2
            end
            if not t2 do
              e
            else
              e = TemperCore.String.prev(line, e)
              ex_loop_285.(ex_loop_285, e)
            end
          else
            e
          end
        end
        e = ex_loop_285.(ex_loop_285, e)
        _t1 = nil
        t1 = if e <= TemperCore.String.begin() do
          t1 = true
          t1
        else
          t1 = TemperCore.String.get(line, TemperCore.String.prev(line, e)) != 46
          t1
        end
        if t1 do
          return = false
          return
        else
          dot = TemperCore.String.prev(line, e)
          k = 0
          ex_loop_287 = fn ex_loop_287, k, return ->
            if k < TemperCore.List.length(TemperCore.Global.get(:"Temper.MarginaliaCore.abbreviations__374")) do
              if Temper.MarginaliaCore.abbreviationAt__351(line, dot, TemperCore.List.get(TemperCore.Global.get(:"Temper.MarginaliaCore.abbreviations__374"), k)) do
                return = true
                throw({:temper_break, :ex_block_284, return})
              else
                k = TemperCore.int32(k + 1)
                ex_loop_287.(ex_loop_287, k, return)
              end
            else
              {k, return}
            end
          end
          {_k, return} = ex_loop_287.(ex_loop_287, k, return)
          _return = if dot > TemperCore.String.begin() do
            c = TemperCore.String.prev(line, dot)
            cp = TemperCore.String.get(line, c)
            _t3 = nil
            t3 = if cp >= 65 do
              if cp <= 90 do
                t3 = Temper.MarginaliaCore.startsAWord__352(line, c)
                t3
              else
                t3 = false
                t3
              end
            else
              t3 = false
              t3
            end
            if t3 do
              return = true
              throw({:temper_break, :ex_block_284, return})
            else
              return
            end
          else
            return
          end
          throw({:temper_return, :ex_return_283, false})
        end
      catch
        {:temper_break, :ex_block_284, ex_vars_289} ->
          ex_vars_289
      end
      return
    catch
      {:temper_return, :ex_return_283, ex_value_290} ->
        ex_value_290
    end
  end
  def splitSentences__349(joined) do
    lines = TemperCore.String.split(Temper.MarginaliaCore.breakSentences__348(joined), "\n")
    out = TemperCore.List.builder()
    k = 0
    ex_loop_292 = fn ex_loop_292, k ->
      if k < TemperCore.List.length(lines) do
        n = TemperCore.List.length(out)
        _t = nil
        t = if n > 0 do
          t = Temper.MarginaliaCore.endsOnAbbreviation__350(TemperCore.List.get(out, TemperCore.int32(n - 1)))
          t
        else
          t = false
          t
        end
        if t do
          TemperCore.List.set(out, TemperCore.int32(n - 1), TemperCore.List.get(out, TemperCore.int32(n - 1)) <> " " <> TemperCore.List.get(lines, k))
          nil
        else
          TemperCore.List.add(out, TemperCore.List.get(lines, k))
          nil
        end
        k = TemperCore.int32(k + 1)
        ex_loop_292.(ex_loop_292, k)
      else
        k
      end
    end
    _k = ex_loop_292.(ex_loop_292, k)
    Temper.MarginaliaCore.joinWith(TemperCore.List.to_list(out), "\n")
  end
  def squeezeBlanks__347(text) do
    out = TemperCore.StringBuilder.new()
    inBlank = false
    i = TemperCore.String.begin()
    ex_loop_295 = fn ex_loop_295, i, inBlank ->
      if TemperCore.String.has_index(text, i) do
        cp = TemperCore.String.get(text, i)
        _t = nil
        t = if cp == 32 do
          t = true
          t
        else
          t = cp == 9
          t
        end
        inBlank = if t do
          if not inBlank do
            TemperCore.StringBuilder.append(out, " ")
            nil
          else
            nil
          end
          inBlank = true
          inBlank
        else
          inBlank = false
          try do
            TemperCore.StringBuilder.append_code_point(out, cp)
            nil
          rescue
            _ in TemperCore.Bubble ->
              raise(TemperCore.Bubble)
          end
          inBlank
        end
        i = TemperCore.String.next(text, i)
        ex_loop_295.(ex_loop_295, i, inBlank)
      else
        {i, inBlank}
      end
    end
    {_i, _inBlank} = ex_loop_295.(ex_loop_295, i, inBlank)
    TemperCore.StringBuilder.to_string(out)
  end
  def unwrap__346(block) do
    lines = TemperCore.String.split(block, "\n")
    last = TemperCore.int32(TemperCore.List.length(lines) - 1)
    pieces = TemperCore.List.builder()
    k = 0
    ex_loop_298 = fn ex_loop_298, k ->
      if k <= last do
        line = TemperCore.List.get(lines, k)
        b = TemperCore.String.begin()
        e = TemperCore.String.end_of(line)
        b = if k > 0 do
          ex_loop_300 = fn ex_loop_300, b ->
            if true do
              _t1 = nil
              t1 = if TemperCore.String.has_index(line, b) do
                t1 = Temper.MarginaliaCore.isRegexSpace(TemperCore.String.get(line, b))
                t1
              else
                t1 = false
                t1
              end
              if not t1 do
                b
              else
                b = TemperCore.String.next(line, b)
                ex_loop_300.(ex_loop_300, b)
              end
            else
              b
            end
          end
          b = ex_loop_300.(ex_loop_300, b)
          b
        else
          b
        end
        e = if k < last do
          ex_loop_302 = fn ex_loop_302, e ->
            if true do
              _t2 = nil
              t2 = if e > b do
                t2 = Temper.MarginaliaCore.isRegexSpace(TemperCore.String.get(line, TemperCore.String.prev(line, e)))
                t2
              else
                t2 = false
                t2
              end
              if not t2 do
                e
              else
                e = TemperCore.String.prev(line, e)
                ex_loop_302.(ex_loop_302, e)
              end
            else
              e
            end
          end
          e = ex_loop_302.(ex_loop_302, e)
          e
        else
          e
        end
        TemperCore.List.add(pieces, TemperCore.String.slice(line, b, e))
        k = TemperCore.int32(k + 1)
        ex_loop_298.(ex_loop_298, k)
      else
        k
      end
    end
    _k = ex_loop_298.(ex_loop_298, k)
    Temper.MarginaliaCore.joinWith(TemperCore.List.to_list(pieces), " ")
  end
  def reflowBlock(block) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      try do
        _return = nil
        return = if true do
          cond do
            not Temper.MarginaliaCore.isProse__353(block) ->
              return = block
              return
            Temper.MarginaliaCore.isQuoted__345(block) ->
              return = Temper.MarginaliaCore.reflowQuote__343(block)
              return
            true ->
              throw({:temper_return, :ex_return_304, Temper.MarginaliaCore.splitSentences__349(Temper.MarginaliaCore.trim(Temper.MarginaliaCore.squeezeBlanks__347(Temper.MarginaliaCore.unwrap__346(block))))})
          end
        end
        return
      catch
        {:temper_return, :ex_return_304, ex_value_306} ->
          ex_value_306
      end
    end)
  end
  def wordsOf(text) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      out = TemperCore.List.builder()
      i = TemperCore.String.begin()
      ex_loop_308 = fn ex_loop_308, i ->
        if true do
          _t1 = nil
          t1 = if TemperCore.String.has_index(text, i) do
            t1 = Temper.MarginaliaCore.isRegexSpace(TemperCore.String.get(text, i))
            t1
          else
            t1 = false
            t1
          end
          if not t1 do
            i
          else
            i = TemperCore.String.next(text, i)
            ex_loop_308.(ex_loop_308, i)
          end
        else
          i
        end
      end
      i = ex_loop_308.(ex_loop_308, i)
      ex_loop_310 = fn ex_loop_310, i ->
        if TemperCore.String.has_index(text, i) do
          start = i
          ex_loop_312 = fn ex_loop_312, i ->
            if true do
              _t2 = nil
              t2 = if TemperCore.String.has_index(text, i) do
                t2 = not Temper.MarginaliaCore.isRegexSpace(TemperCore.String.get(text, i))
                t2
              else
                t2 = false
                t2
              end
              if not t2 do
                i
              else
                i = TemperCore.String.next(text, i)
                ex_loop_312.(ex_loop_312, i)
              end
            else
              i
            end
          end
          i = ex_loop_312.(ex_loop_312, i)
          ex_loop_314 = fn ex_loop_314, i ->
            if true do
              _t3 = nil
              t3 = if TemperCore.String.has_index(text, i) do
                t3 = Temper.MarginaliaCore.isRegexSpace(TemperCore.String.get(text, i))
                t3
              else
                t3 = false
                t3
              end
              if not t3 do
                i
              else
                i = TemperCore.String.next(text, i)
                ex_loop_314.(ex_loop_314, i)
              end
            else
              i
            end
          end
          i = ex_loop_314.(ex_loop_314, i)
          TemperCore.List.add(out, TemperCore.String.slice(text, start, i))
          ex_loop_310.(ex_loop_310, i)
        else
          i
        end
      end
      _i = ex_loop_310.(ex_loop_310, i)
      TemperCore.List.to_list(out)
    end)
  end
  def distinct__365(words) do
    set = TemperCore.Map.builder()
    k = 0
    ex_loop_317 = fn ex_loop_317, k ->
      if k < TemperCore.List.length(words) do
        TemperCore.Map.set(set, TemperCore.List.get(words, k), true)
        k = TemperCore.int32(k + 1)
        ex_loop_317.(ex_loop_317, k)
      else
        k
      end
    end
    _k = ex_loop_317.(ex_loop_317, k)
    set
  end
  def unrelated__364(ak, bk) do
    try do
      _return = nil
      return = if true do
        _t = nil
        t = if TemperCore.List.length(ak) < 200 do
          t = true
          t
        else
          t = TemperCore.List.length(bk) < 200
          t
        end
        if t do
          return = false
          return
        else
          a = TemperCore.Map.to_map(Temper.MarginaliaCore.distinct__365(ak))
          b = TemperCore.Map.to_map(Temper.MarginaliaCore.distinct__365(bk))
          bKeys = TemperCore.Map.keys(b)
          shared = 0
          k = 0
          ex_loop_321 = fn ex_loop_321, k, shared ->
            if k < TemperCore.List.length(bKeys) do
              shared = if TemperCore.Map.has(a, TemperCore.List.get(bKeys, k)) do
                shared = TemperCore.int32(shared + 1)
                shared
              else
                shared
              end
              k = TemperCore.int32(k + 1)
              ex_loop_321.(ex_loop_321, k, shared)
            else
              {k, shared}
            end
          end
          {_k, shared} = ex_loop_321.(ex_loop_321, k, shared)
          aSize = TemperCore.List.length(TemperCore.Map.keys(a))
          bSize = TemperCore.List.length(bKeys)
          _smaller = nil
          smaller = if aSize < bSize do
            smaller = aSize
            smaller
          else
            smaller = bSize
            smaller
          end
          throw({:temper_return, :ex_return_319, TemperCore.Float.lt(TemperCore.int_to_float(shared), TemperCore.Float.mul(0.05, TemperCore.int_to_float(smaller)))})
        end
      end
      return
    catch
      {:temper_return, :ex_return_319, ex_value_323} ->
        ex_value_323
    end
  end
  def attach__372(script, aw, bw, parts) do
    ai = 0
    bi = 0
    c = 0
    ex_loop_325 = fn ex_loop_325, ai, bi, c ->
      if c < TemperCore.List.length(script) do
        chunk = TemperCore.List.get(script, c)
        count = TemperCore.List.length(Temper.MarginaliaCore.Chunk.get_words(chunk))
        k = 0
        ex_loop_327 = fn ex_loop_327, ai, bi, k ->
          if k < count do
            {ai, bi} = cond do
              Temper.MarginaliaCore.Chunk.get_kind(chunk) == 0 ->
                ta = TemperCore.List.get(aw, ai)
                tb = TemperCore.List.get(bw, bi)
                cut = Temper.MarginaliaCore.trailingStart(tb)
                _token = nil
                token = if cut == TemperCore.String.end_of(tb) do
                  token = Temper.MarginaliaCore.trim(tb) <> TemperCore.String.slice(ta, Temper.MarginaliaCore.trailingStart(ta), TemperCore.String.end_of(ta))
                  token
                else
                  token = tb
                  token
                end
                TemperCore.List.add(parts, Temper.MarginaliaCore.Part.new("same", token))
                ai = TemperCore.int32(ai + 1)
                bi = TemperCore.int32(bi + 1)
                {ai, bi}
              Temper.MarginaliaCore.Chunk.get_kind(chunk) == 1 ->
                TemperCore.List.add(parts, Temper.MarginaliaCore.Part.new("del", TemperCore.List.get(aw, ai)))
                ai = TemperCore.int32(ai + 1)
                {ai, bi}
              true ->
                TemperCore.List.add(parts, Temper.MarginaliaCore.Part.new("ins", TemperCore.List.get(bw, bi)))
                bi = TemperCore.int32(bi + 1)
                {ai, bi}
            end
            k = TemperCore.int32(k + 1)
            ex_loop_327.(ex_loop_327, ai, bi, k)
          else
            {ai, bi, k}
          end
        end
        {ai, bi, _k} = ex_loop_327.(ex_loop_327, ai, bi, k)
        c = TemperCore.int32(c + 1)
        ex_loop_325.(ex_loop_325, ai, bi, c)
      else
        {ai, bi, c}
      end
    end
    {_ai, _bi, _c} = ex_loop_325.(ex_loop_325, ai, bi, c)
    nil
  end
  def moveDown__367(p, a) do
    if Temper.MarginaliaCore.Path.get_i(p) < TemperCore.List.length(a) do
      Temper.MarginaliaCore.Path.new(TemperCore.int32(Temper.MarginaliaCore.Path.get_y(p) + 1), TemperCore.int32(Temper.MarginaliaCore.Path.get_i(p) + 1), Temper.MarginaliaCore.Path.get_j(p), Temper.MarginaliaCore.Edit.new(1, TemperCore.List.get(a, Temper.MarginaliaCore.Path.get_i(p)), Temper.MarginaliaCore.Path.get_edits(p)))
    else
      Temper.MarginaliaCore.Path.new(TemperCore.int32(Temper.MarginaliaCore.Path.get_y(p) + 1), Temper.MarginaliaCore.Path.get_i(p), Temper.MarginaliaCore.Path.get_j(p), Temper.MarginaliaCore.Path.get_edits(p))
    end
  end
  def moveRight__366(p, b) do
    if Temper.MarginaliaCore.Path.get_j(p) < TemperCore.List.length(b) do
      Temper.MarginaliaCore.Path.new(Temper.MarginaliaCore.Path.get_y(p), Temper.MarginaliaCore.Path.get_i(p), TemperCore.int32(Temper.MarginaliaCore.Path.get_j(p) + 1), Temper.MarginaliaCore.Edit.new(2, TemperCore.List.get(b, Temper.MarginaliaCore.Path.get_j(p)), Temper.MarginaliaCore.Path.get_edits(p)))
    else
      p
    end
  end
  def followSnake__368(p, a, b) do
    y = Temper.MarginaliaCore.Path.get_y(p)
    i = Temper.MarginaliaCore.Path.get_i(p)
    j = Temper.MarginaliaCore.Path.get_j(p)
    edits = Temper.MarginaliaCore.Path.get_edits(p)
    ex_loop_332 = fn ex_loop_332, edits, i, j, y ->
      if true do
        _t = nil
        t = if i < TemperCore.List.length(a) do
          if j < TemperCore.List.length(b) do
            t = TemperCore.List.get(a, i) == TemperCore.List.get(b, j)
            t
          else
            t = false
            t
          end
        else
          t = false
          t
        end
        if not t do
          {edits, i, j, y}
        else
          edits = Temper.MarginaliaCore.Edit.new(0, TemperCore.List.get(a, i), edits)
          y = TemperCore.int32(y + 1)
          i = TemperCore.int32(i + 1)
          j = TemperCore.int32(j + 1)
          ex_loop_332.(ex_loop_332, edits, i, j, y)
        end
      else
        {edits, i, j, y}
      end
    end
    {edits, i, j, y} = ex_loop_332.(ex_loop_332, edits, i, j, y)
    Temper.MarginaliaCore.Path.new(y, i, j, edits)
  end
  def sameWords__371(x, y) do
    try do
      return = nil
      return = try do
        if TemperCore.List.length(x) != TemperCore.List.length(y) do
          return = false
          return
        else
          k = 0
          ex_loop_336 = fn ex_loop_336, k, return ->
            if k < TemperCore.List.length(x) do
              if TemperCore.List.get(x, k) != TemperCore.List.get(y, k) do
                return = false
                throw({:temper_break, :ex_block_335, return})
              else
                k = TemperCore.int32(k + 1)
                ex_loop_336.(ex_loop_336, k, return)
              end
            else
              {k, return}
            end
          end
          {_k, _return} = ex_loop_336.(ex_loop_336, k, return)
          throw({:temper_return, :ex_return_334, true})
        end
      catch
        {:temper_break, :ex_block_335, ex_vars_338} ->
          ex_vars_338
      end
      return
    catch
      {:temper_return, :ex_return_334, ex_value_339} ->
        ex_value_339
    end
  end
  def compact__370(edits) do
    out = TemperCore.List.builder()
    e = edits
    ex_loop_341 = fn ex_loop_341, e ->
      if not (e === nil) do
        edit = nil
        edit = try do
          if e === nil do
            raise(TemperCore.Bubble)
          else
            edit = e
            edit
          end
        rescue
          _ in TemperCore.Bubble ->
            raise(TemperCore.Panic)
            edit
        end
        n = TemperCore.List.length(out)
        _t1 = nil
        t1 = if n > 0 do
          t1 = Temper.MarginaliaCore.Chunk.get_kind(TemperCore.List.get(out, TemperCore.int32(n - 1))) == Temper.MarginaliaCore.Edit.get_kind(edit)
          t1
        else
          t1 = false
          t1
        end
        if t1 do
          TemperCore.List.add(Temper.MarginaliaCore.Chunk.get_words(TemperCore.List.get(out, TemperCore.int32(n - 1))), Temper.MarginaliaCore.Edit.get_word(edit))
          e = Temper.MarginaliaCore.Edit.get_before(edit)
          ex_loop_341.(ex_loop_341, e)
        else
          _t2 = nil
          t2 = if n >= 3 do
            if Temper.MarginaliaCore.Chunk.get_kind(TemperCore.List.get(out, TemperCore.int32(n - 1))) == 0 do
              if Temper.MarginaliaCore.Chunk.get_kind(TemperCore.List.get(out, TemperCore.int32(n - 2))) == 2 do
                if Temper.MarginaliaCore.Chunk.get_kind(TemperCore.List.get(out, TemperCore.int32(n - 3))) == 0 do
                  t2 = Temper.MarginaliaCore.sameWords__371(Temper.MarginaliaCore.Chunk.get_words(TemperCore.List.get(out, TemperCore.int32(n - 1))), Temper.MarginaliaCore.Chunk.get_words(TemperCore.List.get(out, TemperCore.int32(n - 2))))
                  t2
                else
                  t2 = false
                  t2
                end
              else
                t2 = false
                t2
              end
            else
              t2 = false
              t2
            end
          else
            t2 = false
            t2
          end
          if t2 do
            x = TemperCore.List.remove_last(out)
            ins = TemperCore.List.remove_last(out)
            y = TemperCore.List.remove_last(out)
            merged = TemperCore.List.builder()
            TemperCore.List.add_all(merged, Temper.MarginaliaCore.Chunk.get_words(y))
            TemperCore.List.add_all(merged, Temper.MarginaliaCore.Chunk.get_words(x))
            TemperCore.List.add(out, Temper.MarginaliaCore.Chunk.new(0, merged))
            TemperCore.List.add(out, ins)
            ex_loop_341.(ex_loop_341, e)
          else
            words = TemperCore.List.builder()
            TemperCore.List.add(words, Temper.MarginaliaCore.Edit.get_word(edit))
            TemperCore.List.add(out, Temper.MarginaliaCore.Chunk.new(Temper.MarginaliaCore.Edit.get_kind(edit), words))
            e = Temper.MarginaliaCore.Edit.get_before(edit)
            ex_loop_341.(ex_loop_341, e)
          end
        end
      else
        e
      end
    end
    _e = ex_loop_341.(ex_loop_341, e)
    TemperCore.List.reverse(out)
    k = 0
    ex_loop_343 = fn ex_loop_343, k ->
      if k < TemperCore.List.length(out) do
        TemperCore.List.reverse(Temper.MarginaliaCore.Chunk.get_words(TemperCore.List.get(out, k)))
        k = TemperCore.int32(k + 1)
        ex_loop_343.(ex_loop_343, k)
      else
        k
      end
    end
    _k = ex_loop_343.(ex_loop_343, k)
    TemperCore.List.to_list(out)
  end
  def myers__369(a, b) do
    return = nil
    return = try do
      paths = %TemperCore.Vec{t: {Temper.MarginaliaCore.Path.new(0, 0, 0, nil)}}
      envelope = 0
      ex_loop_347 = fn ex_loop_347, envelope, paths, return ->
        if true do
          next = TemperCore.List.builder()
          at = 0
          diag = TemperCore.int32(-envelope)
          ex_loop_349 = fn ex_loop_349, at, diag, return ->
            if diag <= envelope do
              left = TemperCore.int32(TemperCore.List.length(paths) - at)
              path = TemperCore.List.get(paths, at)
              _t1 = nil
              t1 = if diag == 0 do
                t1 = envelope == 0
                t1
              else
                t1 = false
                t1
              end
              {at, path} = cond do
                t1 ->
                  at = TemperCore.int32(at + 1)
                  {at, path}
                diag == TemperCore.int32(-envelope) ->
                  path = Temper.MarginaliaCore.moveDown__367(path, a)
                  {at, path}
                true ->
                  _t3 = nil
                  t3 = if diag == envelope do
                    t3 = left == 1
                    t3
                  else
                    t3 = false
                    t3
                  end
                  if t3 do
                    path = Temper.MarginaliaCore.moveRight__366(path, b)
                    at = TemperCore.int32(at + 1)
                    {at, path}
                  else
                    _t4 = nil
                    second = TemperCore.List.get(paths, TemperCore.int32(at + 1))
                    t4 = if Temper.MarginaliaCore.Path.get_y(path) > Temper.MarginaliaCore.Path.get_y(second) do
                      t4 = Temper.MarginaliaCore.moveRight__366(path, b)
                      t4
                    else
                      t4 = Temper.MarginaliaCore.moveDown__367(second, a)
                      t4
                    end
                    path = t4
                    at = TemperCore.int32(at + 1)
                    {at, path}
                  end
              end
              path = Temper.MarginaliaCore.followSnake__368(path, a, b)
              _t2 = nil
              t2 = if Temper.MarginaliaCore.Path.get_i(path) == TemperCore.List.length(a) do
                t2 = Temper.MarginaliaCore.Path.get_j(path) == TemperCore.List.length(b)
                t2
              else
                t2 = false
                t2
              end
              if t2 do
                return = Temper.MarginaliaCore.compact__370(Temper.MarginaliaCore.Path.get_edits(path))
                throw({:temper_break, :ex_block_346, return})
              else
                TemperCore.List.add(next, path)
                diag = TemperCore.int32(diag + 2)
                ex_loop_349.(ex_loop_349, at, diag, return)
              end
            else
              {at, diag, return}
            end
          end
          {_at, _diag, return} = ex_loop_349.(ex_loop_349, at, diag, return)
          paths = TemperCore.List.to_list(next)
          envelope = TemperCore.int32(envelope + 1)
          ex_loop_347.(ex_loop_347, envelope, paths, return)
        else
          {envelope, paths, return}
        end
      end
      {_envelope, _paths, return} = ex_loop_347.(ex_loop_347, envelope, paths, return)
      return
    catch
      {:temper_break, :ex_block_346, ex_vars_351} ->
        ex_vars_351
    end
    return
  end
  def merge__373(parts) do
    out = TemperCore.List.builder()
    k = 0
    ex_loop_353 = fn ex_loop_353, k ->
      if k < TemperCore.List.length(parts) do
        kind = Temper.MarginaliaCore.Part.get_kind(TemperCore.List.get(parts, k))
        text = TemperCore.StringBuilder.new()
        ex_loop_355 = fn ex_loop_355, k ->
          if true do
            _t = nil
            t = if k < TemperCore.List.length(parts) do
              t = Temper.MarginaliaCore.Part.get_kind(TemperCore.List.get(parts, k)) == kind
              t
            else
              t = false
              t
            end
            if not t do
              k
            else
              TemperCore.StringBuilder.append(text, Temper.MarginaliaCore.Part.get_text(TemperCore.List.get(parts, k)))
              k = TemperCore.int32(k + 1)
              ex_loop_355.(ex_loop_355, k)
            end
          else
            k
          end
        end
        k = ex_loop_355.(ex_loop_355, k)
        TemperCore.List.add(out, Temper.MarginaliaCore.Part.new(kind, TemperCore.StringBuilder.to_string(text)))
        ex_loop_353.(ex_loop_353, k)
      else
        k
      end
    end
    _k = ex_loop_353.(ex_loop_353, k)
    TemperCore.List.to_list(out)
  end
  def diff(a, b) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      aw = Temper.MarginaliaCore.wordsOf(a)
      bw = Temper.MarginaliaCore.wordsOf(b)
      fn_1 = fn w1 ->
        Temper.MarginaliaCore.trim(w1)
      end
      ak = TemperCore.List.map(aw, fn_1)
      fn_2 = fn w2 ->
        Temper.MarginaliaCore.trim(w2)
      end
      bk = TemperCore.List.map(bw, fn_2)
      parts = TemperCore.List.builder()
      if Temper.MarginaliaCore.unrelated__364(ak, bk) do
        k1 = 0
        ex_loop_360 = fn ex_loop_360, k1 ->
          if k1 < TemperCore.List.length(aw) do
            TemperCore.List.add(parts, Temper.MarginaliaCore.Part.new("del", TemperCore.List.get(aw, k1)))
            k1 = TemperCore.int32(k1 + 1)
            ex_loop_360.(ex_loop_360, k1)
          else
            k1
          end
        end
        _k1 = ex_loop_360.(ex_loop_360, k1)
        k2 = 0
        ex_loop_362 = fn ex_loop_362, k2 ->
          if k2 < TemperCore.List.length(bw) do
            TemperCore.List.add(parts, Temper.MarginaliaCore.Part.new("ins", TemperCore.List.get(bw, k2)))
            k2 = TemperCore.int32(k2 + 1)
            ex_loop_362.(ex_loop_362, k2)
          else
            k2
          end
        end
        _k2 = ex_loop_362.(ex_loop_362, k2)
        nil
      else
        Temper.MarginaliaCore.attach__372(Temper.MarginaliaCore.myers__369(ak, bk), aw, bw, parts)
        nil
      end
      Temper.MarginaliaCore.merge__373(TemperCore.List.to_list(parts))
    end)
  end
  def __temper_init__() do
    TemperCore.init_once(:"Temper.MarginaliaCore", fn ->
      TemperCore.Global.put(:"Temper.MarginaliaCore.abbreviations__374", %TemperCore.Vec{t: {"e.g", "i.e", "vs", "etc", "cf", "viz", "ca", "Mr", "Mrs", "Ms", "Dr", "Prof", "St", "No", "Fig", "Jr", "Sr", "Inc", "Ltd", "Co"}})
      TemperCore.Global.put(:"Temper.MarginaliaCore.v_EQ__375", 0)
      TemperCore.Global.put(:"Temper.MarginaliaCore.v_DEL__376", 1)
      TemperCore.Global.put(:"Temper.MarginaliaCore.v_INS__377", 2)
      nil
    end)
  end
  def main() do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Async.drain()
  end
end
