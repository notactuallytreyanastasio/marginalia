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
defmodule Temper.MarginaliaCore.Section do
  defstruct [:title, :body]
  def __temper_supertypes__() do
    [Temper.MarginaliaCore.Section]
  end
  def new(title, body) do
    Temper.MarginaliaCore.__temper_init__()
    this = %Temper.MarginaliaCore.Section{}
    this = %{this | :title => title}
    this = %{this | :body => body}
    this
  end
  def get_title(this) do
    this.title
  end
  def get_body(this) do
    this.body
  end
end
defmodule Temper.MarginaliaCore.HeadChunk do
  def __temper_supertypes__() do
    [Temper.MarginaliaCore.HeadChunk]
  end
  def new(title, lines) do
    this = TemperCore.Heap.new(Temper.MarginaliaCore.HeadChunk, %{:title => nil, :lines => nil})
    TemperCore.Heap.put(this, :title, title)
    TemperCore.Heap.put(this, :lines, lines)
    this
  end
  def get_title(this) do
    TemperCore.Heap.get(this, :title)
  end
  def get_lines(this) do
    TemperCore.Heap.get(this, :lines)
  end
end
defmodule Temper.MarginaliaCore.Window do
  def __temper_supertypes__() do
    [Temper.MarginaliaCore.Window]
  end
  def new(paras, words) do
    this = TemperCore.Heap.new(Temper.MarginaliaCore.Window, %{:paras => nil, :words => nil})
    TemperCore.Heap.put(this, :paras, paras)
    TemperCore.Heap.put(this, :words, words)
    this
  end
  def get_paras(this) do
    TemperCore.Heap.get(this, :paras)
  end
  def get_words(this) do
    TemperCore.Heap.get(this, :words)
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
            throw({:temper_return, :ex_return_13, Temper.MarginaliaCore.joinWith__520(TemperCore.List.map(Temper.MarginaliaCore.blocks(text), fn_), "\n\n")})
          end
        end
        return
      catch
        {:temper_return, :ex_return_13, ex_value_16} ->
          ex_value_16
      end
    end)
  end
  def startsWith__518(s, prefix) do
    try do
      return = nil
      return = try do
        i = TemperCore.String.begin()
        j = TemperCore.String.begin()
        ex_loop_34 = fn ex_loop_34, i, j, return ->
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
              throw({:temper_break, :ex_block_33, return})
            else
              i = TemperCore.String.next(s, i)
              j = TemperCore.String.next(prefix, j)
              ex_loop_34.(ex_loop_34, i, j, return)
            end
          else
            {i, j, return}
          end
        end
        {_i, _j, _return} = ex_loop_34.(ex_loop_34, i, j, return)
        throw({:temper_return, :ex_return_32, true})
      catch
        {:temper_break, :ex_block_33, ex_vars_36} ->
          ex_vars_36
      end
      return
    catch
      {:temper_return, :ex_return_32, ex_value_37} ->
        ex_value_37
    end
  end
  def isRegexSpace__511(cp) do
    cond do
      cp == 32 ->
        true
      cp >= 9 ->
        cp <= 13
      true ->
        false
    end
  end
  def isTrimSpace__512(cp) do
    cond do
      Temper.MarginaliaCore.isRegexSpace__511(cp) ->
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
  end
  def leadingEnd__515(s) do
    b = TemperCore.String.begin()
    ex_loop_41 = fn ex_loop_41, b ->
      if true do
        _t = nil
        t = if TemperCore.String.has_index(s, b) do
          t = Temper.MarginaliaCore.isTrimSpace__512(TemperCore.String.get(s, b))
          t
        else
          t = false
          t
        end
        if not t do
          b
        else
          b = TemperCore.String.next(s, b)
          ex_loop_41.(ex_loop_41, b)
        end
      else
        b
      end
    end
    b = ex_loop_41.(ex_loop_41, b)
    b
  end
  def trimLeading__516(s) do
    TemperCore.String.slice(s, Temper.MarginaliaCore.leadingEnd__515(s), TemperCore.String.end_of(s))
  end
  def joinWith__520(parts, sep) do
    fn_ = fn p ->
      p
    end
    TemperCore.List.join(parts, sep, fn_)
  end
  def flushBlock__433(current, out) do
    if not TemperCore.List.is_empty(current) do
      TemperCore.List.add(out, Temper.MarginaliaCore.joinWith__520(TemperCore.List.to_list(current), "\n"))
      TemperCore.List.clear(current)
      nil
    else
      nil
    end
    nil
  end
  def fenceOpener__434(line) do
    try do
      _return = nil
      return = if true do
        i = TemperCore.String.begin()
        ex_loop_49 = fn ex_loop_49, i ->
          if true do
            _t2 = nil
            t2 = if TemperCore.String.has_index(line, i) do
              t2 = Temper.MarginaliaCore.isRegexSpace__511(TemperCore.String.get(line, i))
              t2
            else
              t2 = false
              t2
            end
            if not t2 do
              i
            else
              i = TemperCore.String.next(line, i)
              ex_loop_49.(ex_loop_49, i)
            end
          else
            i
          end
        end
        i = ex_loop_49.(ex_loop_49, i)
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
            ex_loop_51 = fn ex_loop_51, count, i ->
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
                  ex_loop_51.(ex_loop_51, count, i)
                end
              else
                {count, i}
              end
            end
            {count, i} = ex_loop_51.(ex_loop_51, count, i)
            if count >= 3 do
              throw({:temper_return, :ex_return_47, TemperCore.String.slice(line, start, i)})
            else
              throw({:temper_return, :ex_return_47, nil})
            end
          end
        end
      end
      return
    catch
      {:temper_return, :ex_return_47, ex_value_53} ->
        ex_value_53
    end
  end
  def trim__513(s) do
    b = TemperCore.String.begin()
    ex_loop_55 = fn ex_loop_55, b ->
      if true do
        _t1 = nil
        t1 = if TemperCore.String.has_index(s, b) do
          t1 = Temper.MarginaliaCore.isTrimSpace__512(TemperCore.String.get(s, b))
          t1
        else
          t1 = false
          t1
        end
        if not t1 do
          b
        else
          b = TemperCore.String.next(s, b)
          ex_loop_55.(ex_loop_55, b)
        end
      else
        b
      end
    end
    b = ex_loop_55.(ex_loop_55, b)
    e = TemperCore.String.end_of(s)
    ex_loop_57 = fn ex_loop_57, e ->
      if true do
        _t2 = nil
        t2 = if e > b do
          t2 = Temper.MarginaliaCore.isTrimSpace__512(TemperCore.String.get(s, TemperCore.String.prev(s, e)))
          t2
        else
          t2 = false
          t2
        end
        if not t2 do
          e
        else
          e = TemperCore.String.prev(s, e)
          ex_loop_57.(ex_loop_57, e)
        end
      else
        e
      end
    end
    e = ex_loop_57.(ex_loop_57, e)
    TemperCore.String.slice(s, b, e)
  end
  def trailingStart__514(s) do
    e = TemperCore.String.end_of(s)
    ex_loop_60 = fn ex_loop_60, e ->
      if true do
        _t = nil
        t = if e > TemperCore.String.begin() do
          t = Temper.MarginaliaCore.isTrimSpace__512(TemperCore.String.get(s, TemperCore.String.prev(s, e)))
          t
        else
          t = false
          t
        end
        if not t do
          e
        else
          e = TemperCore.String.prev(s, e)
          ex_loop_60.(ex_loop_60, e)
        end
      else
        e
      end
    end
    e = ex_loop_60.(ex_loop_60, e)
    e
  end
  def trimTrailing__517(s) do
    TemperCore.String.slice(s, TemperCore.String.begin(), Temper.MarginaliaCore.trailingStart__514(s))
  end
  def blocks(body) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      out = TemperCore.List.builder()
      current = TemperCore.List.builder()
      fence = nil
      lines = TemperCore.String.split(body, "\n")
      k1 = 0
      ex_loop_64 = fn ex_loop_64, fence, k1 ->
        if k1 < TemperCore.List.length(lines) do
          line = TemperCore.List.get(lines, k1)
          open1 = fence
          fence = if not (open1 === nil) do
            open2 = open1
            TemperCore.List.add(current, line)
            if Temper.MarginaliaCore.startsWith__518(Temper.MarginaliaCore.trimLeading__516(line), open2) do
              Temper.MarginaliaCore.flushBlock__433(current, out)
              fence = nil
              fence
            else
              fence
            end
          else
            opener1 = Temper.MarginaliaCore.fenceOpener__434(line)
            cond do
              not (opener1 === nil) ->
                opener2 = opener1
                Temper.MarginaliaCore.flushBlock__433(current, out)
                TemperCore.List.add(current, line)
                fence = opener2
                fence
              TemperCore.String.is_empty(Temper.MarginaliaCore.trim__513(line)) ->
                Temper.MarginaliaCore.flushBlock__433(current, out)
                fence
              true ->
                TemperCore.List.add(current, line)
                fence
            end
          end
          k1 = TemperCore.int32(k1 + 1)
          ex_loop_64.(ex_loop_64, fence, k1)
        else
          {fence, k1}
        end
      end
      {_fence, _k1} = ex_loop_64.(ex_loop_64, fence, k1)
      Temper.MarginaliaCore.flushBlock__433(current, out)
      kept = TemperCore.List.builder()
      all = TemperCore.List.to_list(out)
      k2 = 0
      ex_loop_66 = fn ex_loop_66, k2 ->
        if k2 < TemperCore.List.length(all) do
          block = Temper.MarginaliaCore.trimTrailing__517(TemperCore.List.get(all, k2))
          if not TemperCore.String.is_empty(Temper.MarginaliaCore.trim__513(block)) do
            TemperCore.List.add(kept, block)
            nil
          else
            nil
          end
          k2 = TemperCore.int32(k2 + 1)
          ex_loop_66.(ex_loop_66, k2)
        else
          k2
        end
      end
      _k2 = ex_loop_66.(ex_loop_66, k2)
      TemperCore.List.to_list(kept)
    end)
  end
  def flushParagraph__435(piece, out) do
    p = Temper.MarginaliaCore.trim__513(TemperCore.StringBuilder.to_string(piece))
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
      ex_loop_70 = fn ex_loop_70, i, newlines ->
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
                Temper.MarginaliaCore.flushParagraph__435(piece, out)
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
          ex_loop_70.(ex_loop_70, i, newlines)
        else
          {i, newlines}
        end
      end
      {_i, newlines} = ex_loop_70.(ex_loop_70, i, newlines)
      if newlines == 1 do
        TemperCore.StringBuilder.append(piece, "\n")
        nil
      else
        nil
      end
      Temper.MarginaliaCore.flushParagraph__435(piece, out)
      TemperCore.List.to_list(out)
    end)
  end
  def alignmentKey__436(p) do
    out = TemperCore.StringBuilder.new()
    inSpace = false
    i = TemperCore.String.begin()
    ex_loop_73 = fn ex_loop_73, i, inSpace ->
      if TemperCore.String.has_index(p, i) do
        cp = TemperCore.String.get(p, i)
        inSpace = if Temper.MarginaliaCore.isRegexSpace__511(cp) do
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
        ex_loop_73.(ex_loop_73, i, inSpace)
      else
        {i, inSpace}
      end
    end
    {_i, inSpace} = ex_loop_73.(ex_loop_73, i, inSpace)
    if inSpace do
      TemperCore.StringBuilder.append(out, " ")
      nil
    else
      nil
    end
    Temper.MarginaliaCore.trim__513(TemperCore.StringBuilder.to_string(out))
  end
  def flushRun__437(dels, ins, out) do
    _longer = nil
    longer = if TemperCore.List.length(dels) > TemperCore.List.length(ins) do
      longer = TemperCore.List.length(dels)
      longer
    else
      longer = TemperCore.List.length(ins)
      longer
    end
    k = 0
    ex_loop_76 = fn ex_loop_76, k ->
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
        ex_loop_76.(ex_loop_76, k)
      else
        k
      end
    end
    _k = ex_loop_76.(ex_loop_76, k)
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
        Temper.MarginaliaCore.alignmentKey__436(p1)
      end
      ak = TemperCore.List.map(a, fn_1)
      fn_2 = fn p2 ->
        Temper.MarginaliaCore.alignmentKey__436(p2)
      end
      bk = TemperCore.List.map(b, fn_2)
      n = TemperCore.List.length(a)
      m = TemperCore.List.length(b)
      width = TemperCore.int32(m + 1)
      table = TemperCore.List.builder()
      k = 0
      ex_loop_81 = fn ex_loop_81, k ->
        if k < TemperCore.int32(TemperCore.int32(n + 1) * width) do
          TemperCore.List.add(table, 0)
          k = TemperCore.int32(k + 1)
          ex_loop_81.(ex_loop_81, k)
        else
          k
        end
      end
      _k = ex_loop_81.(ex_loop_81, k)
      i1 = TemperCore.int32(n - 1)
      ex_loop_83 = fn ex_loop_83, i1 ->
        if i1 >= 0 do
          j2 = TemperCore.int32(m - 1)
          ex_loop_85 = fn ex_loop_85, j2 ->
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
              ex_loop_85.(ex_loop_85, j2)
            else
              j2
            end
          end
          _j2 = ex_loop_85.(ex_loop_85, j2)
          i1 = TemperCore.int32(i1 - 1)
          ex_loop_83.(ex_loop_83, i1)
        else
          i1
        end
      end
      _i1 = ex_loop_83.(ex_loop_83, i1)
      out = TemperCore.List.builder()
      dels = TemperCore.List.builder()
      ins = TemperCore.List.builder()
      i2 = 0
      j1 = 0
      ex_loop_87 = fn ex_loop_87, i2, j1 ->
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
              Temper.MarginaliaCore.flushRun__437(dels, ins, out)
              TemperCore.List.add(out, Temper.MarginaliaCore.Row.new("same", TemperCore.List.get(a, i2), TemperCore.List.get(a, i2)))
              i2 = TemperCore.int32(i2 + 1)
              j1 = TemperCore.int32(j1 + 1)
              ex_loop_87.(ex_loop_87, i2, j1)
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
                ex_loop_87.(ex_loop_87, i2, j1)
              else
                TemperCore.List.add(dels, TemperCore.List.get(a, i2))
                i2 = TemperCore.int32(i2 + 1)
                ex_loop_87.(ex_loop_87, i2, j1)
              end
            end
          end
        else
          {i2, j1}
        end
      end
      {_i2, _j1} = ex_loop_87.(ex_loop_87, i2, j1)
      Temper.MarginaliaCore.flushRun__437(dels, ins, out)
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
      ex_loop_100 = fn ex_loop_100, k, nonBlank ->
        if k < TemperCore.List.length(lines) do
          nonBlank = if not TemperCore.String.is_empty(Temper.MarginaliaCore.trim__513(TemperCore.List.get(lines, k))) do
            nonBlank = TemperCore.int32(nonBlank + 1)
            nonBlank
          else
            nonBlank
          end
          k = TemperCore.int32(k + 1)
          ex_loop_100.(ex_loop_100, k, nonBlank)
        else
          {k, nonBlank}
        end
      end
      {_k, nonBlank} = ex_loop_100.(ex_loop_100, k, nonBlank)
      gaps = 0
      i = TemperCore.String.begin()
      ex_loop_102 = fn ex_loop_102, gaps, i ->
        if TemperCore.String.has_index(text, i) do
          if Temper.MarginaliaCore.isRegexSpace__511(TemperCore.String.get(text, i)) do
            newlines = 0
            ex_loop_104 = fn ex_loop_104, i, newlines ->
              if true do
                _t = nil
                t = if TemperCore.String.has_index(text, i) do
                  t = Temper.MarginaliaCore.isRegexSpace__511(TemperCore.String.get(text, i))
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
                  ex_loop_104.(ex_loop_104, i, newlines)
                end
              else
                {i, newlines}
              end
            end
            {i, newlines} = ex_loop_104.(ex_loop_104, i, newlines)
            if newlines >= 2 do
              gaps = TemperCore.int32(gaps + 1)
              ex_loop_102.(ex_loop_102, gaps, i)
            else
              ex_loop_102.(ex_loop_102, gaps, i)
            end
          else
            i = TemperCore.String.next(text, i)
            ex_loop_102.(ex_loop_102, gaps, i)
          end
        else
          {gaps, i}
        end
      end
      {gaps, _i} = ex_loop_102.(ex_loop_102, gaps, i)
      if nonBlank >= 12 do
        gaps <= TemperCore.int32(div(nonBlank, 12))
      else
        false
      end
    end)
  end
  def isWordChar__452(cp) do
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
  def intactHyphens__453(text) do
    found = TemperCore.Map.builder()
    i = TemperCore.String.begin()
    ex_loop_108 = fn ex_loop_108, i ->
      if TemperCore.String.has_index(text, i) do
        if not Temper.MarginaliaCore.isWordChar__452(TemperCore.String.get(text, i)) do
          i = TemperCore.String.next(text, i)
          ex_loop_108.(ex_loop_108, i)
        else
          start = i
          ex_loop_110 = fn ex_loop_110, i ->
            if true do
              _t2 = nil
              t2 = if TemperCore.String.has_index(text, i) do
                t2 = Temper.MarginaliaCore.isWordChar__452(TemperCore.String.get(text, i))
                t2
              else
                t2 = false
                t2
              end
              if not t2 do
                i
              else
                i = TemperCore.String.next(text, i)
                ex_loop_110.(ex_loop_110, i)
              end
            else
              i
            end
          end
          i = ex_loop_110.(ex_loop_110, i)
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
              t3 = Temper.MarginaliaCore.isWordChar__452(TemperCore.String.get(text, after_))
              t3
            else
              t3 = false
              t3
            end
            if t3 do
              e = after_
              ex_loop_112 = fn ex_loop_112, e ->
                if true do
                  _t4 = nil
                  t4 = if TemperCore.String.has_index(text, e) do
                    t4 = Temper.MarginaliaCore.isWordChar__452(TemperCore.String.get(text, e))
                    t4
                  else
                    t4 = false
                    t4
                  end
                  if not t4 do
                    e
                  else
                    e = TemperCore.String.next(text, e)
                    ex_loop_112.(ex_loop_112, e)
                  end
                else
                  e
                end
              end
              e = ex_loop_112.(ex_loop_112, e)
              TemperCore.Map.set(found, Temper.MarginaliaCore.downcase(TemperCore.String.slice(text, start, e)), true)
              i = e
              ex_loop_108.(ex_loop_108, i)
            else
              ex_loop_108.(ex_loop_108, i)
            end
          else
            ex_loop_108.(ex_loop_108, i)
          end
        end
      else
        i
      end
    end
    _i = ex_loop_108.(ex_loop_108, i)
    found
  end
  def normalizeNewlines__440(text) do
    Temper.MarginaliaCore.joinWith__520(TemperCore.String.split(text, "\r\n"), "\n")
  end
  def isJudgeLine__449(line) do
    try do
      _return = nil
      return = if true do
        i = TemperCore.String.begin()
        names = 0
        ex_loop_117 = fn ex_loop_117, i, names ->
          if true do
            j = i
            caps = 0
            ex_loop_119 = fn ex_loop_119, caps, j ->
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
                  ex_loop_119.(ex_loop_119, caps, j)
                end
              else
                {caps, j}
              end
            end
            {caps, j} = ex_loop_119.(ex_loop_119, caps, j)
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
                ex_loop_117.(ex_loop_117, i, names)
              end
            end
          else
            {i, names}
          end
        end
        {i, names} = ex_loop_117.(ex_loop_117, i, names)
        if names == 0 do
          return = false
          return
        else
          rest = TemperCore.String.slice(line, i, TemperCore.String.end_of(line))
          at = TemperCore.String.begin()
          at = if Temper.MarginaliaCore.startsWith__518(rest, "C. ") do
            at = TemperCore.String.step(rest, at, 3)
            at
          else
            at
          end
          tail = TemperCore.String.slice(rest, at, TemperCore.String.end_of(rest))
          if not Temper.MarginaliaCore.startsWith__518(tail, "J.,") do
            return = false
            return
          else
            k = TemperCore.String.step(tail, TemperCore.String.begin(), 3)
            spaces = 0
            ex_loop_121 = fn ex_loop_121, k, spaces ->
              if true do
                _t3 = nil
                t3 = if TemperCore.String.has_index(tail, k) do
                  t3 = Temper.MarginaliaCore.isRegexSpace__511(TemperCore.String.get(tail, k))
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
                  ex_loop_121.(ex_loop_121, k, spaces)
                end
              else
                {k, spaces}
              end
            end
            {k, spaces} = ex_loop_121.(ex_loop_121, k, spaces)
            word = TemperCore.String.slice(tail, k, TemperCore.String.end_of(tail))
            if spaces >= 1 do
              if Temper.MarginaliaCore.startsWith__518(word, "concurring") do
                throw({:temper_return, :ex_return_115, true})
              else
                throw({:temper_return, :ex_return_115, Temper.MarginaliaCore.startsWith__518(word, "dissenting")})
              end
            else
              throw({:temper_return, :ex_return_115, false})
            end
          end
        end
      end
      return
    catch
      {:temper_return, :ex_return_115, ex_value_123} ->
        ex_value_123
    end
  end
  def allAsciiDigits__448(s, from, to) do
    try do
      return = nil
      return = try do
        i = from
        ex_loop_126 = fn ex_loop_126, i, return ->
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
              throw({:temper_break, :ex_block_125, return})
            else
              i = TemperCore.String.next(s, i)
              ex_loop_126.(ex_loop_126, i, return)
            end
          else
            {i, return}
          end
        end
        {_i, _return} = ex_loop_126.(ex_loop_126, i, return)
        throw({:temper_return, :ex_return_124, true})
      catch
        {:temper_break, :ex_block_125, ex_vars_128} ->
          ex_vars_128
      end
      return
    catch
      {:temper_return, :ex_return_124, ex_value_129} ->
        ex_value_129
    end
  end
  def isPageNumber__447(line) do
    n = TemperCore.String.count_between(line, TemperCore.String.begin(), TemperCore.String.end_of(line))
    if n >= 1 do
      if n <= 3 do
        Temper.MarginaliaCore.allAsciiDigits__448(line, TemperCore.String.begin(), TemperCore.String.end_of(line))
      else
        false
      end
    else
      false
    end
  end
  def withoutPageNumbers__451(line) do
    s = line
    i = TemperCore.String.begin()
    digits = 0
    ex_loop_132 = fn ex_loop_132, digits, i ->
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
          ex_loop_132.(ex_loop_132, digits, i)
        end
      else
        {digits, i}
      end
    end
    {digits, i} = ex_loop_132.(ex_loop_132, digits, i)
    _t1 = nil
    t1 = if digits >= 1 do
      if digits <= 3 do
        if TemperCore.String.has_index(s, i) do
          t1 = Temper.MarginaliaCore.isRegexSpace__511(TemperCore.String.get(s, i))
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
      ex_loop_134 = fn ex_loop_134, i ->
        if true do
          _t5 = nil
          t5 = if TemperCore.String.has_index(s, i) do
            t5 = Temper.MarginaliaCore.isRegexSpace__511(TemperCore.String.get(s, i))
            t5
          else
            t5 = false
            t5
          end
          if not t5 do
            i
          else
            i = TemperCore.String.next(s, i)
            ex_loop_134.(ex_loop_134, i)
          end
        else
          i
        end
      end
      i = ex_loop_134.(ex_loop_134, i)
      s = TemperCore.String.slice(s, i, TemperCore.String.end_of(s))
      {i, s}
    else
      {i, s}
    end
    e = TemperCore.String.end_of(s)
    tailDigits = 0
    ex_loop_136 = fn ex_loop_136, e, tailDigits ->
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
          ex_loop_136.(ex_loop_136, e, tailDigits)
        end
      else
        {e, tailDigits}
      end
    end
    {e, tailDigits} = ex_loop_136.(ex_loop_136, e, tailDigits)
    _t2 = nil
    t2 = if tailDigits >= 1 do
      if tailDigits <= 3 do
        if e > TemperCore.String.begin() do
          t2 = Temper.MarginaliaCore.isRegexSpace__511(TemperCore.String.get(s, TemperCore.String.prev(s, e)))
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
      ex_loop_138 = fn ex_loop_138, e ->
        if true do
          _t6 = nil
          t6 = if e > TemperCore.String.begin() do
            t6 = Temper.MarginaliaCore.isRegexSpace__511(TemperCore.String.get(s, TemperCore.String.prev(s, e)))
            t6
          else
            t6 = false
            t6
          end
          if not t6 do
            e
          else
            e = TemperCore.String.prev(s, e)
            ex_loop_138.(ex_loop_138, e)
          end
        else
          e
        end
      end
      e = ex_loop_138.(ex_loop_138, e)
      s = TemperCore.String.slice(s, TemperCore.String.begin(), e)
      {e, s}
    else
      {e, s}
    end
    s
  end
  def isCaption__450(line) do
    try do
      _return = nil
      return = if true do
        body = Temper.MarginaliaCore.withoutPageNumbers__451(line)
        letters = 0
        upper = 0
        i = TemperCore.String.begin()
        ex_loop_142 = fn ex_loop_142, i, letters, upper ->
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
            ex_loop_142.(ex_loop_142, i, letters, upper)
          else
            {i, letters, upper}
          end
        end
        {_i, letters, upper} = ex_loop_142.(ex_loop_142, i, letters, upper)
        if letters < 8 do
          return = false
          return
        else
          _ratio = nil
          ratio = try do
            ratio = TemperCore.Float.divide(TemperCore.int_to_float(upper), TemperCore.int_to_float(letters))
            ratio
          rescue
            _ in TemperCore.Bubble ->
              raise(TemperCore.Panic)
          end
          throw({:temper_return, :ex_return_140, TemperCore.Float.ge(ratio, 0.75)})
        end
      end
      return
    catch
      {:temper_return, :ex_return_140, ex_value_144} ->
        ex_value_144
    end
  end
  def isFurniture__446(line) do
    cond do
      Temper.MarginaliaCore.startsWith__518(line, "Cite as:") ->
        true
      line == "Opinion of the Court" ->
        true
      line == "Syllabus" ->
        true
      line == "Per Curiam" ->
        true
      Temper.MarginaliaCore.isJudgeLine__449(line) ->
        true
      Temper.MarginaliaCore.isPageNumber__447(line) ->
        true
      true ->
        Temper.MarginaliaCore.isCaption__450(line)
    end
  end
  def contains__445(chars, cp) do
    try do
      return = nil
      return = try do
        i = TemperCore.String.begin()
        ex_loop_148 = fn ex_loop_148, i, return ->
          if TemperCore.String.has_index(chars, i) do
            if TemperCore.String.get(chars, i) == cp do
              return = true
              throw({:temper_break, :ex_block_147, return})
            else
              i = TemperCore.String.next(chars, i)
              ex_loop_148.(ex_loop_148, i, return)
            end
          else
            {i, return}
          end
        end
        {_i, _return} = ex_loop_148.(ex_loop_148, i, return)
        throw({:temper_return, :ex_return_146, false})
      catch
        {:temper_break, :ex_block_147, ex_vars_150} ->
          ex_vars_150
      end
      return
    catch
      {:temper_return, :ex_return_146, ex_value_151} ->
        ex_value_151
    end
  end
  def allIn__444(s, chars) do
    try do
      return = nil
      return = try do
        i = TemperCore.String.begin()
        ex_loop_154 = fn ex_loop_154, i, return ->
          if TemperCore.String.has_index(s, i) do
            if not Temper.MarginaliaCore.contains__445(chars, TemperCore.String.get(s, i)) do
              return = false
              throw({:temper_break, :ex_block_153, return})
            else
              i = TemperCore.String.next(s, i)
              ex_loop_154.(ex_loop_154, i, return)
            end
          else
            {i, return}
          end
        end
        {_i, _return} = ex_loop_154.(ex_loop_154, i, return)
        throw({:temper_return, :ex_return_152, true})
      catch
        {:temper_break, :ex_block_153, ex_vars_156} ->
          ex_vars_156
      end
      return
    catch
      {:temper_return, :ex_return_152, ex_value_157} ->
        ex_value_157
    end
  end
  def isHeading__443(line) do
    try do
      return = nil
      return = try do
        i = TemperCore.String.begin()
        hashes = 0
        ex_loop_160 = fn ex_loop_160, hashes, i ->
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
              ex_loop_160.(ex_loop_160, hashes, i)
            end
          else
            {hashes, i}
          end
        end
        {hashes, i} = ex_loop_160.(ex_loop_160, hashes, i)
        _t1 = nil
        t1 = if hashes >= 1 do
          if hashes <= 6 do
            if TemperCore.String.has_index(line, i) do
              t1 = Temper.MarginaliaCore.isRegexSpace__511(TemperCore.String.get(line, i))
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
          ex_loop_162 = fn ex_loop_162, i ->
            if true do
              _t4 = nil
              t4 = if TemperCore.String.has_index(line, i) do
                t4 = Temper.MarginaliaCore.isRegexSpace__511(TemperCore.String.get(line, i))
                t4
              else
                t4 = false
                t4
              end
              if not t4 do
                i
              else
                i = TemperCore.String.next(line, i)
                ex_loop_162.(ex_loop_162, i)
              end
            else
              i
            end
          end
          i = ex_loop_162.(ex_loop_162, i)
          if TemperCore.String.has_index(line, i) do
            return = true
            throw({:temper_break, :ex_block_159, return})
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
            t2 = Temper.MarginaliaCore.allIn__444(line, "IVXL")
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
              throw({:temper_return, :ex_return_158, TemperCore.String.get(line, TemperCore.String.begin()) <= 90})
            else
              throw({:temper_return, :ex_return_158, false})
            end
          true ->
            throw({:temper_return, :ex_return_158, false})
        end
      catch
        {:temper_break, :ex_block_159, ex_vars_164} ->
          ex_vars_164
      end
      return
    catch
      {:temper_return, :ex_return_158, ex_value_165} ->
        ex_value_165
    end
  end
  def chunkParagraphs__442(lines, measure) do
    done = TemperCore.List.builder()
    current = TemperCore.List.builder()
    k = 0
    ex_loop_167 = fn ex_loop_167, k ->
      if k < TemperCore.List.length(lines) do
        line = TemperCore.List.get(lines, k)
        cond do
          Temper.MarginaliaCore.isHeading__443(line) ->
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
        ex_loop_167.(ex_loop_167, k)
      else
        k
      end
    end
    _k = ex_loop_167.(ex_loop_167, k)
    TemperCore.List.add(done, TemperCore.List.to_list(current))
    fn_ = fn p ->
      not TemperCore.List.is_empty(p)
    end
    TemperCore.List.filter(TemperCore.List.to_list(done), fn_)
  end
  def measure__441(lines) do
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
          throw({:temper_return, :ex_return_170, TemperCore.List.get(lengths, TemperCore.int32(div(TemperCore.int32(TemperCore.List.length(lengths) * 2), 3)))})
        end
      end
      return
    catch
      {:temper_return, :ex_return_170, ex_value_174} ->
        ex_value_174
    end
  end
  def endsWithAt__519(s, end_, suffix) do
    try do
      return = nil
      return = try do
        i = end_
        j = TemperCore.String.end_of(suffix)
        ex_loop_177 = fn ex_loop_177, i, j, return ->
          if j > TemperCore.String.begin() do
            if i <= TemperCore.String.begin() do
              return = false
              throw({:temper_break, :ex_block_176, return})
            else
              i = TemperCore.String.prev(s, i)
              j = TemperCore.String.prev(suffix, j)
              if TemperCore.String.get(s, i) != TemperCore.String.get(suffix, j) do
                return = false
                throw({:temper_break, :ex_block_176, return})
              else
                ex_loop_177.(ex_loop_177, i, j, return)
              end
            end
          else
            {i, j, return}
          end
        end
        {_i, _j, _return} = ex_loop_177.(ex_loop_177, i, j, return)
        throw({:temper_return, :ex_return_175, true})
      catch
        {:temper_break, :ex_block_176, ex_vars_179} ->
          ex_vars_179
      end
      return
    catch
      {:temper_return, :ex_return_175, ex_value_180} ->
        ex_value_180
    end
  end
  def withoutTrailingHyphens__456(s) do
    e = TemperCore.String.end_of(s)
    ex_loop_182 = fn ex_loop_182, e ->
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
          ex_loop_182.(ex_loop_182, e)
        end
      else
        e
      end
    end
    e = ex_loop_182.(ex_loop_182, e)
    TemperCore.String.slice(s, TemperCore.String.begin(), e)
  end
  def lastAsciiSpaceField__457(s) do
    b = TemperCore.String.end_of(s)
    ex_loop_185 = fn ex_loop_185, b ->
      if true do
        _t = nil
        t = if b > TemperCore.String.begin() do
          t = not Temper.MarginaliaCore.isRegexSpace__511(TemperCore.String.get(s, TemperCore.String.prev(s, b)))
          t
        else
          t = false
          t
        end
        if not t do
          b
        else
          b = TemperCore.String.prev(s, b)
          ex_loop_185.(ex_loop_185, b)
        end
      else
        b
      end
    end
    b = ex_loop_185.(ex_loop_185, b)
    TemperCore.String.slice(s, b, TemperCore.String.end_of(s))
  end
  def firstAsciiSpaceField__458(s) do
    e = TemperCore.String.begin()
    ex_loop_188 = fn ex_loop_188, e ->
      if true do
        _t = nil
        t = if TemperCore.String.has_index(s, e) do
          t = not Temper.MarginaliaCore.isRegexSpace__511(TemperCore.String.get(s, e))
          t
        else
          t = false
          t
        end
        if not t do
          e
        else
          e = TemperCore.String.next(s, e)
          ex_loop_188.(ex_loop_188, e)
        end
      else
        e
      end
    end
    e = ex_loop_188.(ex_loop_188, e)
    TemperCore.String.slice(s, TemperCore.String.begin(), e)
  end
  def stripTrailingPunct__459(word) do
    e = TemperCore.String.end_of(word)
    ex_loop_191 = fn ex_loop_191, e ->
      if true do
        _t = nil
        t = if e > TemperCore.String.begin() do
          if not Temper.MarginaliaCore.isWordChar__452(TemperCore.String.get(word, TemperCore.String.prev(word, e))) do
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
          ex_loop_191.(ex_loop_191, e)
        end
      else
        e
      end
    end
    e = ex_loop_191.(ex_loop_191, e)
    TemperCore.String.slice(word, TemperCore.String.begin(), e)
  end
  def mend__455(acc, line, keep) do
    unhyphened = Temper.MarginaliaCore.withoutTrailingHyphens__456(acc)
    stem = Temper.MarginaliaCore.lastAsciiSpaceField__457(unhyphened)
    head = Temper.MarginaliaCore.firstAsciiSpaceField__458(line)
    word = Temper.MarginaliaCore.downcase(stem <> "-" <> Temper.MarginaliaCore.stripTrailingPunct__459(head))
    if TemperCore.Map.has(keep, word) do
      acc <> line
    else
      unhyphened <> line
    end
  end
  def join__454(lines, keep) do
    acc = ""
    k = 0
    ex_loop_195 = fn ex_loop_195, acc, k ->
      if k < TemperCore.List.length(lines) do
        line = TemperCore.List.get(lines, k)
        acc = cond do
          TemperCore.String.is_empty(acc) ->
            acc = line
            acc
          Temper.MarginaliaCore.endsWithAt__519(acc, TemperCore.String.end_of(acc), "-") ->
            acc = Temper.MarginaliaCore.mend__455(acc, line, keep)
            acc
          true ->
            acc = acc <> " " <> line
            acc
        end
        k = TemperCore.int32(k + 1)
        ex_loop_195.(ex_loop_195, acc, k)
      else
        {acc, k}
      end
    end
    {acc, _k} = ex_loop_195.(ex_loop_195, acc, k)
    Temper.MarginaliaCore.trim__513(acc)
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
            keep = Temper.MarginaliaCore.intactHyphens__453(text)
            raw = TemperCore.String.split(Temper.MarginaliaCore.normalizeNewlines__440(text), "\n")
            lines = TemperCore.List.builder()
            k1 = 0
            ex_loop_199 = fn ex_loop_199, k1 ->
              if k1 < TemperCore.List.length(raw) do
                line = Temper.MarginaliaCore.trim__513(TemperCore.List.get(raw, k1))
                _t = nil
                t = if not Temper.MarginaliaCore.isFurniture__446(line) do
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
                ex_loop_199.(ex_loop_199, k1)
              else
                k1
              end
            end
            _k1 = ex_loop_199.(ex_loop_199, k1)
            all = TemperCore.List.to_list(lines)
            paragraphs = Temper.MarginaliaCore.chunkParagraphs__442(all, Temper.MarginaliaCore.measure__441(all))
            out = TemperCore.List.builder()
            k2 = 0
            ex_loop_201 = fn ex_loop_201, k2 ->
              if k2 < TemperCore.List.length(paragraphs) do
                p = Temper.MarginaliaCore.join__454(TemperCore.List.get(paragraphs, k2), keep)
                if not TemperCore.String.is_empty(p) do
                  TemperCore.List.add(out, p)
                  nil
                else
                  nil
                end
                k2 = TemperCore.int32(k2 + 1)
                ex_loop_201.(ex_loop_201, k2)
              else
                k2
              end
            end
            _k2 = ex_loop_201.(ex_loop_201, k2)
            throw({:temper_return, :ex_return_197, Temper.MarginaliaCore.joinWith__520(TemperCore.List.to_list(out), "\n\n")})
          end
        end
        return
      catch
        {:temper_return, :ex_return_197, ex_value_203} ->
          ex_value_203
      end
    end)
  end
  def align(quote_, source) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      raw = TemperCore.String.split(Temper.MarginaliaCore.normalizeNewlines__440(quote_), "\n")
      lines = TemperCore.List.builder()
      k = 0
      ex_loop_205 = fn ex_loop_205, k ->
        if k < TemperCore.List.length(raw) do
          line = Temper.MarginaliaCore.trim__513(TemperCore.List.get(raw, k))
          if not TemperCore.String.is_empty(line) do
            TemperCore.List.add(lines, line)
            nil
          else
            nil
          end
          k = TemperCore.int32(k + 1)
          ex_loop_205.(ex_loop_205, k)
        else
          k
        end
      end
      _k = ex_loop_205.(ex_loop_205, k)
      Temper.MarginaliaCore.join__454(TemperCore.List.to_list(lines), Temper.MarginaliaCore.intactHyphens__453(source))
    end)
  end
  def graphemePrefix(s, n) do
    TemperConnected.graphemePrefix(s, n)
  end
  def normalize__462(raw) do
    unixed = Temper.MarginaliaCore.joinWith__520(TemperCore.String.split(Temper.MarginaliaCore.joinWith__520(TemperCore.String.split(raw, "\r\n"), "\n"), "\r"), "\n")
    out = TemperCore.StringBuilder.new()
    newlines = 0
    i = TemperCore.String.begin()
    ex_loop_227 = fn ex_loop_227, i, newlines ->
      if TemperCore.String.has_index(unixed, i) do
        cp = TemperCore.String.get(unixed, i)
        newlines = if cp == 10 do
          newlines = TemperCore.int32(newlines + 1)
          newlines
        else
          if newlines >= 3 do
            TemperCore.StringBuilder.append(out, "\n\n")
            nil
          else
            k2 = 0
            ex_loop_229 = fn ex_loop_229, k2 ->
              if k2 < newlines do
                TemperCore.StringBuilder.append(out, "\n")
                k2 = TemperCore.int32(k2 + 1)
                ex_loop_229.(ex_loop_229, k2)
              else
                k2
              end
            end
            _k2 = ex_loop_229.(ex_loop_229, k2)
            nil
          end
          newlines = 0
          try do
            TemperCore.StringBuilder.append_code_point(out, cp)
            nil
          rescue
            _ in TemperCore.Bubble ->
              raise(TemperCore.Bubble)
          end
          newlines
        end
        i = TemperCore.String.next(unixed, i)
        ex_loop_227.(ex_loop_227, i, newlines)
      else
        {i, newlines}
      end
    end
    {_i, newlines} = ex_loop_227.(ex_loop_227, i, newlines)
    if newlines >= 3 do
      TemperCore.StringBuilder.append(out, "\n\n")
      nil
    else
      k1 = 0
      ex_loop_231 = fn ex_loop_231, k1 ->
        if k1 < newlines do
          TemperCore.StringBuilder.append(out, "\n")
          k1 = TemperCore.int32(k1 + 1)
          ex_loop_231.(ex_loop_231, k1)
        else
          k1
        end
      end
      _k1 = ex_loop_231.(ex_loop_231, k1)
      nil
    end
    Temper.MarginaliaCore.trim__513(TemperCore.StringBuilder.to_string(out))
  end
  def isMarkdownHead__463(line) do
    try do
      _return = nil
      return = if true do
        i = TemperCore.String.begin()
        hashes = 0
        ex_loop_235 = fn ex_loop_235, hashes, i ->
          if true do
            _t2 = nil
            t2 = if TemperCore.String.has_index(line, i) do
              t2 = TemperCore.String.get(line, i) == 35
              t2
            else
              t2 = false
              t2
            end
            if not t2 do
              {hashes, i}
            else
              hashes = TemperCore.int32(hashes + 1)
              i = TemperCore.String.next(line, i)
              ex_loop_235.(ex_loop_235, hashes, i)
            end
          else
            {hashes, i}
          end
        end
        {hashes, i} = ex_loop_235.(ex_loop_235, hashes, i)
        _t1 = nil
        t1 = cond do
          hashes < 1 ->
            t1 = true
            t1
          hashes > 3 ->
            t1 = true
            t1
          not TemperCore.String.has_index(line, i) ->
            t1 = true
            t1
          true ->
            t1 = not Temper.MarginaliaCore.isRegexSpace__511(TemperCore.String.get(line, i))
            t1
        end
        if t1 do
          return = false
          return
        else
          ex_loop_237 = fn ex_loop_237, i ->
            if true do
              _t3 = nil
              t3 = if TemperCore.String.has_index(line, i) do
                t3 = Temper.MarginaliaCore.isRegexSpace__511(TemperCore.String.get(line, i))
                t3
              else
                t3 = false
                t3
              end
              if not t3 do
                i
              else
                i = TemperCore.String.next(line, i)
                ex_loop_237.(ex_loop_237, i)
              end
            else
              i
            end
          end
          i = ex_loop_237.(ex_loop_237, i)
          throw({:temper_return, :ex_return_233, TemperCore.String.has_index(line, i)})
        end
      end
      return
    catch
      {:temper_return, :ex_return_233, ex_value_239} ->
        ex_value_239
    end
  end
  def wordCount__478(s) do
    n = 0
    inWord = false
    i = TemperCore.String.begin()
    ex_loop_241 = fn ex_loop_241, i, inWord, n ->
      if TemperCore.String.has_index(s, i) do
        {inWord, n} = if Temper.MarginaliaCore.isRegexSpace__511(TemperCore.String.get(s, i)) do
          inWord = false
          {inWord, n}
        else
          n = if not inWord do
            n = TemperCore.int32(n + 1)
            n
          else
            n
          end
          inWord = true
          {inWord, n}
        end
        i = TemperCore.String.next(s, i)
        ex_loop_241.(ex_loop_241, i, inWord, n)
      else
        {i, inWord, n}
      end
    end
    {_i, _inWord, n} = ex_loop_241.(ex_loop_241, i, inWord, n)
    n
  end
  def paragraphPieces__476(text) do
    out = TemperCore.List.builder()
    start = TemperCore.String.begin()
    i = TemperCore.String.begin()
    ex_loop_244 = fn ex_loop_244, i, start ->
      if TemperCore.String.has_index(text, i) do
        if Temper.MarginaliaCore.isRegexSpace__511(TemperCore.String.get(text, i)) do
          runStart = i
          newlines = 0
          lastNewline = i
          ex_loop_246 = fn ex_loop_246, i, lastNewline, newlines ->
            if true do
              _t = nil
              t = if TemperCore.String.has_index(text, i) do
                t = Temper.MarginaliaCore.isRegexSpace__511(TemperCore.String.get(text, i))
                t
              else
                t = false
                t
              end
              if not t do
                {i, lastNewline, newlines}
              else
                {lastNewline, newlines} = if TemperCore.String.get(text, i) == 10 do
                  newlines = TemperCore.int32(newlines + 1)
                  lastNewline = i
                  {lastNewline, newlines}
                else
                  {lastNewline, newlines}
                end
                i = TemperCore.String.next(text, i)
                ex_loop_246.(ex_loop_246, i, lastNewline, newlines)
              end
            else
              {i, lastNewline, newlines}
            end
          end
          {i, lastNewline, newlines} = ex_loop_246.(ex_loop_246, i, lastNewline, newlines)
          if newlines >= 2 do
            firstNewline = runStart
            ex_loop_248 = fn ex_loop_248, firstNewline ->
              if TemperCore.String.get(text, firstNewline) != 10 do
                firstNewline = TemperCore.String.next(text, firstNewline)
                ex_loop_248.(ex_loop_248, firstNewline)
              else
                firstNewline
              end
            end
            firstNewline = ex_loop_248.(ex_loop_248, firstNewline)
            piece = TemperCore.String.slice(text, start, firstNewline)
            if not TemperCore.String.is_empty(piece) do
              TemperCore.List.add(out, piece)
              nil
            else
              nil
            end
            start = TemperCore.String.next(text, lastNewline)
            ex_loop_244.(ex_loop_244, i, start)
          else
            ex_loop_244.(ex_loop_244, i, start)
          end
        else
          i = TemperCore.String.next(text, i)
          ex_loop_244.(ex_loop_244, i, start)
        end
      else
        {i, start}
      end
    end
    {_i, start} = ex_loop_244.(ex_loop_244, i, start)
    last = TemperCore.String.slice(text, start, TemperCore.String.end_of(text))
    if not TemperCore.String.is_empty(last) do
      TemperCore.List.add(out, last)
      nil
    else
      nil
    end
    TemperCore.List.to_list(out)
  end
  def window__477(text) do
    pieces = Temper.MarginaliaCore.paragraphPieces__476(text)
    windows = TemperCore.List.builder()
    k = 0
    ex_loop_251 = fn ex_loop_251, k ->
      if k < TemperCore.List.length(pieces) do
        para = Temper.MarginaliaCore.trim__513(TemperCore.List.get(pieces, k))
        words = Temper.MarginaliaCore.wordCount__478(para)
        n = TemperCore.List.length(windows)
        _t = nil
        t = if n > 0 do
          t = Temper.MarginaliaCore.Window.get_words(TemperCore.List.get(windows, TemperCore.int32(n - 1))) < 1800
          t
        else
          t = false
          t
        end
        if t do
          head = TemperCore.List.get(windows, TemperCore.int32(n - 1))
          TemperCore.List.add(Temper.MarginaliaCore.Window.get_paras(head), para)
          TemperCore.List.set(windows, TemperCore.int32(n - 1), Temper.MarginaliaCore.Window.new(Temper.MarginaliaCore.Window.get_paras(head), TemperCore.int32(Temper.MarginaliaCore.Window.get_words(head) + words)))
          nil
        else
          paras = TemperCore.List.builder()
          TemperCore.List.add(paras, para)
          TemperCore.List.add(windows, Temper.MarginaliaCore.Window.new(paras, words))
          nil
        end
        k = TemperCore.int32(k + 1)
        ex_loop_251.(ex_loop_251, k)
      else
        k
      end
    end
    _k = ex_loop_251.(ex_loop_251, k)
    fn_ = fn w ->
      Temper.MarginaliaCore.joinWith__520(TemperCore.List.to_list(Temper.MarginaliaCore.Window.get_paras(w)), "\n\n")
    end
    TemperCore.List.map(TemperCore.List.to_list(windows), fn_)
  end
  def subdivide__481(chunk) do
    try do
      _return = nil
      return = if true do
        if Temper.MarginaliaCore.wordCount__478(Temper.MarginaliaCore.Section.get_body(chunk)) <= 4000 do
          return = %TemperCore.Vec{t: {chunk}}
          return
        else
          parts = Temper.MarginaliaCore.window__477(Temper.MarginaliaCore.Section.get_body(chunk))
          n = TemperCore.List.length(parts)
          if n < 2 do
            return = %TemperCore.Vec{t: {chunk}}
            return
          else
            out = TemperCore.List.builder()
            k = 0
            ex_loop_256 = fn ex_loop_256, k ->
              if k < n do
                TemperCore.List.add(out, Temper.MarginaliaCore.Section.new(Temper.MarginaliaCore.Section.get_title(chunk) <> " (" <> TemperCore.int_to_string(TemperCore.int32(k + 1)) <> "/" <> TemperCore.int_to_string(n) <> ")", TemperCore.List.get(parts, k)))
                k = TemperCore.int32(k + 1)
                ex_loop_256.(ex_loop_256, k)
              else
                k
              end
            end
            _k = ex_loop_256.(ex_loop_256, k)
            throw({:temper_return, :ex_return_254, TemperCore.List.to_list(out)})
          end
        end
      end
      return
    catch
      {:temper_return, :ex_return_254, ex_value_258} ->
        ex_value_258
    end
  end
  def finish__480(chunks) do
    kept = TemperCore.List.builder()
    k1 = 0
    ex_loop_260 = fn ex_loop_260, k1 ->
      if k1 < TemperCore.List.length(chunks) do
        if true do
          chunk = TemperCore.List.get(chunks, k1)
          if TemperCore.String.is_empty(Temper.MarginaliaCore.trim__513(Temper.MarginaliaCore.Section.get_body(chunk))) do
            nil
          else
            n = TemperCore.List.length(kept)
            _t = nil
            t = if n > 0 do
              if Temper.MarginaliaCore.wordCount__478(Temper.MarginaliaCore.Section.get_body(chunk)) < 250 do
                t = Temper.MarginaliaCore.wordCount__478(Temper.MarginaliaCore.Section.get_body(TemperCore.List.get(kept, TemperCore.int32(n - 1)))) < 1800
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
              prev = TemperCore.List.get(kept, TemperCore.int32(n - 1))
              TemperCore.List.set(kept, TemperCore.int32(n - 1), Temper.MarginaliaCore.Section.new(Temper.MarginaliaCore.Section.get_title(prev), Temper.MarginaliaCore.Section.get_body(prev) <> "\n" <> "\n" <> Temper.MarginaliaCore.Section.get_body(chunk)))
              nil
            else
              TemperCore.List.add(kept, chunk)
              nil
            end
          end
        end
        k1 = TemperCore.int32(k1 + 1)
        ex_loop_260.(ex_loop_260, k1)
      else
        k1
      end
    end
    _k1 = ex_loop_260.(ex_loop_260, k1)
    out = TemperCore.List.builder()
    all = TemperCore.List.to_list(kept)
    k2 = 0
    ex_loop_263 = fn ex_loop_263, k2 ->
      if k2 < TemperCore.List.length(all) do
        TemperCore.List.add_all(out, Temper.MarginaliaCore.subdivide__481(TemperCore.List.get(all, k2)))
        k2 = TemperCore.int32(k2 + 1)
        ex_loop_263.(ex_loop_263, k2)
      else
        k2
      end
    end
    _k2 = ex_loop_263.(ex_loop_263, k2)
    if TemperCore.List.is_empty(out) do
      nil
    else
      TemperCore.List.to_list(out)
    end
  end
  def asciiCaselessPrefix__471(line, at, word) do
    try do
      return = nil
      return = try do
        i = at
        j = TemperCore.String.begin()
        ex_loop_267 = fn ex_loop_267, i, j, return ->
          if TemperCore.String.has_index(word, j) do
            if not TemperCore.String.has_index(line, i) do
              return = nil
              throw({:temper_break, :ex_block_266, return})
            else
              cp = TemperCore.String.get(line, i)
              _t = nil
              t = if cp >= 65 do
                t = cp <= 90
                t
              else
                t = false
                t
              end
              cp = if t do
                cp = TemperCore.int32(cp + 32)
                cp
              else
                cp
              end
              if cp != TemperCore.String.get(word, j) do
                return = nil
                throw({:temper_break, :ex_block_266, return})
              else
                i = TemperCore.String.next(line, i)
                j = TemperCore.String.next(word, j)
                ex_loop_267.(ex_loop_267, i, j, return)
              end
            end
          else
            {i, j, return}
          end
        end
        {i, _j, _return} = ex_loop_267.(ex_loop_267, i, j, return)
        throw({:temper_return, :ex_return_265, i})
      catch
        {:temper_break, :ex_block_266, ex_vars_269} ->
          ex_vars_269
      end
      return
    catch
      {:temper_return, :ex_return_265, ex_value_270} ->
        ex_value_270
    end
  end
  def isAsciiLetter__469(cp) do
    _t = nil
    t = if cp >= 65 do
      t = cp <= 90
      t
    else
      t = false
      t
    end
    cond do
      t ->
        true
      cp >= 97 ->
        cp <= 122
      true ->
        false
    end
  end
  def isRomanLetter__470(cp) do
    cond do
      cp == 73 ->
        true
      cp == 86 ->
        true
      cp == 88 ->
        true
      cp == 76 ->
        true
      cp == 67 ->
        true
      cp == 105 ->
        true
      cp == 118 ->
        true
      cp == 120 ->
        true
      cp == 108 ->
        true
      true ->
        cp == 99
    end
  end
  def markerHead__468(line, at) do
    try do
      return = nil
      return = try do
        keywords = %TemperCore.Vec{t: {"chapter", "part", "book", "act", "section"}}
        k = 0
        ex_loop_275 = fn ex_loop_275, k, return ->
          if k < TemperCore.List.length(keywords) do
            after_1 = Temper.MarginaliaCore.asciiCaselessPrefix__471(line, at, TemperCore.List.get(keywords, k))
            return = if not (after_1 === nil) do
              after_2 = after_1
              i = after_2
              spaces = 0
              ex_loop_277 = fn ex_loop_277, i, spaces ->
                if true do
                  _t8 = nil
                  t8 = if TemperCore.String.has_index(line, i) do
                    t8 = Temper.MarginaliaCore.isRegexSpace__511(TemperCore.String.get(line, i))
                    t8
                  else
                    t8 = false
                    t8
                  end
                  if not t8 do
                    {i, spaces}
                  else
                    spaces = TemperCore.int32(spaces + 1)
                    i = TemperCore.String.next(line, i)
                    ex_loop_277.(ex_loop_277, i, spaces)
                  end
                else
                  {i, spaces}
                end
              end
              {i, spaces} = ex_loop_277.(ex_loop_277, i, spaces)
              _t6 = nil
              t6 = if spaces >= 1 do
                t6 = TemperCore.String.has_index(line, i)
                t6
              else
                t6 = false
                t6
              end
              if t6 do
                cp = TemperCore.String.get(line, i)
                _t9 = nil
                t9 = if cp >= 48 do
                  t9 = cp <= 57
                  t9
                else
                  t9 = false
                  t9
                end
                cond do
                  t9 ->
                    ex_loop_279 = fn ex_loop_279, i ->
                      if true do
                        _t11 = nil
                        t11 = if TemperCore.String.has_index(line, i) do
                          if TemperCore.String.get(line, i) >= 48 do
                            t11 = TemperCore.String.get(line, i) <= 57
                            t11
                          else
                            t11 = false
                            t11
                          end
                        else
                          t11 = false
                          t11
                        end
                        if not t11 do
                          i
                        else
                          i = TemperCore.String.next(line, i)
                          ex_loop_279.(ex_loop_279, i)
                        end
                      else
                        i
                      end
                    end
                    i = ex_loop_279.(ex_loop_279, i)
                    return = i
                    throw({:temper_break, :ex_block_274, return})
                  Temper.MarginaliaCore.isAsciiLetter__469(cp) ->
                    ex_loop_281 = fn ex_loop_281, i ->
                      if true do
                        _t12 = nil
                        t12 = if TemperCore.String.has_index(line, i) do
                          t12 = Temper.MarginaliaCore.isAsciiLetter__469(TemperCore.String.get(line, i))
                          t12
                        else
                          t12 = false
                          t12
                        end
                        if not t12 do
                          i
                        else
                          i = TemperCore.String.next(line, i)
                          ex_loop_281.(ex_loop_281, i)
                        end
                      else
                        i
                      end
                    end
                    i = ex_loop_281.(ex_loop_281, i)
                    return = i
                    throw({:temper_break, :ex_block_274, return})
                  true ->
                    return
                end
              else
                return
              end
            else
              return
            end
            k = TemperCore.int32(k + 1)
            ex_loop_275.(ex_loop_275, k, return)
          else
            {k, return}
          end
        end
        {_k, return} = ex_loop_275.(ex_loop_275, k, return)
        r = at
        romans = 0
        ex_loop_283 = fn ex_loop_283, r, romans ->
          if true do
            _t3 = nil
            t3 = if TemperCore.String.has_index(line, r) do
              t3 = Temper.MarginaliaCore.isRomanLetter__470(TemperCore.String.get(line, r))
              t3
            else
              t3 = false
              t3
            end
            if not t3 do
              {r, romans}
            else
              romans = TemperCore.int32(romans + 1)
              r = TemperCore.String.next(line, r)
              ex_loop_283.(ex_loop_283, r, romans)
            end
          else
            {r, romans}
          end
        end
        {r, romans} = ex_loop_283.(ex_loop_283, r, romans)
        _t1 = nil
        t1 = if romans >= 1 do
          if romans <= 7 do
            if TemperCore.String.has_index(line, r) do
              t1 = TemperCore.String.get(line, r) == 46
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
        if t1 do
          return = TemperCore.String.next(line, r)
          return
        else
          _t2 = nil
          t2 = if TemperCore.String.has_index(line, at) do
            t2 = TemperCore.String.get(line, at) == 42
            t2
          else
            t2 = false
            t2
          end
          _return = if t2 do
            s = TemperCore.String.next(line, at)
            stars = 1
            ex_loop_285 = fn ex_loop_285, s, stars ->
              if stars < 3 do
                ex_loop_287 = fn ex_loop_287, s ->
                  if true do
                    _t10 = nil
                    t10 = if TemperCore.String.has_index(line, s) do
                      t10 = Temper.MarginaliaCore.isRegexSpace__511(TemperCore.String.get(line, s))
                      t10
                    else
                      t10 = false
                      t10
                    end
                    if not t10 do
                      s
                    else
                      s = TemperCore.String.next(line, s)
                      ex_loop_287.(ex_loop_287, s)
                    end
                  else
                    s
                  end
                end
                s = ex_loop_287.(ex_loop_287, s)
                _t7 = nil
                t7 = if not TemperCore.String.has_index(line, s) do
                  t7 = true
                  t7
                else
                  t7 = TemperCore.String.get(line, s) != 42
                  t7
                end
                if t7 do
                  {s, stars}
                else
                  stars = TemperCore.int32(stars + 1)
                  s = TemperCore.String.next(line, s)
                  ex_loop_285.(ex_loop_285, s, stars)
                end
              else
                {s, stars}
              end
            end
            {s, stars} = ex_loop_285.(ex_loop_285, s, stars)
            if stars == 3 do
              return = s
              throw({:temper_break, :ex_block_274, return})
            else
              return
            end
          else
            return
          end
          m = at
          emDashes = 0
          ex_loop_289 = fn ex_loop_289, emDashes, m ->
            if true do
              _t4 = nil
              t4 = if TemperCore.String.has_index(line, m) do
                t4 = TemperCore.String.get(line, m) == 8212
                t4
              else
                t4 = false
                t4
              end
              if not t4 do
                {emDashes, m}
              else
                emDashes = TemperCore.int32(emDashes + 1)
                m = TemperCore.String.next(line, m)
                ex_loop_289.(ex_loop_289, emDashes, m)
              end
            else
              {emDashes, m}
            end
          end
          {emDashes, m} = ex_loop_289.(ex_loop_289, emDashes, m)
          if emDashes >= 3 do
            return = m
            return
          else
            d = at
            dashes = 0
            ex_loop_291 = fn ex_loop_291, d, dashes ->
              if true do
                _t5 = nil
                t5 = if TemperCore.String.has_index(line, d) do
                  t5 = TemperCore.String.get(line, d) == 45
                  t5
                else
                  t5 = false
                  t5
                end
                if not t5 do
                  {d, dashes}
                else
                  dashes = TemperCore.int32(dashes + 1)
                  d = TemperCore.String.next(line, d)
                  ex_loop_291.(ex_loop_291, d, dashes)
                end
              else
                {d, dashes}
              end
            end
            {d, dashes} = ex_loop_291.(ex_loop_291, d, dashes)
            if dashes >= 3 do
              return = d
              return
            else
              throw({:temper_return, :ex_return_273, nil})
            end
          end
        end
      catch
        {:temper_break, :ex_block_274, ex_vars_293} ->
          ex_vars_293
      end
      return
    catch
      {:temper_return, :ex_return_273, ex_value_294} ->
        ex_value_294
    end
  end
  def utf8Length__467(s, from) do
    n = 0
    i = from
    ex_loop_296 = fn ex_loop_296, i, n ->
      if TemperCore.String.has_index(s, i) do
        _t1 = nil
        cp = TemperCore.String.get(s, i)
        t2 = n
        t1 = cond do
          cp < 128 ->
            t1 = 1
            t1
          cp < 2048 ->
            t1 = 2
            t1
          cp < 65536 ->
            t1 = 3
            t1
          true ->
            t1 = 4
            t1
        end
        n = TemperCore.int32(t2 + t1)
        i = TemperCore.String.next(s, i)
        ex_loop_296.(ex_loop_296, i, n)
      else
        {i, n}
      end
    end
    {_i, n} = ex_loop_296.(ex_loop_296, i, n)
    n
  end
  def isMarker__466(line) do
    try do
      _return = nil
      return = if true do
        _t1 = nil
        if Temper.MarginaliaCore.graphemeLength(Temper.MarginaliaCore.trim__513(line)) >= 90 do
          return = false
          return
        else
          i = TemperCore.String.begin()
          ex_loop_300 = fn ex_loop_300, i ->
            if true do
              _t2 = nil
              t2 = if TemperCore.String.has_index(line, i) do
                t2 = Temper.MarginaliaCore.isRegexSpace__511(TemperCore.String.get(line, i))
                t2
              else
                t2 = false
                t2
              end
              if not t2 do
                i
              else
                i = TemperCore.String.next(line, i)
                ex_loop_300.(ex_loop_300, i)
              end
            else
              i
            end
          end
          i = ex_loop_300.(ex_loop_300, i)
          head = Temper.MarginaliaCore.markerHead__468(line, i)
          if head === nil do
            return = false
            return
          else
            t1 = try do
              if head === nil do
                raise(TemperCore.Bubble)
              else
                t1 = head
                t1
              end
            rescue
              _ in TemperCore.Bubble ->
                raise(TemperCore.Panic)
            end
            i = t1
            ex_loop_302 = fn ex_loop_302, i ->
              if true do
                _t3 = nil
                t3 = if TemperCore.String.has_index(line, i) do
                  t3 = Temper.MarginaliaCore.isRegexSpace__511(TemperCore.String.get(line, i))
                  t3
                else
                  t3 = false
                  t3
                end
                if not t3 do
                  i
                else
                  i = TemperCore.String.next(line, i)
                  ex_loop_302.(ex_loop_302, i)
                end
              else
                i
              end
            end
            i = ex_loop_302.(ex_loop_302, i)
            spare = 0
            {i, spare} = if TemperCore.String.has_index(line, i) do
              cp = TemperCore.String.get(line, i)
              _t4 = nil
              t4 = cond do
                cp == 58 ->
                  t4 = true
                  t4
                cp == 46 ->
                  t4 = true
                  t4
                true ->
                  t4 = cp == 45
                  t4
              end
              if t4 do
                i = TemperCore.String.next(line, i)
                ex_loop_304 = fn ex_loop_304, i ->
                  if true do
                    _t6 = nil
                    t6 = if TemperCore.String.has_index(line, i) do
                      t6 = Temper.MarginaliaCore.isRegexSpace__511(TemperCore.String.get(line, i))
                      t6
                    else
                      t6 = false
                      t6
                    end
                    if not t6 do
                      i
                    else
                      i = TemperCore.String.next(line, i)
                      ex_loop_304.(ex_loop_304, i)
                    end
                  else
                    i
                  end
                end
                i = ex_loop_304.(ex_loop_304, i)
                {i, spare}
              else
                _t5 = nil
                t5 = if cp >= 8192 do
                  t5 = cp <= 12287
                  t5
                else
                  t5 = false
                  t5
                end
                if t5 do
                  spare = 1
                  {i, spare}
                else
                  {i, spare}
                end
              end
            else
              {i, spare}
            end
            throw({:temper_return, :ex_return_298, TemperCore.int32(Temper.MarginaliaCore.utf8Length__467(line, i) - spare) <= 80})
          end
        end
      end
      return
    catch
      {:temper_return, :ex_return_298, ex_value_306} ->
        ex_value_306
    end
  end
  def markdownTitle__464(line) do
    i = TemperCore.String.begin()
    ex_loop_308 = fn ex_loop_308, i ->
      if true do
        _t1 = nil
        t1 = if TemperCore.String.has_index(line, i) do
          t1 = TemperCore.String.get(line, i) == 35
          t1
        else
          t1 = false
          t1
        end
        if not t1 do
          i
        else
          i = TemperCore.String.next(line, i)
          ex_loop_308.(ex_loop_308, i)
        end
      else
        i
      end
    end
    i = ex_loop_308.(ex_loop_308, i)
    ex_loop_310 = fn ex_loop_310, i ->
      if true do
        _t2 = nil
        t2 = if TemperCore.String.has_index(line, i) do
          t2 = Temper.MarginaliaCore.isRegexSpace__511(TemperCore.String.get(line, i))
          t2
        else
          t2 = false
          t2
        end
        if not t2 do
          i
        else
          i = TemperCore.String.next(line, i)
          ex_loop_310.(ex_loop_310, i)
        end
      else
        i
      end
    end
    i = ex_loop_310.(ex_loop_310, i)
    Temper.MarginaliaCore.trim__513(TemperCore.String.slice(line, i, TemperCore.String.end_of(line)))
  end
  def untitledIfBlank__474(title) do
    if TemperCore.String.is_empty(title) do
      "Untitled"
    else
      Temper.MarginaliaCore.graphemePrefix(title, 120)
    end
  end
  def chunkOn__473(lines, markdown) do
    chunks = TemperCore.List.builder()
    k = 0
    ex_loop_314 = fn ex_loop_314, k ->
      if k < TemperCore.List.length(lines) do
        line = TemperCore.List.get(lines, k)
        _isHead = nil
        isHead = if markdown do
          isHead = Temper.MarginaliaCore.isMarkdownHead__463(line)
          isHead
        else
          isHead = Temper.MarginaliaCore.isMarker__466(line)
          isHead
        end
        cond do
          isHead ->
            _title = nil
            title = if markdown do
              title = Temper.MarginaliaCore.markdownTitle__464(line)
              title
            else
              title = Temper.MarginaliaCore.trim__513(line)
              title
            end
            TemperCore.List.add(chunks, Temper.MarginaliaCore.HeadChunk.new(title, TemperCore.List.builder()))
            nil
          TemperCore.List.is_empty(chunks) ->
            first = TemperCore.List.builder()
            TemperCore.List.add(first, line)
            TemperCore.List.add(chunks, Temper.MarginaliaCore.HeadChunk.new("Opening", first))
            nil
          true ->
            TemperCore.List.add(Temper.MarginaliaCore.HeadChunk.get_lines(TemperCore.List.get(chunks, TemperCore.int32(TemperCore.List.length(chunks) - 1))), line)
            nil
        end
        k = TemperCore.int32(k + 1)
        ex_loop_314.(ex_loop_314, k)
      else
        k
      end
    end
    _k = ex_loop_314.(ex_loop_314, k)
    fn_ = fn c ->
      Temper.MarginaliaCore.Section.new(Temper.MarginaliaCore.untitledIfBlank__474(Temper.MarginaliaCore.HeadChunk.get_title(c)), Temper.MarginaliaCore.trim__513(Temper.MarginaliaCore.joinWith__520(TemperCore.List.to_list(Temper.MarginaliaCore.HeadChunk.get_lines(c)), "\n")))
    end
    TemperCore.List.map(TemperCore.List.to_list(chunks), fn_)
  end
  def byMarkdown__465(text) do
    try do
      _return = nil
      return = if true do
        lines = TemperCore.String.split(text, "\n")
        fn_ = fn l ->
          Temper.MarginaliaCore.isMarkdownHead__463(l)
        end
        if TemperCore.List.length(TemperCore.List.filter(lines, fn_)) < 2 do
          return = nil
          return
        else
          throw({:temper_return, :ex_return_317, Temper.MarginaliaCore.finish__480(Temper.MarginaliaCore.chunkOn__473(lines, true))})
        end
      end
      return
    catch
      {:temper_return, :ex_return_317, ex_value_320} ->
        ex_value_320
    end
  end
  def byMarker__472(text) do
    try do
      _return = nil
      return = if true do
        lines = TemperCore.String.split(text, "\n")
        fn_ = fn l ->
          Temper.MarginaliaCore.isMarker__466(l)
        end
        if TemperCore.List.length(TemperCore.List.filter(lines, fn_)) < 2 do
          return = nil
          return
        else
          throw({:temper_return, :ex_return_321, Temper.MarginaliaCore.finish__480(Temper.MarginaliaCore.chunkOn__473(lines, false))})
        end
      end
      return
    catch
      {:temper_return, :ex_return_321, ex_value_324} ->
        ex_value_324
    end
  end
  def allOf__498(s, from, to, cp) do
    try do
      return = nil
      return = try do
        i = from
        ex_loop_327 = fn ex_loop_327, i, return ->
          if i < to do
            if TemperCore.String.get(s, i) != cp do
              return = false
              throw({:temper_break, :ex_block_326, return})
            else
              i = TemperCore.String.next(s, i)
              ex_loop_327.(ex_loop_327, i, return)
            end
          else
            {i, return}
          end
        end
        {_i, _return} = ex_loop_327.(ex_loop_327, i, return)
        throw({:temper_return, :ex_return_325, true})
      catch
        {:temper_break, :ex_block_326, ex_vars_329} ->
          ex_vars_329
      end
      return
    catch
      {:temper_return, :ex_return_325, ex_value_330} ->
        ex_value_330
    end
  end
  def isUnderline__497(s) do
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
            throw({:temper_return, :ex_return_331, Temper.MarginaliaCore.allOf__498(s, TemperCore.String.begin(), TemperCore.String.end_of(s), mark)})
          end
        end
      end
      return
    catch
      {:temper_return, :ex_return_331, ex_value_333} ->
        ex_value_333
    end
  end
  def delimiterCell__500(s, at) do
    try do
      _return = nil
      return = if true do
        i = at
        ex_loop_336 = fn ex_loop_336, i ->
          if true do
            _t3 = nil
            t3 = if TemperCore.String.has_index(s, i) do
              t3 = Temper.MarginaliaCore.isRegexSpace__511(TemperCore.String.get(s, i))
              t3
            else
              t3 = false
              t3
            end
            if not t3 do
              i
            else
              i = TemperCore.String.next(s, i)
              ex_loop_336.(ex_loop_336, i)
            end
          else
            i
          end
        end
        i = ex_loop_336.(ex_loop_336, i)
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
        ex_loop_338 = fn ex_loop_338, dashes, i ->
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
              ex_loop_338.(ex_loop_338, dashes, i)
            end
          else
            {dashes, i}
          end
        end
        {dashes, i} = ex_loop_338.(ex_loop_338, dashes, i)
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
          ex_loop_340 = fn ex_loop_340, i ->
            if true do
              _t5 = nil
              t5 = if TemperCore.String.has_index(s, i) do
                t5 = Temper.MarginaliaCore.isRegexSpace__511(TemperCore.String.get(s, i))
                t5
              else
                t5 = false
                t5
              end
              if not t5 do
                i
              else
                i = TemperCore.String.next(s, i)
                ex_loop_340.(ex_loop_340, i)
              end
            else
              i
            end
          end
          i = ex_loop_340.(ex_loop_340, i)
          throw({:temper_return, :ex_return_334, i})
        end
      end
      return
    catch
      {:temper_return, :ex_return_334, ex_value_342} ->
        ex_value_342
    end
  end
  def isTableDelimiter__499(s) do
    return = nil
    return = if true do
      _t1 = nil
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
      first = Temper.MarginaliaCore.delimiterCell__500(s, i)
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
        end
        i = t1
        ex_loop_345 = fn ex_loop_345, i, return ->
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
                cell = Temper.MarginaliaCore.delimiterCell__500(s, after_)
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
                  end
                  ex_loop_345.(ex_loop_345, i, return)
                end
            end
          else
            {i, return}
          end
        end
        {_i, return} = ex_loop_345.(ex_loop_345, i, return)
        return
      end
    end
    return
  end
  def isAtxHeading__501(s) do
    i = TemperCore.String.begin()
    hashes = 0
    ex_loop_348 = fn ex_loop_348, hashes, i ->
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
          ex_loop_348.(ex_loop_348, hashes, i)
        end
      else
        {hashes, i}
      end
    end
    {hashes, i} = ex_loop_348.(ex_loop_348, hashes, i)
    if hashes >= 1 do
      if hashes <= 6 do
        if TemperCore.String.has_index(s, i) do
          Temper.MarginaliaCore.isRegexSpace__511(TemperCore.String.get(s, i))
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
  def isIndentedCode__502(block) do
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
          ex_loop_352 = fn ex_loop_352, i, spaces ->
            if true do
              _t2 = nil
              t2 = if TemperCore.String.has_index(block, i) do
                if Temper.MarginaliaCore.isRegexSpace__511(TemperCore.String.get(block, i)) do
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
                ex_loop_352.(ex_loop_352, i, spaces)
              end
            else
              {i, spaces}
            end
          end
          {_i, spaces} = ex_loop_352.(ex_loop_352, i, spaces)
          throw({:temper_return, :ex_return_350, spaces >= 4})
        end
      end
      return
    catch
      {:temper_return, :ex_return_350, ex_value_354} ->
        ex_value_354
    end
  end
  def isListItem__503(s) do
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
              t1 = Temper.MarginaliaCore.isRegexSpace__511(TemperCore.String.get(s, after_))
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
            ex_loop_357 = fn ex_loop_357, digits, i ->
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
                  ex_loop_357.(ex_loop_357, digits, i)
                end
              else
                {digits, i}
              end
            end
            {digits, i} = ex_loop_357.(ex_loop_357, digits, i)
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
                throw({:temper_return, :ex_return_355, Temper.MarginaliaCore.isRegexSpace__511(TemperCore.String.get(s, next))})
              else
                throw({:temper_return, :ex_return_355, false})
              end
            end
          end
        end
      end
      return
    catch
      {:temper_return, :ex_return_355, ex_value_359} ->
        ex_value_359
    end
  end
  def isHtml__504(s) do
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
              throw({:temper_return, :ex_return_360, true})
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
                  throw({:temper_return, :ex_return_360, true})
                c == 33 ->
                  throw({:temper_return, :ex_return_360, true})
                true ->
                  throw({:temper_return, :ex_return_360, c == 47})
              end
            end
          end
        end
      end
      return
    catch
      {:temper_return, :ex_return_360, ex_value_362} ->
        ex_value_362
    end
  end
  def isLoneLinkOrImage__505(block) do
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
          ex_loop_365 = fn ex_loop_365, i ->
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
                ex_loop_365.(ex_loop_365, i)
              end
            else
              i
            end
          end
          i = ex_loop_365.(ex_loop_365, i)
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
              ex_loop_367 = fn ex_loop_367, i ->
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
                    ex_loop_367.(ex_loop_367, i)
                  end
                else
                  i
                end
              end
              i = ex_loop_367.(ex_loop_367, i)
              if not TemperCore.String.has_index(block, i) do
                return = false
                return
              else
                i = TemperCore.String.next(block, i)
                ex_loop_369 = fn ex_loop_369, i ->
                  if true do
                    _t6 = nil
                    t6 = if TemperCore.String.has_index(block, i) do
                      t6 = Temper.MarginaliaCore.isRegexSpace__511(TemperCore.String.get(block, i))
                      t6
                    else
                      t6 = false
                      t6
                    end
                    if not t6 do
                      i
                    else
                      i = TemperCore.String.next(block, i)
                      ex_loop_369.(ex_loop_369, i)
                    end
                  else
                    i
                  end
                end
                i = ex_loop_369.(ex_loop_369, i)
                throw({:temper_return, :ex_return_363, not TemperCore.String.has_index(block, i)})
              end
            end
          end
        end
      end
      return
    catch
      {:temper_return, :ex_return_363, ex_value_371} ->
        ex_value_371
    end
  end
  def isRule__506(s) do
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
            ex_loop_374 = fn ex_loop_374, count, i ->
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
                  ex_loop_374.(ex_loop_374, count, i)
                end
              else
                {count, i}
              end
            end
            {count, i} = ex_loop_374.(ex_loop_374, count, i)
            ex_loop_376 = fn ex_loop_376, i ->
              if true do
                _t3 = nil
                t3 = if TemperCore.String.has_index(s, i) do
                  t3 = Temper.MarginaliaCore.isRegexSpace__511(TemperCore.String.get(s, i))
                  t3
                else
                  t3 = false
                  t3
                end
                if not t3 do
                  i
                else
                  i = TemperCore.String.next(s, i)
                  ex_loop_376.(ex_loop_376, i)
                end
              else
                i
              end
            end
            i = ex_loop_376.(ex_loop_376, i)
            if count >= 3 do
              throw({:temper_return, :ex_return_372, not TemperCore.String.has_index(s, i)})
            else
              throw({:temper_return, :ex_return_372, false})
            end
          end
        end
      end
      return
    catch
      {:temper_return, :ex_return_372, ex_value_378} ->
        ex_value_378
    end
  end
  def isProse__496(block) do
    try do
      _return = nil
      return = if true do
        lines = TemperCore.String.split(block, "\n")
        first = Temper.MarginaliaCore.trimLeading__516(TemperCore.List.get(lines, 0))
        _second = nil
        second = if TemperCore.List.length(lines) > 1 do
          second = Temper.MarginaliaCore.trim__513(TemperCore.List.get(lines, 1))
          second
        else
          second = ""
          second
        end
        cond do
          Temper.MarginaliaCore.isUnderline__497(second) ->
            return = false
            return
          Temper.MarginaliaCore.isTableDelimiter__499(second) ->
            return = false
            return
          true ->
            _t = nil
            t = if Temper.MarginaliaCore.startsWith__518(first, "```") do
              t = true
              t
            else
              t = Temper.MarginaliaCore.startsWith__518(first, "~~~")
              t
            end
            cond do
              t ->
                return = false
                return
              Temper.MarginaliaCore.isAtxHeading__501(first) ->
                return = false
                return
              Temper.MarginaliaCore.isIndentedCode__502(block) ->
                return = false
                return
              Temper.MarginaliaCore.isListItem__503(first) ->
                return = false
                return
              Temper.MarginaliaCore.isHtml__504(first) ->
                return = false
                return
              Temper.MarginaliaCore.isLoneLinkOrImage__505(block) ->
                return = false
                return
              Temper.MarginaliaCore.isRule__506(first) ->
                return = false
                return
              true ->
                allPiped = true
                k = 0
                ex_loop_381 = fn ex_loop_381, allPiped, k ->
                  if k < TemperCore.List.length(lines) do
                    allPiped = if not Temper.MarginaliaCore.startsWith__518(Temper.MarginaliaCore.trimLeading__516(TemperCore.List.get(lines, k)), "|") do
                      allPiped = false
                      allPiped
                    else
                      allPiped
                    end
                    k = TemperCore.int32(k + 1)
                    ex_loop_381.(ex_loop_381, allPiped, k)
                  else
                    {allPiped, k}
                  end
                end
                {allPiped, _k} = ex_loop_381.(ex_loop_381, allPiped, k)
                throw({:temper_return, :ex_return_379, not allPiped})
            end
        end
      end
      return
    catch
      {:temper_return, :ex_return_379, ex_value_383} ->
        ex_value_383
    end
  end
  def isQuoted__488(block) do
    i = TemperCore.String.begin()
    ex_loop_385 = fn ex_loop_385, i ->
      if true do
        _t = nil
        t = if TemperCore.String.has_index(block, i) do
          t = Temper.MarginaliaCore.isRegexSpace__511(TemperCore.String.get(block, i))
          t
        else
          t = false
          t
        end
        if not t do
          i
        else
          i = TemperCore.String.next(block, i)
          ex_loop_385.(ex_loop_385, i)
        end
      else
        i
      end
    end
    i = ex_loop_385.(ex_loop_385, i)
    if TemperCore.String.has_index(block, i) do
      TemperCore.String.get(block, i) == 62
    else
      false
    end
  end
  def stripQuoteMark__487(line) do
    try do
      _return = nil
      return = if true do
        i = TemperCore.String.begin()
        ex_loop_389 = fn ex_loop_389, i ->
          if true do
            _t3 = nil
            t3 = if TemperCore.String.has_index(line, i) do
              t3 = Temper.MarginaliaCore.isRegexSpace__511(TemperCore.String.get(line, i))
              t3
            else
              t3 = false
              t3
            end
            if not t3 do
              i
            else
              i = TemperCore.String.next(line, i)
              ex_loop_389.(ex_loop_389, i)
            end
          else
            i
          end
        end
        i = ex_loop_389.(ex_loop_389, i)
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
            t2 = Temper.MarginaliaCore.isRegexSpace__511(TemperCore.String.get(line, i))
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
          throw({:temper_return, :ex_return_387, TemperCore.String.slice(line, i, TemperCore.String.end_of(line))})
        end
      end
      return
    catch
      {:temper_return, :ex_return_387, ex_value_391} ->
        ex_value_391
    end
  end
  def reflowQuote__486(block) do
    lines = TemperCore.String.split(block, "\n")
    fn_1 = fn l1 ->
      Temper.MarginaliaCore.stripQuoteMark__487(l1)
    end
    stripped = Temper.MarginaliaCore.joinWith__520(TemperCore.List.map(lines, fn_1), "\n")
    back = TemperCore.String.split(Temper.MarginaliaCore.reflow(stripped), "\n")
    fn_2 = fn l2 ->
      if TemperCore.String.is_empty(l2) do
        ">"
      else
        "> " <> l2
      end
    end
    Temper.MarginaliaCore.joinWith__520(TemperCore.List.map(back, fn_2), "\n")
  end
  def isCloser__484(cp) do
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
  def isUnicodeSpace(cp) do
    TemperConnected.isUnicodeSpace(cp)
  end
  def isOpener__485(cp) do
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
  def isUnicodeUpper(cp) do
    TemperConnected.isUnicodeUpper(cp)
  end
  def isUnicodeDigit(cp) do
    TemperConnected.isUnicodeDigit(cp)
  end
  def breakSentences__491(text) do
    out = TemperCore.StringBuilder.new()
    i = TemperCore.String.begin()
    ex_loop_398 = fn ex_loop_398, i ->
      if TemperCore.String.has_index(text, i) do
        ex_step_412 = try do
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
            ex_loop_406 = fn ex_loop_406, j ->
              if true do
                _t3 = nil
                t3 = if TemperCore.String.has_index(text, j) do
                  t3 = Temper.MarginaliaCore.isCloser__484(TemperCore.String.get(text, j))
                  t3
                else
                  t3 = false
                  t3
                end
                if not t3 do
                  j
                else
                  j = TemperCore.String.next(text, j)
                  ex_loop_406.(ex_loop_406, j)
                end
              else
                j
              end
            end
            j = ex_loop_406.(ex_loop_406, j)
            k = j
            ex_loop_408 = fn ex_loop_408, k ->
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
                  ex_loop_408.(ex_loop_408, k)
                end
              else
                k
              end
            end
            k = ex_loop_408.(ex_loop_408, k)
            m = k
            ex_loop_410 = fn ex_loop_410, m ->
              if true do
                _t5 = nil
                t5 = if TemperCore.String.has_index(text, m) do
                  t5 = Temper.MarginaliaCore.isOpener__485(TemperCore.String.get(text, m))
                  t5
                else
                  t5 = false
                  t5
                end
                if not t5 do
                  m
                else
                  m = TemperCore.String.next(text, m)
                  ex_loop_410.(ex_loop_410, m)
                end
              else
                m
              end
            end
            m = ex_loop_410.(ex_loop_410, m)
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
              throw({:temper_continue, :ex_loop_399, i})
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
          {:temper_continue, :ex_loop_399, ex_vars_413} ->
            {:temper_next, ex_vars_413}
          {:temper_break, :ex_loop_399, ex_vars_413} ->
            {:temper_done, ex_vars_413}
        end
        case ex_step_412 do
          {:temper_next, i} ->
            ex_loop_398.(ex_loop_398, i)
          {:temper_done, ex_vars_413} ->
            ex_vars_413
        end
      else
        i
      end
    end
    _i = ex_loop_398.(ex_loop_398, i)
    TemperCore.StringBuilder.to_string(out)
  end
  def startsAWord__495(line, at) do
    if at <= TemperCore.String.begin() do
      true
    else
      Temper.MarginaliaCore.isUnicodeSpace(TemperCore.String.get(line, TemperCore.String.prev(line, at)))
    end
  end
  def abbreviationAt__494(line, dot, word) do
    try do
      _return = nil
      return = if true do
        if not Temper.MarginaliaCore.endsWithAt__519(line, dot, word) do
          return = false
          return
        else
          start = dot
          k = 0
          ex_loop_417 = fn ex_loop_417, k, start ->
            if k < TemperCore.String.count_between(word, TemperCore.String.begin(), TemperCore.String.end_of(word)) do
              start = TemperCore.String.prev(line, start)
              k = TemperCore.int32(k + 1)
              ex_loop_417.(ex_loop_417, k, start)
            else
              {k, start}
            end
          end
          {_k, start} = ex_loop_417.(ex_loop_417, k, start)
          throw({:temper_return, :ex_return_415, Temper.MarginaliaCore.startsAWord__495(line, start)})
        end
      end
      return
    catch
      {:temper_return, :ex_return_415, ex_value_419} ->
        ex_value_419
    end
  end
  def endsOnAbbreviation__493(line) do
    try do
      return = nil
      return = try do
        e = TemperCore.String.end_of(line)
        ex_loop_422 = fn ex_loop_422, e ->
          if true do
            _t2 = nil
            t2 = if e > TemperCore.String.begin() do
              t2 = Temper.MarginaliaCore.isCloser__484(TemperCore.String.get(line, TemperCore.String.prev(line, e)))
              t2
            else
              t2 = false
              t2
            end
            if not t2 do
              e
            else
              e = TemperCore.String.prev(line, e)
              ex_loop_422.(ex_loop_422, e)
            end
          else
            e
          end
        end
        e = ex_loop_422.(ex_loop_422, e)
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
          ex_loop_424 = fn ex_loop_424, k, return ->
            if k < TemperCore.List.length(TemperCore.Global.get(:"Temper.MarginaliaCore.abbreviations__540")) do
              if Temper.MarginaliaCore.abbreviationAt__494(line, dot, TemperCore.List.get(TemperCore.Global.get(:"Temper.MarginaliaCore.abbreviations__540"), k)) do
                return = true
                throw({:temper_break, :ex_block_421, return})
              else
                k = TemperCore.int32(k + 1)
                ex_loop_424.(ex_loop_424, k, return)
              end
            else
              {k, return}
            end
          end
          {_k, return} = ex_loop_424.(ex_loop_424, k, return)
          _return = if dot > TemperCore.String.begin() do
            c = TemperCore.String.prev(line, dot)
            cp = TemperCore.String.get(line, c)
            _t3 = nil
            t3 = if cp >= 65 do
              if cp <= 90 do
                t3 = Temper.MarginaliaCore.startsAWord__495(line, c)
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
              throw({:temper_break, :ex_block_421, return})
            else
              return
            end
          else
            return
          end
          throw({:temper_return, :ex_return_420, false})
        end
      catch
        {:temper_break, :ex_block_421, ex_vars_426} ->
          ex_vars_426
      end
      return
    catch
      {:temper_return, :ex_return_420, ex_value_427} ->
        ex_value_427
    end
  end
  def splitSentences__492(joined) do
    lines = TemperCore.String.split(Temper.MarginaliaCore.breakSentences__491(joined), "\n")
    out = TemperCore.List.builder()
    k = 0
    ex_loop_429 = fn ex_loop_429, k ->
      if k < TemperCore.List.length(lines) do
        n = TemperCore.List.length(out)
        _t = nil
        t = if n > 0 do
          t = Temper.MarginaliaCore.endsOnAbbreviation__493(TemperCore.List.get(out, TemperCore.int32(n - 1)))
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
        ex_loop_429.(ex_loop_429, k)
      else
        k
      end
    end
    _k = ex_loop_429.(ex_loop_429, k)
    Temper.MarginaliaCore.joinWith__520(TemperCore.List.to_list(out), "\n")
  end
  def squeezeBlanks__490(text) do
    out = TemperCore.StringBuilder.new()
    inBlank = false
    i = TemperCore.String.begin()
    ex_loop_432 = fn ex_loop_432, i, inBlank ->
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
        ex_loop_432.(ex_loop_432, i, inBlank)
      else
        {i, inBlank}
      end
    end
    {_i, _inBlank} = ex_loop_432.(ex_loop_432, i, inBlank)
    TemperCore.StringBuilder.to_string(out)
  end
  def unwrap__489(block) do
    lines = TemperCore.String.split(block, "\n")
    last = TemperCore.int32(TemperCore.List.length(lines) - 1)
    pieces = TemperCore.List.builder()
    k = 0
    ex_loop_435 = fn ex_loop_435, k ->
      if k <= last do
        line = TemperCore.List.get(lines, k)
        b = TemperCore.String.begin()
        e = TemperCore.String.end_of(line)
        b = if k > 0 do
          ex_loop_437 = fn ex_loop_437, b ->
            if true do
              _t1 = nil
              t1 = if TemperCore.String.has_index(line, b) do
                t1 = Temper.MarginaliaCore.isRegexSpace__511(TemperCore.String.get(line, b))
                t1
              else
                t1 = false
                t1
              end
              if not t1 do
                b
              else
                b = TemperCore.String.next(line, b)
                ex_loop_437.(ex_loop_437, b)
              end
            else
              b
            end
          end
          b = ex_loop_437.(ex_loop_437, b)
          b
        else
          b
        end
        e = if k < last do
          ex_loop_439 = fn ex_loop_439, e ->
            if true do
              _t2 = nil
              t2 = if e > b do
                t2 = Temper.MarginaliaCore.isRegexSpace__511(TemperCore.String.get(line, TemperCore.String.prev(line, e)))
                t2
              else
                t2 = false
                t2
              end
              if not t2 do
                e
              else
                e = TemperCore.String.prev(line, e)
                ex_loop_439.(ex_loop_439, e)
              end
            else
              e
            end
          end
          e = ex_loop_439.(ex_loop_439, e)
          e
        else
          e
        end
        TemperCore.List.add(pieces, TemperCore.String.slice(line, b, e))
        k = TemperCore.int32(k + 1)
        ex_loop_435.(ex_loop_435, k)
      else
        k
      end
    end
    _k = ex_loop_435.(ex_loop_435, k)
    Temper.MarginaliaCore.joinWith__520(TemperCore.List.to_list(pieces), " ")
  end
  def reflowBlock(block) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      try do
        _return = nil
        return = if true do
          cond do
            not Temper.MarginaliaCore.isProse__496(block) ->
              return = block
              return
            Temper.MarginaliaCore.isQuoted__488(block) ->
              return = Temper.MarginaliaCore.reflowQuote__486(block)
              return
            true ->
              throw({:temper_return, :ex_return_441, Temper.MarginaliaCore.splitSentences__492(Temper.MarginaliaCore.trim__513(Temper.MarginaliaCore.squeezeBlanks__490(Temper.MarginaliaCore.unwrap__489(block))))})
          end
        end
        return
      catch
        {:temper_return, :ex_return_441, ex_value_443} ->
          ex_value_443
      end
    end)
  end
  def deriveTitle__479(body, i) do
    first = TemperCore.List.get(TemperCore.String.split(body, "\n"), 0)
    h = TemperCore.String.begin()
    hashes = 0
    ex_loop_445 = fn ex_loop_445, h, hashes ->
      if true do
        _t2 = nil
        t2 = if TemperCore.String.has_index(first, h) do
          if TemperCore.String.get(first, h) == 35 do
            t2 = hashes < 7
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
          {h, hashes}
        else
          hashes = TemperCore.int32(hashes + 1)
          h = TemperCore.String.next(first, h)
          ex_loop_445.(ex_loop_445, h, hashes)
        end
      else
        {h, hashes}
      end
    end
    {h, hashes} = ex_loop_445.(ex_loop_445, h, hashes)
    _t1 = nil
    t1 = if hashes >= 1 do
      if hashes <= 6 do
        if TemperCore.String.has_index(first, h) do
          t1 = Temper.MarginaliaCore.isRegexSpace__511(TemperCore.String.get(first, h))
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
    {first, _h} = if t1 do
      ex_loop_447 = fn ex_loop_447, h ->
        if true do
          _t4 = nil
          t4 = if TemperCore.String.has_index(first, h) do
            t4 = Temper.MarginaliaCore.isRegexSpace__511(TemperCore.String.get(first, h))
            t4
          else
            t4 = false
            t4
          end
          if not t4 do
            h
          else
            h = TemperCore.String.next(first, h)
            ex_loop_447.(ex_loop_447, h)
          end
        else
          h
        end
      end
      h = ex_loop_447.(ex_loop_447, h)
      first = TemperCore.String.slice(first, h, TemperCore.String.end_of(first))
      {first, h}
    else
      {first, h}
    end
    plain = TemperCore.StringBuilder.new()
    k = TemperCore.String.begin()
    ex_loop_449 = fn ex_loop_449, k ->
      if TemperCore.String.has_index(first, k) do
        cp = TemperCore.String.get(first, k)
        _t3 = nil
        t3 = if cp != 42 do
          if cp != 95 do
            t3 = cp != 96
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
          try do
            TemperCore.StringBuilder.append_code_point(plain, cp)
            nil
          rescue
            _ in TemperCore.Bubble ->
              raise(TemperCore.Bubble)
          end
          nil
        else
          nil
        end
        k = TemperCore.String.next(first, k)
        ex_loop_449.(ex_loop_449, k)
      else
        k
      end
    end
    _k = ex_loop_449.(ex_loop_449, k)
    label = Temper.MarginaliaCore.graphemePrefix(Temper.MarginaliaCore.trim__513(TemperCore.StringBuilder.to_string(plain)), 60)
    if Temper.MarginaliaCore.graphemeLength(label) > 12 do
      TemperCore.int_to_string(i) <> ". " <> label <> "…"
    else
      "Section " <> TemperCore.int_to_string(i)
    end
  end
  def byWindows__475(text) do
    bodies = Temper.MarginaliaCore.window__477(text)
    out = TemperCore.List.builder()
    k = 0
    ex_loop_452 = fn ex_loop_452, k ->
      if k < TemperCore.List.length(bodies) do
        body = Temper.MarginaliaCore.reflow(TemperCore.List.get(bodies, k))
        TemperCore.List.add(out, Temper.MarginaliaCore.Section.new(Temper.MarginaliaCore.deriveTitle__479(body, TemperCore.int32(k + 1)), body))
        k = TemperCore.int32(k + 1)
        ex_loop_452.(ex_loop_452, k)
      else
        k
      end
    end
    _k = ex_loop_452.(ex_loop_452, k)
    subject = Temper.MarginaliaCore.finish__480(TemperCore.List.to_list(out))
    if subject === nil do
      %TemperCore.Vec{t: {}}
    else
      subject
    end
  end
  def segment(raw) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      try do
        _return = nil
        return = if true do
          text = Temper.MarginaliaCore.normalize__462(raw)
          if TemperCore.String.is_empty(text) do
            return = %TemperCore.Vec{t: {}}
            return
          else
            _chunks = nil
            _t = nil
            subject = Temper.MarginaliaCore.byMarkdown__465(text)
            t = if subject === nil do
              t = Temper.MarginaliaCore.byMarker__472(text)
              t
            else
              t = subject
              t
            end
            chunks = if t === nil do
              chunks = Temper.MarginaliaCore.byWindows__475(text)
              chunks
            else
              chunks = t
              chunks
            end
            fn_ = fn c ->
              Temper.MarginaliaCore.Section.new(Temper.MarginaliaCore.Section.get_title(c), Temper.MarginaliaCore.reflow(Temper.MarginaliaCore.Section.get_body(c)))
            end
            throw({:temper_return, :ex_return_454, TemperCore.List.map(chunks, fn_)})
          end
        end
        return
      catch
        {:temper_return, :ex_return_454, ex_value_457} ->
          ex_value_457
      end
    end)
  end
  def wordsOf__521(text) do
    out = TemperCore.List.builder()
    i = TemperCore.String.begin()
    ex_loop_479 = fn ex_loop_479, i ->
      if true do
        _t1 = nil
        t1 = if TemperCore.String.has_index(text, i) do
          t1 = Temper.MarginaliaCore.isRegexSpace__511(TemperCore.String.get(text, i))
          t1
        else
          t1 = false
          t1
        end
        if not t1 do
          i
        else
          i = TemperCore.String.next(text, i)
          ex_loop_479.(ex_loop_479, i)
        end
      else
        i
      end
    end
    i = ex_loop_479.(ex_loop_479, i)
    ex_loop_481 = fn ex_loop_481, i ->
      if TemperCore.String.has_index(text, i) do
        start = i
        ex_loop_483 = fn ex_loop_483, i ->
          if true do
            _t2 = nil
            t2 = if TemperCore.String.has_index(text, i) do
              t2 = not Temper.MarginaliaCore.isRegexSpace__511(TemperCore.String.get(text, i))
              t2
            else
              t2 = false
              t2
            end
            if not t2 do
              i
            else
              i = TemperCore.String.next(text, i)
              ex_loop_483.(ex_loop_483, i)
            end
          else
            i
          end
        end
        i = ex_loop_483.(ex_loop_483, i)
        ex_loop_485 = fn ex_loop_485, i ->
          if true do
            _t3 = nil
            t3 = if TemperCore.String.has_index(text, i) do
              t3 = Temper.MarginaliaCore.isRegexSpace__511(TemperCore.String.get(text, i))
              t3
            else
              t3 = false
              t3
            end
            if not t3 do
              i
            else
              i = TemperCore.String.next(text, i)
              ex_loop_485.(ex_loop_485, i)
            end
          else
            i
          end
        end
        i = ex_loop_485.(ex_loop_485, i)
        TemperCore.List.add(out, TemperCore.String.slice(text, start, i))
        ex_loop_481.(ex_loop_481, i)
      else
        i
      end
    end
    _i = ex_loop_481.(ex_loop_481, i)
    TemperCore.List.to_list(out)
  end
  def distinct__523(words) do
    set = TemperCore.Map.builder()
    k = 0
    ex_loop_488 = fn ex_loop_488, k ->
      if k < TemperCore.List.length(words) do
        TemperCore.Map.set(set, TemperCore.List.get(words, k), true)
        k = TemperCore.int32(k + 1)
        ex_loop_488.(ex_loop_488, k)
      else
        k
      end
    end
    _k = ex_loop_488.(ex_loop_488, k)
    set
  end
  def unrelated__522(ak, bk) do
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
          a = TemperCore.Map.to_map(Temper.MarginaliaCore.distinct__523(ak))
          b = TemperCore.Map.to_map(Temper.MarginaliaCore.distinct__523(bk))
          bKeys = TemperCore.Map.keys(b)
          shared = 0
          k = 0
          ex_loop_492 = fn ex_loop_492, k, shared ->
            if k < TemperCore.List.length(bKeys) do
              shared = if TemperCore.Map.has(a, TemperCore.List.get(bKeys, k)) do
                shared = TemperCore.int32(shared + 1)
                shared
              else
                shared
              end
              k = TemperCore.int32(k + 1)
              ex_loop_492.(ex_loop_492, k, shared)
            else
              {k, shared}
            end
          end
          {_k, shared} = ex_loop_492.(ex_loop_492, k, shared)
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
          throw({:temper_return, :ex_return_490, TemperCore.Float.lt(TemperCore.int_to_float(shared), TemperCore.Float.mul(0.05, TemperCore.int_to_float(smaller)))})
        end
      end
      return
    catch
      {:temper_return, :ex_return_490, ex_value_494} ->
        ex_value_494
    end
  end
  def attach__530(script, aw, bw, parts) do
    ai = 0
    bi = 0
    c = 0
    ex_loop_496 = fn ex_loop_496, ai, bi, c ->
      if c < TemperCore.List.length(script) do
        chunk = TemperCore.List.get(script, c)
        count = TemperCore.List.length(Temper.MarginaliaCore.Chunk.get_words(chunk))
        k = 0
        ex_loop_498 = fn ex_loop_498, ai, bi, k ->
          if k < count do
            {ai, bi} = cond do
              Temper.MarginaliaCore.Chunk.get_kind(chunk) == 0 ->
                ta = TemperCore.List.get(aw, ai)
                tb = TemperCore.List.get(bw, bi)
                cut = Temper.MarginaliaCore.trailingStart__514(tb)
                _token = nil
                token = if cut == TemperCore.String.end_of(tb) do
                  token = Temper.MarginaliaCore.trim__513(tb) <> TemperCore.String.slice(ta, Temper.MarginaliaCore.trailingStart__514(ta), TemperCore.String.end_of(ta))
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
            ex_loop_498.(ex_loop_498, ai, bi, k)
          else
            {ai, bi, k}
          end
        end
        {ai, bi, _k} = ex_loop_498.(ex_loop_498, ai, bi, k)
        c = TemperCore.int32(c + 1)
        ex_loop_496.(ex_loop_496, ai, bi, c)
      else
        {ai, bi, c}
      end
    end
    {_ai, _bi, _c} = ex_loop_496.(ex_loop_496, ai, bi, c)
    nil
  end
  def moveDown__525(p, a) do
    if Temper.MarginaliaCore.Path.get_i(p) < TemperCore.List.length(a) do
      Temper.MarginaliaCore.Path.new(TemperCore.int32(Temper.MarginaliaCore.Path.get_y(p) + 1), TemperCore.int32(Temper.MarginaliaCore.Path.get_i(p) + 1), Temper.MarginaliaCore.Path.get_j(p), Temper.MarginaliaCore.Edit.new(1, TemperCore.List.get(a, Temper.MarginaliaCore.Path.get_i(p)), Temper.MarginaliaCore.Path.get_edits(p)))
    else
      Temper.MarginaliaCore.Path.new(TemperCore.int32(Temper.MarginaliaCore.Path.get_y(p) + 1), Temper.MarginaliaCore.Path.get_i(p), Temper.MarginaliaCore.Path.get_j(p), Temper.MarginaliaCore.Path.get_edits(p))
    end
  end
  def moveRight__524(p, b) do
    if Temper.MarginaliaCore.Path.get_j(p) < TemperCore.List.length(b) do
      Temper.MarginaliaCore.Path.new(Temper.MarginaliaCore.Path.get_y(p), Temper.MarginaliaCore.Path.get_i(p), TemperCore.int32(Temper.MarginaliaCore.Path.get_j(p) + 1), Temper.MarginaliaCore.Edit.new(2, TemperCore.List.get(b, Temper.MarginaliaCore.Path.get_j(p)), Temper.MarginaliaCore.Path.get_edits(p)))
    else
      p
    end
  end
  def followSnake__526(p, a, b) do
    y = Temper.MarginaliaCore.Path.get_y(p)
    i = Temper.MarginaliaCore.Path.get_i(p)
    j = Temper.MarginaliaCore.Path.get_j(p)
    edits = Temper.MarginaliaCore.Path.get_edits(p)
    ex_loop_503 = fn ex_loop_503, edits, i, j, y ->
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
          ex_loop_503.(ex_loop_503, edits, i, j, y)
        end
      else
        {edits, i, j, y}
      end
    end
    {edits, i, j, y} = ex_loop_503.(ex_loop_503, edits, i, j, y)
    Temper.MarginaliaCore.Path.new(y, i, j, edits)
  end
  def sameWords__529(x, y) do
    try do
      return = nil
      return = try do
        if TemperCore.List.length(x) != TemperCore.List.length(y) do
          return = false
          return
        else
          k = 0
          ex_loop_507 = fn ex_loop_507, k, return ->
            if k < TemperCore.List.length(x) do
              if TemperCore.List.get(x, k) != TemperCore.List.get(y, k) do
                return = false
                throw({:temper_break, :ex_block_506, return})
              else
                k = TemperCore.int32(k + 1)
                ex_loop_507.(ex_loop_507, k, return)
              end
            else
              {k, return}
            end
          end
          {_k, _return} = ex_loop_507.(ex_loop_507, k, return)
          throw({:temper_return, :ex_return_505, true})
        end
      catch
        {:temper_break, :ex_block_506, ex_vars_509} ->
          ex_vars_509
      end
      return
    catch
      {:temper_return, :ex_return_505, ex_value_510} ->
        ex_value_510
    end
  end
  def compact__528(edits) do
    out = TemperCore.List.builder()
    e = edits
    ex_loop_512 = fn ex_loop_512, e ->
      if not (e === nil) do
        _edit = nil
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
          ex_loop_512.(ex_loop_512, e)
        else
          _t2 = nil
          t2 = if n >= 3 do
            if Temper.MarginaliaCore.Chunk.get_kind(TemperCore.List.get(out, TemperCore.int32(n - 1))) == 0 do
              if Temper.MarginaliaCore.Chunk.get_kind(TemperCore.List.get(out, TemperCore.int32(n - 2))) == 2 do
                if Temper.MarginaliaCore.Chunk.get_kind(TemperCore.List.get(out, TemperCore.int32(n - 3))) == 0 do
                  t2 = Temper.MarginaliaCore.sameWords__529(Temper.MarginaliaCore.Chunk.get_words(TemperCore.List.get(out, TemperCore.int32(n - 1))), Temper.MarginaliaCore.Chunk.get_words(TemperCore.List.get(out, TemperCore.int32(n - 2))))
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
            ex_loop_512.(ex_loop_512, e)
          else
            words = TemperCore.List.builder()
            TemperCore.List.add(words, Temper.MarginaliaCore.Edit.get_word(edit))
            TemperCore.List.add(out, Temper.MarginaliaCore.Chunk.new(Temper.MarginaliaCore.Edit.get_kind(edit), words))
            e = Temper.MarginaliaCore.Edit.get_before(edit)
            ex_loop_512.(ex_loop_512, e)
          end
        end
      else
        e
      end
    end
    _e = ex_loop_512.(ex_loop_512, e)
    TemperCore.List.reverse(out)
    k = 0
    ex_loop_514 = fn ex_loop_514, k ->
      if k < TemperCore.List.length(out) do
        TemperCore.List.reverse(Temper.MarginaliaCore.Chunk.get_words(TemperCore.List.get(out, k)))
        k = TemperCore.int32(k + 1)
        ex_loop_514.(ex_loop_514, k)
      else
        k
      end
    end
    _k = ex_loop_514.(ex_loop_514, k)
    TemperCore.List.to_list(out)
  end
  def myers__527(a, b) do
    return = nil
    return = try do
      paths = %TemperCore.Vec{t: {Temper.MarginaliaCore.Path.new(0, 0, 0, nil)}}
      envelope = 0
      ex_loop_518 = fn ex_loop_518, envelope, paths, return ->
        if true do
          next = TemperCore.List.builder()
          at = 0
          diag = TemperCore.int32(-envelope)
          ex_loop_520 = fn ex_loop_520, at, diag, return ->
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
                  path = Temper.MarginaliaCore.moveDown__525(path, a)
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
                    path = Temper.MarginaliaCore.moveRight__524(path, b)
                    at = TemperCore.int32(at + 1)
                    {at, path}
                  else
                    _t4 = nil
                    second = TemperCore.List.get(paths, TemperCore.int32(at + 1))
                    t4 = if Temper.MarginaliaCore.Path.get_y(path) > Temper.MarginaliaCore.Path.get_y(second) do
                      t4 = Temper.MarginaliaCore.moveRight__524(path, b)
                      t4
                    else
                      t4 = Temper.MarginaliaCore.moveDown__525(second, a)
                      t4
                    end
                    path = t4
                    at = TemperCore.int32(at + 1)
                    {at, path}
                  end
              end
              path = Temper.MarginaliaCore.followSnake__526(path, a, b)
              _t2 = nil
              t2 = if Temper.MarginaliaCore.Path.get_i(path) == TemperCore.List.length(a) do
                t2 = Temper.MarginaliaCore.Path.get_j(path) == TemperCore.List.length(b)
                t2
              else
                t2 = false
                t2
              end
              if t2 do
                return = Temper.MarginaliaCore.compact__528(Temper.MarginaliaCore.Path.get_edits(path))
                throw({:temper_break, :ex_block_517, return})
              else
                TemperCore.List.add(next, path)
                diag = TemperCore.int32(diag + 2)
                ex_loop_520.(ex_loop_520, at, diag, return)
              end
            else
              {at, diag, return}
            end
          end
          {_at, _diag, return} = ex_loop_520.(ex_loop_520, at, diag, return)
          paths = TemperCore.List.to_list(next)
          envelope = TemperCore.int32(envelope + 1)
          ex_loop_518.(ex_loop_518, envelope, paths, return)
        else
          {envelope, paths, return}
        end
      end
      {_envelope, _paths, return} = ex_loop_518.(ex_loop_518, envelope, paths, return)
      return
    catch
      {:temper_break, :ex_block_517, ex_vars_522} ->
        ex_vars_522
    end
    return
  end
  def merge__531(parts) do
    out = TemperCore.List.builder()
    k = 0
    ex_loop_524 = fn ex_loop_524, k ->
      if k < TemperCore.List.length(parts) do
        kind = Temper.MarginaliaCore.Part.get_kind(TemperCore.List.get(parts, k))
        text = TemperCore.StringBuilder.new()
        ex_loop_526 = fn ex_loop_526, k ->
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
              ex_loop_526.(ex_loop_526, k)
            end
          else
            k
          end
        end
        k = ex_loop_526.(ex_loop_526, k)
        TemperCore.List.add(out, Temper.MarginaliaCore.Part.new(kind, TemperCore.StringBuilder.to_string(text)))
        ex_loop_524.(ex_loop_524, k)
      else
        k
      end
    end
    _k = ex_loop_524.(ex_loop_524, k)
    TemperCore.List.to_list(out)
  end
  def diff(a, b) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      aw = Temper.MarginaliaCore.wordsOf__521(a)
      bw = Temper.MarginaliaCore.wordsOf__521(b)
      fn_1 = fn w1 ->
        Temper.MarginaliaCore.trim__513(w1)
      end
      ak = TemperCore.List.map(aw, fn_1)
      fn_2 = fn w2 ->
        Temper.MarginaliaCore.trim__513(w2)
      end
      bk = TemperCore.List.map(bw, fn_2)
      parts = TemperCore.List.builder()
      if Temper.MarginaliaCore.unrelated__522(ak, bk) do
        k1 = 0
        ex_loop_531 = fn ex_loop_531, k1 ->
          if k1 < TemperCore.List.length(aw) do
            TemperCore.List.add(parts, Temper.MarginaliaCore.Part.new("del", TemperCore.List.get(aw, k1)))
            k1 = TemperCore.int32(k1 + 1)
            ex_loop_531.(ex_loop_531, k1)
          else
            k1
          end
        end
        _k1 = ex_loop_531.(ex_loop_531, k1)
        k2 = 0
        ex_loop_533 = fn ex_loop_533, k2 ->
          if k2 < TemperCore.List.length(bw) do
            TemperCore.List.add(parts, Temper.MarginaliaCore.Part.new("ins", TemperCore.List.get(bw, k2)))
            k2 = TemperCore.int32(k2 + 1)
            ex_loop_533.(ex_loop_533, k2)
          else
            k2
          end
        end
        _k2 = ex_loop_533.(ex_loop_533, k2)
        nil
      else
        Temper.MarginaliaCore.attach__530(Temper.MarginaliaCore.myers__527(ak, bk), aw, bw, parts)
        nil
      end
      Temper.MarginaliaCore.merge__531(TemperCore.List.to_list(parts))
    end)
  end
  def __temper_init__() do
    TemperCore.init_once(:"Temper.MarginaliaCore", fn ->
      TemperCore.Global.put(:"Temper.MarginaliaCore.abbreviations__540", %TemperCore.Vec{t: {"e.g", "i.e", "vs", "etc", "cf", "viz", "ca", "Mr", "Mrs", "Ms", "Dr", "Prof", "St", "No", "Fig", "Jr", "Sr", "Inc", "Ltd", "Co"}})
      nil
    end)
  end
  def main() do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Async.drain()
  end
end
