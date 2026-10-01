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
  def flushBlock__227(current, out) do
    if not TemperCore.List.is_empty(current) do
      TemperCore.List.add(out, Temper.MarginaliaCore.joinWith(TemperCore.List.to_list(current), "\n"))
      TemperCore.List.clear(current)
      nil
    else
      nil
    end
    nil
  end
  def fenceOpener__228(line) do
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
              Temper.MarginaliaCore.flushBlock__227(current, out)
              fence = nil
              fence
            else
              fence
            end
          else
            opener1 = Temper.MarginaliaCore.fenceOpener__228(line)
            cond do
              not (opener1 === nil) ->
                opener2 = opener1
                Temper.MarginaliaCore.flushBlock__227(current, out)
                TemperCore.List.add(current, line)
                fence = opener2
                fence
              TemperCore.String.is_empty(Temper.MarginaliaCore.trim(line)) ->
                Temper.MarginaliaCore.flushBlock__227(current, out)
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
      Temper.MarginaliaCore.flushBlock__227(current, out)
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
  def flushParagraph__229(piece, out) do
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
                Temper.MarginaliaCore.flushParagraph__229(piece, out)
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
      Temper.MarginaliaCore.flushParagraph__229(piece, out)
      TemperCore.List.to_list(out)
    end)
  end
  def alignmentKey__230(p) do
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
  def flushRun__231(dels, ins, out) do
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
        Temper.MarginaliaCore.alignmentKey__230(p1)
      end
      ak = TemperCore.List.map(a, fn_1)
      fn_2 = fn p2 ->
        Temper.MarginaliaCore.alignmentKey__230(p2)
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
              Temper.MarginaliaCore.flushRun__231(dels, ins, out)
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
      Temper.MarginaliaCore.flushRun__231(dels, ins, out)
      TemperCore.List.to_list(out)
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
  def isCloser__232(cp) do
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
  def isOpener__233(cp) do
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
  def allOf__246(s, from, to, cp) do
    try do
      return = nil
      return = try do
        i = from
        ex_loop_84 = fn ex_loop_84, i, return ->
          if i < to do
            if TemperCore.String.get(s, i) != cp do
              return = false
              throw({:temper_break, :ex_block_83, return})
            else
              i = TemperCore.String.next(s, i)
              ex_loop_84.(ex_loop_84, i, return)
            end
          else
            {i, return}
          end
        end
        {_i, _return} = ex_loop_84.(ex_loop_84, i, return)
        throw({:temper_return, :ex_return_82, true})
      catch
        {:temper_break, :ex_block_83, ex_vars_86} ->
          ex_vars_86
      end
      return
    catch
      {:temper_return, :ex_return_82, ex_value_87} ->
        ex_value_87
    end
  end
  def isUnderline__245(s) do
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
            throw({:temper_return, :ex_return_88, Temper.MarginaliaCore.allOf__246(s, TemperCore.String.begin(), TemperCore.String.end_of(s), mark)})
          end
        end
      end
      return
    catch
      {:temper_return, :ex_return_88, ex_value_90} ->
        ex_value_90
    end
  end
  def delimiterCell__248(s, at) do
    try do
      _return = nil
      return = if true do
        i = at
        ex_loop_93 = fn ex_loop_93, i ->
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
              ex_loop_93.(ex_loop_93, i)
            end
          else
            i
          end
        end
        i = ex_loop_93.(ex_loop_93, i)
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
        ex_loop_95 = fn ex_loop_95, dashes, i ->
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
              ex_loop_95.(ex_loop_95, dashes, i)
            end
          else
            {dashes, i}
          end
        end
        {dashes, i} = ex_loop_95.(ex_loop_95, dashes, i)
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
          ex_loop_97 = fn ex_loop_97, i ->
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
                ex_loop_97.(ex_loop_97, i)
              end
            else
              i
            end
          end
          i = ex_loop_97.(ex_loop_97, i)
          throw({:temper_return, :ex_return_91, i})
        end
      end
      return
    catch
      {:temper_return, :ex_return_91, ex_value_99} ->
        ex_value_99
    end
  end
  def isTableDelimiter__247(s) do
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
      first = Temper.MarginaliaCore.delimiterCell__248(s, i)
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
        ex_loop_102 = fn ex_loop_102, i, return ->
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
                cell = Temper.MarginaliaCore.delimiterCell__248(s, after_)
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
                  ex_loop_102.(ex_loop_102, i, return)
                end
            end
          else
            {i, return}
          end
        end
        {_i, return} = ex_loop_102.(ex_loop_102, i, return)
        return
      end
    end
    return
  end
  def isAtxHeading__249(s) do
    i = TemperCore.String.begin()
    hashes = 0
    ex_loop_105 = fn ex_loop_105, hashes, i ->
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
          ex_loop_105.(ex_loop_105, hashes, i)
        end
      else
        {hashes, i}
      end
    end
    {hashes, i} = ex_loop_105.(ex_loop_105, hashes, i)
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
  def isIndentedCode__250(block) do
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
          ex_loop_109 = fn ex_loop_109, i, spaces ->
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
                ex_loop_109.(ex_loop_109, i, spaces)
              end
            else
              {i, spaces}
            end
          end
          {_i, spaces} = ex_loop_109.(ex_loop_109, i, spaces)
          throw({:temper_return, :ex_return_107, spaces >= 4})
        end
      end
      return
    catch
      {:temper_return, :ex_return_107, ex_value_111} ->
        ex_value_111
    end
  end
  def isListItem__251(s) do
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
            ex_loop_114 = fn ex_loop_114, digits, i ->
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
                  ex_loop_114.(ex_loop_114, digits, i)
                end
              else
                {digits, i}
              end
            end
            {digits, i} = ex_loop_114.(ex_loop_114, digits, i)
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
                throw({:temper_return, :ex_return_112, Temper.MarginaliaCore.isRegexSpace(TemperCore.String.get(s, next))})
              else
                throw({:temper_return, :ex_return_112, false})
              end
            end
          end
        end
      end
      return
    catch
      {:temper_return, :ex_return_112, ex_value_116} ->
        ex_value_116
    end
  end
  def isHtml__252(s) do
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
              throw({:temper_return, :ex_return_117, true})
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
                  throw({:temper_return, :ex_return_117, true})
                c == 33 ->
                  throw({:temper_return, :ex_return_117, true})
                true ->
                  throw({:temper_return, :ex_return_117, c == 47})
              end
            end
          end
        end
      end
      return
    catch
      {:temper_return, :ex_return_117, ex_value_119} ->
        ex_value_119
    end
  end
  def isLoneLinkOrImage__253(block) do
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
          ex_loop_122 = fn ex_loop_122, i ->
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
                ex_loop_122.(ex_loop_122, i)
              end
            else
              i
            end
          end
          i = ex_loop_122.(ex_loop_122, i)
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
              ex_loop_124 = fn ex_loop_124, i ->
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
                    ex_loop_124.(ex_loop_124, i)
                  end
                else
                  i
                end
              end
              i = ex_loop_124.(ex_loop_124, i)
              if not TemperCore.String.has_index(block, i) do
                return = false
                return
              else
                i = TemperCore.String.next(block, i)
                ex_loop_126 = fn ex_loop_126, i ->
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
                      ex_loop_126.(ex_loop_126, i)
                    end
                  else
                    i
                  end
                end
                i = ex_loop_126.(ex_loop_126, i)
                throw({:temper_return, :ex_return_120, not TemperCore.String.has_index(block, i)})
              end
            end
          end
        end
      end
      return
    catch
      {:temper_return, :ex_return_120, ex_value_128} ->
        ex_value_128
    end
  end
  def isRule__254(s) do
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
            ex_loop_131 = fn ex_loop_131, count, i ->
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
                  ex_loop_131.(ex_loop_131, count, i)
                end
              else
                {count, i}
              end
            end
            {count, i} = ex_loop_131.(ex_loop_131, count, i)
            ex_loop_133 = fn ex_loop_133, i ->
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
                  ex_loop_133.(ex_loop_133, i)
                end
              else
                i
              end
            end
            i = ex_loop_133.(ex_loop_133, i)
            if count >= 3 do
              throw({:temper_return, :ex_return_129, not TemperCore.String.has_index(s, i)})
            else
              throw({:temper_return, :ex_return_129, false})
            end
          end
        end
      end
      return
    catch
      {:temper_return, :ex_return_129, ex_value_135} ->
        ex_value_135
    end
  end
  def isProse__244(block) do
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
          Temper.MarginaliaCore.isUnderline__245(second) ->
            return = false
            return
          Temper.MarginaliaCore.isTableDelimiter__247(second) ->
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
              Temper.MarginaliaCore.isAtxHeading__249(first) ->
                return = false
                return
              Temper.MarginaliaCore.isIndentedCode__250(block) ->
                return = false
                return
              Temper.MarginaliaCore.isListItem__251(first) ->
                return = false
                return
              Temper.MarginaliaCore.isHtml__252(first) ->
                return = false
                return
              Temper.MarginaliaCore.isLoneLinkOrImage__253(block) ->
                return = false
                return
              Temper.MarginaliaCore.isRule__254(first) ->
                return = false
                return
              true ->
                allPiped = true
                k = 0
                ex_loop_138 = fn ex_loop_138, allPiped, k ->
                  if k < TemperCore.List.length(lines) do
                    allPiped = if not Temper.MarginaliaCore.startsWith(Temper.MarginaliaCore.trimLeading(TemperCore.List.get(lines, k)), "|") do
                      allPiped = false
                      allPiped
                    else
                      allPiped
                    end
                    k = TemperCore.int32(k + 1)
                    ex_loop_138.(ex_loop_138, allPiped, k)
                  else
                    {allPiped, k}
                  end
                end
                {allPiped, _k} = ex_loop_138.(ex_loop_138, allPiped, k)
                throw({:temper_return, :ex_return_136, not allPiped})
            end
        end
      end
      return
    catch
      {:temper_return, :ex_return_136, ex_value_140} ->
        ex_value_140
    end
  end
  def isQuoted__236(block) do
    i = TemperCore.String.begin()
    ex_loop_142 = fn ex_loop_142, i ->
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
          ex_loop_142.(ex_loop_142, i)
        end
      else
        i
      end
    end
    i = ex_loop_142.(ex_loop_142, i)
    if TemperCore.String.has_index(block, i) do
      TemperCore.String.get(block, i) == 62
    else
      false
    end
  end
  def stripQuoteMark__235(line) do
    try do
      _return = nil
      return = if true do
        i = TemperCore.String.begin()
        ex_loop_146 = fn ex_loop_146, i ->
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
              ex_loop_146.(ex_loop_146, i)
            end
          else
            i
          end
        end
        i = ex_loop_146.(ex_loop_146, i)
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
          throw({:temper_return, :ex_return_144, TemperCore.String.slice(line, i, TemperCore.String.end_of(line))})
        end
      end
      return
    catch
      {:temper_return, :ex_return_144, ex_value_148} ->
        ex_value_148
    end
  end
  def reflowQuote__234(block) do
    lines = TemperCore.String.split(block, "\n")
    fn_1 = fn l1 ->
      Temper.MarginaliaCore.stripQuoteMark__235(l1)
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
  def breakSentences__239(text) do
    out = TemperCore.StringBuilder.new()
    i = TemperCore.String.begin()
    ex_loop_153 = fn ex_loop_153, i ->
      if TemperCore.String.has_index(text, i) do
        ex_step_167 = try do
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
            ex_loop_161 = fn ex_loop_161, j ->
              if true do
                _t3 = nil
                t3 = if TemperCore.String.has_index(text, j) do
                  t3 = Temper.MarginaliaCore.isCloser__232(TemperCore.String.get(text, j))
                  t3
                else
                  t3 = false
                  t3
                end
                if not t3 do
                  j
                else
                  j = TemperCore.String.next(text, j)
                  ex_loop_161.(ex_loop_161, j)
                end
              else
                j
              end
            end
            j = ex_loop_161.(ex_loop_161, j)
            k = j
            ex_loop_163 = fn ex_loop_163, k ->
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
                  ex_loop_163.(ex_loop_163, k)
                end
              else
                k
              end
            end
            k = ex_loop_163.(ex_loop_163, k)
            m = k
            ex_loop_165 = fn ex_loop_165, m ->
              if true do
                _t5 = nil
                t5 = if TemperCore.String.has_index(text, m) do
                  t5 = Temper.MarginaliaCore.isOpener__233(TemperCore.String.get(text, m))
                  t5
                else
                  t5 = false
                  t5
                end
                if not t5 do
                  m
                else
                  m = TemperCore.String.next(text, m)
                  ex_loop_165.(ex_loop_165, m)
                end
              else
                m
              end
            end
            m = ex_loop_165.(ex_loop_165, m)
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
              throw({:temper_continue, :ex_loop_154, i})
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
          {:temper_continue, :ex_loop_154, ex_vars_168} ->
            {:temper_next, ex_vars_168}
          {:temper_break, :ex_loop_154, ex_vars_168} ->
            {:temper_done, ex_vars_168}
        end
        case ex_step_167 do
          {:temper_next, i} ->
            ex_loop_153.(ex_loop_153, i)
          {:temper_done, ex_vars_168} ->
            ex_vars_168
        end
      else
        i
      end
    end
    _i = ex_loop_153.(ex_loop_153, i)
    TemperCore.StringBuilder.to_string(out)
  end
  def endsWithAt(s, end_, suffix) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      try do
        return = nil
        return = try do
          i = end_
          j = TemperCore.String.end_of(suffix)
          ex_loop_171 = fn ex_loop_171, i, j, return ->
            if j > TemperCore.String.begin() do
              if i <= TemperCore.String.begin() do
                return = false
                throw({:temper_break, :ex_block_170, return})
              else
                i = TemperCore.String.prev(s, i)
                j = TemperCore.String.prev(suffix, j)
                if TemperCore.String.get(s, i) != TemperCore.String.get(suffix, j) do
                  return = false
                  throw({:temper_break, :ex_block_170, return})
                else
                  ex_loop_171.(ex_loop_171, i, j, return)
                end
              end
            else
              {i, j, return}
            end
          end
          {_i, _j, _return} = ex_loop_171.(ex_loop_171, i, j, return)
          throw({:temper_return, :ex_return_169, true})
        catch
          {:temper_break, :ex_block_170, ex_vars_173} ->
            ex_vars_173
        end
        return
      catch
        {:temper_return, :ex_return_169, ex_value_174} ->
          ex_value_174
      end
    end)
  end
  def startsAWord__243(line, at) do
    if at <= TemperCore.String.begin() do
      true
    else
      Temper.MarginaliaCore.isUnicodeSpace(TemperCore.String.get(line, TemperCore.String.prev(line, at)))
    end
  end
  def abbreviationAt__242(line, dot, word) do
    try do
      _return = nil
      return = if true do
        if not Temper.MarginaliaCore.endsWithAt(line, dot, word) do
          return = false
          return
        else
          start = dot
          k = 0
          ex_loop_178 = fn ex_loop_178, k, start ->
            if k < TemperCore.String.count_between(word, TemperCore.String.begin(), TemperCore.String.end_of(word)) do
              start = TemperCore.String.prev(line, start)
              k = TemperCore.int32(k + 1)
              ex_loop_178.(ex_loop_178, k, start)
            else
              {k, start}
            end
          end
          {_k, start} = ex_loop_178.(ex_loop_178, k, start)
          throw({:temper_return, :ex_return_176, Temper.MarginaliaCore.startsAWord__243(line, start)})
        end
      end
      return
    catch
      {:temper_return, :ex_return_176, ex_value_180} ->
        ex_value_180
    end
  end
  def endsOnAbbreviation__241(line) do
    try do
      return = nil
      return = try do
        e = TemperCore.String.end_of(line)
        ex_loop_183 = fn ex_loop_183, e ->
          if true do
            _t2 = nil
            t2 = if e > TemperCore.String.begin() do
              t2 = Temper.MarginaliaCore.isCloser__232(TemperCore.String.get(line, TemperCore.String.prev(line, e)))
              t2
            else
              t2 = false
              t2
            end
            if not t2 do
              e
            else
              e = TemperCore.String.prev(line, e)
              ex_loop_183.(ex_loop_183, e)
            end
          else
            e
          end
        end
        e = ex_loop_183.(ex_loop_183, e)
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
          ex_loop_185 = fn ex_loop_185, k, return ->
            if k < TemperCore.List.length(TemperCore.Global.get(:"Temper.MarginaliaCore.abbreviations__265")) do
              if Temper.MarginaliaCore.abbreviationAt__242(line, dot, TemperCore.List.get(TemperCore.Global.get(:"Temper.MarginaliaCore.abbreviations__265"), k)) do
                return = true
                throw({:temper_break, :ex_block_182, return})
              else
                k = TemperCore.int32(k + 1)
                ex_loop_185.(ex_loop_185, k, return)
              end
            else
              {k, return}
            end
          end
          {_k, return} = ex_loop_185.(ex_loop_185, k, return)
          _return = if dot > TemperCore.String.begin() do
            c = TemperCore.String.prev(line, dot)
            cp = TemperCore.String.get(line, c)
            _t3 = nil
            t3 = if cp >= 65 do
              if cp <= 90 do
                t3 = Temper.MarginaliaCore.startsAWord__243(line, c)
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
              throw({:temper_break, :ex_block_182, return})
            else
              return
            end
          else
            return
          end
          throw({:temper_return, :ex_return_181, false})
        end
      catch
        {:temper_break, :ex_block_182, ex_vars_187} ->
          ex_vars_187
      end
      return
    catch
      {:temper_return, :ex_return_181, ex_value_188} ->
        ex_value_188
    end
  end
  def splitSentences__240(joined) do
    lines = TemperCore.String.split(Temper.MarginaliaCore.breakSentences__239(joined), "\n")
    out = TemperCore.List.builder()
    k = 0
    ex_loop_190 = fn ex_loop_190, k ->
      if k < TemperCore.List.length(lines) do
        n = TemperCore.List.length(out)
        _t = nil
        t = if n > 0 do
          t = Temper.MarginaliaCore.endsOnAbbreviation__241(TemperCore.List.get(out, TemperCore.int32(n - 1)))
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
        ex_loop_190.(ex_loop_190, k)
      else
        k
      end
    end
    _k = ex_loop_190.(ex_loop_190, k)
    Temper.MarginaliaCore.joinWith(TemperCore.List.to_list(out), "\n")
  end
  def squeezeBlanks__238(text) do
    out = TemperCore.StringBuilder.new()
    inBlank = false
    i = TemperCore.String.begin()
    ex_loop_193 = fn ex_loop_193, i, inBlank ->
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
        ex_loop_193.(ex_loop_193, i, inBlank)
      else
        {i, inBlank}
      end
    end
    {_i, _inBlank} = ex_loop_193.(ex_loop_193, i, inBlank)
    TemperCore.StringBuilder.to_string(out)
  end
  def unwrap__237(block) do
    lines = TemperCore.String.split(block, "\n")
    last = TemperCore.int32(TemperCore.List.length(lines) - 1)
    pieces = TemperCore.List.builder()
    k = 0
    ex_loop_196 = fn ex_loop_196, k ->
      if k <= last do
        line = TemperCore.List.get(lines, k)
        b = TemperCore.String.begin()
        e = TemperCore.String.end_of(line)
        b = if k > 0 do
          ex_loop_198 = fn ex_loop_198, b ->
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
                ex_loop_198.(ex_loop_198, b)
              end
            else
              b
            end
          end
          b = ex_loop_198.(ex_loop_198, b)
          b
        else
          b
        end
        e = if k < last do
          ex_loop_200 = fn ex_loop_200, e ->
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
                ex_loop_200.(ex_loop_200, e)
              end
            else
              e
            end
          end
          e = ex_loop_200.(ex_loop_200, e)
          e
        else
          e
        end
        TemperCore.List.add(pieces, TemperCore.String.slice(line, b, e))
        k = TemperCore.int32(k + 1)
        ex_loop_196.(ex_loop_196, k)
      else
        k
      end
    end
    _k = ex_loop_196.(ex_loop_196, k)
    Temper.MarginaliaCore.joinWith(TemperCore.List.to_list(pieces), " ")
  end
  def reflowBlock(block) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      try do
        _return = nil
        return = if true do
          cond do
            not Temper.MarginaliaCore.isProse__244(block) ->
              return = block
              return
            Temper.MarginaliaCore.isQuoted__236(block) ->
              return = Temper.MarginaliaCore.reflowQuote__234(block)
              return
            true ->
              throw({:temper_return, :ex_return_202, Temper.MarginaliaCore.splitSentences__240(Temper.MarginaliaCore.trim(Temper.MarginaliaCore.squeezeBlanks__238(Temper.MarginaliaCore.unwrap__237(block))))})
          end
        end
        return
      catch
        {:temper_return, :ex_return_202, ex_value_204} ->
          ex_value_204
      end
    end)
  end
  def wordsOf(text) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      out = TemperCore.List.builder()
      i = TemperCore.String.begin()
      ex_loop_206 = fn ex_loop_206, i ->
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
            ex_loop_206.(ex_loop_206, i)
          end
        else
          i
        end
      end
      i = ex_loop_206.(ex_loop_206, i)
      ex_loop_208 = fn ex_loop_208, i ->
        if TemperCore.String.has_index(text, i) do
          start = i
          ex_loop_210 = fn ex_loop_210, i ->
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
                ex_loop_210.(ex_loop_210, i)
              end
            else
              i
            end
          end
          i = ex_loop_210.(ex_loop_210, i)
          ex_loop_212 = fn ex_loop_212, i ->
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
                ex_loop_212.(ex_loop_212, i)
              end
            else
              i
            end
          end
          i = ex_loop_212.(ex_loop_212, i)
          TemperCore.List.add(out, TemperCore.String.slice(text, start, i))
          ex_loop_208.(ex_loop_208, i)
        else
          i
        end
      end
      _i = ex_loop_208.(ex_loop_208, i)
      TemperCore.List.to_list(out)
    end)
  end
  def distinct__256(words) do
    set = TemperCore.Map.builder()
    k = 0
    ex_loop_215 = fn ex_loop_215, k ->
      if k < TemperCore.List.length(words) do
        TemperCore.Map.set(set, TemperCore.List.get(words, k), true)
        k = TemperCore.int32(k + 1)
        ex_loop_215.(ex_loop_215, k)
      else
        k
      end
    end
    _k = ex_loop_215.(ex_loop_215, k)
    set
  end
  def unrelated__255(ak, bk) do
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
          a = TemperCore.Map.to_map(Temper.MarginaliaCore.distinct__256(ak))
          b = TemperCore.Map.to_map(Temper.MarginaliaCore.distinct__256(bk))
          bKeys = TemperCore.Map.keys(b)
          shared = 0
          k = 0
          ex_loop_219 = fn ex_loop_219, k, shared ->
            if k < TemperCore.List.length(bKeys) do
              shared = if TemperCore.Map.has(a, TemperCore.List.get(bKeys, k)) do
                shared = TemperCore.int32(shared + 1)
                shared
              else
                shared
              end
              k = TemperCore.int32(k + 1)
              ex_loop_219.(ex_loop_219, k, shared)
            else
              {k, shared}
            end
          end
          {_k, shared} = ex_loop_219.(ex_loop_219, k, shared)
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
          throw({:temper_return, :ex_return_217, TemperCore.Float.lt(TemperCore.int_to_float(shared), TemperCore.Float.mul(0.05, TemperCore.int_to_float(smaller)))})
        end
      end
      return
    catch
      {:temper_return, :ex_return_217, ex_value_221} ->
        ex_value_221
    end
  end
  def attach__263(script, aw, bw, parts) do
    ai = 0
    bi = 0
    c = 0
    ex_loop_223 = fn ex_loop_223, ai, bi, c ->
      if c < TemperCore.List.length(script) do
        chunk = TemperCore.List.get(script, c)
        count = TemperCore.List.length(Temper.MarginaliaCore.Chunk.get_words(chunk))
        k = 0
        ex_loop_225 = fn ex_loop_225, ai, bi, k ->
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
            ex_loop_225.(ex_loop_225, ai, bi, k)
          else
            {ai, bi, k}
          end
        end
        {ai, bi, _k} = ex_loop_225.(ex_loop_225, ai, bi, k)
        c = TemperCore.int32(c + 1)
        ex_loop_223.(ex_loop_223, ai, bi, c)
      else
        {ai, bi, c}
      end
    end
    {_ai, _bi, _c} = ex_loop_223.(ex_loop_223, ai, bi, c)
    nil
  end
  def moveDown__258(p, a) do
    if Temper.MarginaliaCore.Path.get_i(p) < TemperCore.List.length(a) do
      Temper.MarginaliaCore.Path.new(TemperCore.int32(Temper.MarginaliaCore.Path.get_y(p) + 1), TemperCore.int32(Temper.MarginaliaCore.Path.get_i(p) + 1), Temper.MarginaliaCore.Path.get_j(p), Temper.MarginaliaCore.Edit.new(1, TemperCore.List.get(a, Temper.MarginaliaCore.Path.get_i(p)), Temper.MarginaliaCore.Path.get_edits(p)))
    else
      Temper.MarginaliaCore.Path.new(TemperCore.int32(Temper.MarginaliaCore.Path.get_y(p) + 1), Temper.MarginaliaCore.Path.get_i(p), Temper.MarginaliaCore.Path.get_j(p), Temper.MarginaliaCore.Path.get_edits(p))
    end
  end
  def moveRight__257(p, b) do
    if Temper.MarginaliaCore.Path.get_j(p) < TemperCore.List.length(b) do
      Temper.MarginaliaCore.Path.new(Temper.MarginaliaCore.Path.get_y(p), Temper.MarginaliaCore.Path.get_i(p), TemperCore.int32(Temper.MarginaliaCore.Path.get_j(p) + 1), Temper.MarginaliaCore.Edit.new(2, TemperCore.List.get(b, Temper.MarginaliaCore.Path.get_j(p)), Temper.MarginaliaCore.Path.get_edits(p)))
    else
      p
    end
  end
  def followSnake__259(p, a, b) do
    y = Temper.MarginaliaCore.Path.get_y(p)
    i = Temper.MarginaliaCore.Path.get_i(p)
    j = Temper.MarginaliaCore.Path.get_j(p)
    edits = Temper.MarginaliaCore.Path.get_edits(p)
    ex_loop_230 = fn ex_loop_230, edits, i, j, y ->
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
          ex_loop_230.(ex_loop_230, edits, i, j, y)
        end
      else
        {edits, i, j, y}
      end
    end
    {edits, i, j, y} = ex_loop_230.(ex_loop_230, edits, i, j, y)
    Temper.MarginaliaCore.Path.new(y, i, j, edits)
  end
  def sameWords__262(x, y) do
    try do
      return = nil
      return = try do
        if TemperCore.List.length(x) != TemperCore.List.length(y) do
          return = false
          return
        else
          k = 0
          ex_loop_234 = fn ex_loop_234, k, return ->
            if k < TemperCore.List.length(x) do
              if TemperCore.List.get(x, k) != TemperCore.List.get(y, k) do
                return = false
                throw({:temper_break, :ex_block_233, return})
              else
                k = TemperCore.int32(k + 1)
                ex_loop_234.(ex_loop_234, k, return)
              end
            else
              {k, return}
            end
          end
          {_k, _return} = ex_loop_234.(ex_loop_234, k, return)
          throw({:temper_return, :ex_return_232, true})
        end
      catch
        {:temper_break, :ex_block_233, ex_vars_236} ->
          ex_vars_236
      end
      return
    catch
      {:temper_return, :ex_return_232, ex_value_237} ->
        ex_value_237
    end
  end
  def compact__261(edits) do
    out = TemperCore.List.builder()
    e = edits
    ex_loop_239 = fn ex_loop_239, e ->
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
          ex_loop_239.(ex_loop_239, e)
        else
          _t2 = nil
          t2 = if n >= 3 do
            if Temper.MarginaliaCore.Chunk.get_kind(TemperCore.List.get(out, TemperCore.int32(n - 1))) == 0 do
              if Temper.MarginaliaCore.Chunk.get_kind(TemperCore.List.get(out, TemperCore.int32(n - 2))) == 2 do
                if Temper.MarginaliaCore.Chunk.get_kind(TemperCore.List.get(out, TemperCore.int32(n - 3))) == 0 do
                  t2 = Temper.MarginaliaCore.sameWords__262(Temper.MarginaliaCore.Chunk.get_words(TemperCore.List.get(out, TemperCore.int32(n - 1))), Temper.MarginaliaCore.Chunk.get_words(TemperCore.List.get(out, TemperCore.int32(n - 2))))
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
            ex_loop_239.(ex_loop_239, e)
          else
            words = TemperCore.List.builder()
            TemperCore.List.add(words, Temper.MarginaliaCore.Edit.get_word(edit))
            TemperCore.List.add(out, Temper.MarginaliaCore.Chunk.new(Temper.MarginaliaCore.Edit.get_kind(edit), words))
            e = Temper.MarginaliaCore.Edit.get_before(edit)
            ex_loop_239.(ex_loop_239, e)
          end
        end
      else
        e
      end
    end
    _e = ex_loop_239.(ex_loop_239, e)
    TemperCore.List.reverse(out)
    k = 0
    ex_loop_241 = fn ex_loop_241, k ->
      if k < TemperCore.List.length(out) do
        TemperCore.List.reverse(Temper.MarginaliaCore.Chunk.get_words(TemperCore.List.get(out, k)))
        k = TemperCore.int32(k + 1)
        ex_loop_241.(ex_loop_241, k)
      else
        k
      end
    end
    _k = ex_loop_241.(ex_loop_241, k)
    TemperCore.List.to_list(out)
  end
  def myers__260(a, b) do
    return = nil
    return = try do
      paths = %TemperCore.Vec{t: {Temper.MarginaliaCore.Path.new(0, 0, 0, nil)}}
      envelope = 0
      ex_loop_245 = fn ex_loop_245, envelope, paths, return ->
        if true do
          next = TemperCore.List.builder()
          at = 0
          diag = TemperCore.int32(-envelope)
          ex_loop_247 = fn ex_loop_247, at, diag, return ->
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
                  path = Temper.MarginaliaCore.moveDown__258(path, a)
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
                    path = Temper.MarginaliaCore.moveRight__257(path, b)
                    at = TemperCore.int32(at + 1)
                    {at, path}
                  else
                    _t4 = nil
                    second = TemperCore.List.get(paths, TemperCore.int32(at + 1))
                    t4 = if Temper.MarginaliaCore.Path.get_y(path) > Temper.MarginaliaCore.Path.get_y(second) do
                      t4 = Temper.MarginaliaCore.moveRight__257(path, b)
                      t4
                    else
                      t4 = Temper.MarginaliaCore.moveDown__258(second, a)
                      t4
                    end
                    path = t4
                    at = TemperCore.int32(at + 1)
                    {at, path}
                  end
              end
              path = Temper.MarginaliaCore.followSnake__259(path, a, b)
              _t2 = nil
              t2 = if Temper.MarginaliaCore.Path.get_i(path) == TemperCore.List.length(a) do
                t2 = Temper.MarginaliaCore.Path.get_j(path) == TemperCore.List.length(b)
                t2
              else
                t2 = false
                t2
              end
              if t2 do
                return = Temper.MarginaliaCore.compact__261(Temper.MarginaliaCore.Path.get_edits(path))
                throw({:temper_break, :ex_block_244, return})
              else
                TemperCore.List.add(next, path)
                diag = TemperCore.int32(diag + 2)
                ex_loop_247.(ex_loop_247, at, diag, return)
              end
            else
              {at, diag, return}
            end
          end
          {_at, _diag, return} = ex_loop_247.(ex_loop_247, at, diag, return)
          paths = TemperCore.List.to_list(next)
          envelope = TemperCore.int32(envelope + 1)
          ex_loop_245.(ex_loop_245, envelope, paths, return)
        else
          {envelope, paths, return}
        end
      end
      {_envelope, _paths, return} = ex_loop_245.(ex_loop_245, envelope, paths, return)
      return
    catch
      {:temper_break, :ex_block_244, ex_vars_249} ->
        ex_vars_249
    end
    return
  end
  def merge__264(parts) do
    out = TemperCore.List.builder()
    k = 0
    ex_loop_251 = fn ex_loop_251, k ->
      if k < TemperCore.List.length(parts) do
        kind = Temper.MarginaliaCore.Part.get_kind(TemperCore.List.get(parts, k))
        text = TemperCore.StringBuilder.new()
        ex_loop_253 = fn ex_loop_253, k ->
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
              ex_loop_253.(ex_loop_253, k)
            end
          else
            k
          end
        end
        k = ex_loop_253.(ex_loop_253, k)
        TemperCore.List.add(out, Temper.MarginaliaCore.Part.new(kind, TemperCore.StringBuilder.to_string(text)))
        ex_loop_251.(ex_loop_251, k)
      else
        k
      end
    end
    _k = ex_loop_251.(ex_loop_251, k)
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
      if Temper.MarginaliaCore.unrelated__255(ak, bk) do
        k1 = 0
        ex_loop_258 = fn ex_loop_258, k1 ->
          if k1 < TemperCore.List.length(aw) do
            TemperCore.List.add(parts, Temper.MarginaliaCore.Part.new("del", TemperCore.List.get(aw, k1)))
            k1 = TemperCore.int32(k1 + 1)
            ex_loop_258.(ex_loop_258, k1)
          else
            k1
          end
        end
        _k1 = ex_loop_258.(ex_loop_258, k1)
        k2 = 0
        ex_loop_260 = fn ex_loop_260, k2 ->
          if k2 < TemperCore.List.length(bw) do
            TemperCore.List.add(parts, Temper.MarginaliaCore.Part.new("ins", TemperCore.List.get(bw, k2)))
            k2 = TemperCore.int32(k2 + 1)
            ex_loop_260.(ex_loop_260, k2)
          else
            k2
          end
        end
        _k2 = ex_loop_260.(ex_loop_260, k2)
        nil
      else
        Temper.MarginaliaCore.attach__263(Temper.MarginaliaCore.myers__260(ak, bk), aw, bw, parts)
        nil
      end
      Temper.MarginaliaCore.merge__264(TemperCore.List.to_list(parts))
    end)
  end
  def __temper_init__() do
    TemperCore.init_once(:"Temper.MarginaliaCore", fn ->
      TemperCore.Global.put(:"Temper.MarginaliaCore.abbreviations__265", %TemperCore.Vec{t: {"e.g", "i.e", "vs", "etc", "cf", "viz", "ca", "Mr", "Mrs", "Ms", "Dr", "Prof", "St", "No", "Fig", "Jr", "Sr", "Inc", "Ltd", "Co"}})
      TemperCore.Global.put(:"Temper.MarginaliaCore.v_EQ__266", 0)
      TemperCore.Global.put(:"Temper.MarginaliaCore.v_DEL__267", 1)
      TemperCore.Global.put(:"Temper.MarginaliaCore.v_INS__268", 2)
      nil
    end)
  end
  def main() do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Async.drain()
  end
end
