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
  def trim(s) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      b = TemperCore.String.begin()
      ex_loop_22 = fn ex_loop_22, b ->
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
            ex_loop_22.(ex_loop_22, b)
          end
        else
          b
        end
      end
      b = ex_loop_22.(ex_loop_22, b)
      e = TemperCore.String.end_of(s)
      ex_loop_24 = fn ex_loop_24, e ->
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
            ex_loop_24.(ex_loop_24, e)
          end
        else
          e
        end
      end
      e = ex_loop_24.(ex_loop_24, e)
      TemperCore.String.slice(s, b, e)
    end)
  end
  def flushParagraph__100(piece, out) do
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
      ex_loop_28 = fn ex_loop_28, i, newlines ->
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
                Temper.MarginaliaCore.flushParagraph__100(piece, out)
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
          ex_loop_28.(ex_loop_28, i, newlines)
        else
          {i, newlines}
        end
      end
      {_i, newlines} = ex_loop_28.(ex_loop_28, i, newlines)
      if newlines == 1 do
        TemperCore.StringBuilder.append(piece, "\n")
        nil
      else
        nil
      end
      Temper.MarginaliaCore.flushParagraph__100(piece, out)
      TemperCore.List.to_list(out)
    end)
  end
  def alignmentKey__101(p) do
    out = TemperCore.StringBuilder.new()
    inSpace = false
    i = TemperCore.String.begin()
    ex_loop_31 = fn ex_loop_31, i, inSpace ->
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
        ex_loop_31.(ex_loop_31, i, inSpace)
      else
        {i, inSpace}
      end
    end
    {_i, inSpace} = ex_loop_31.(ex_loop_31, i, inSpace)
    if inSpace do
      TemperCore.StringBuilder.append(out, " ")
      nil
    else
      nil
    end
    Temper.MarginaliaCore.trim(TemperCore.StringBuilder.to_string(out))
  end
  def flushRun__102(dels, ins, out) do
    _longer = nil
    longer = if TemperCore.List.length(dels) > TemperCore.List.length(ins) do
      longer = TemperCore.List.length(dels)
      longer
    else
      longer = TemperCore.List.length(ins)
      longer
    end
    k = 0
    ex_loop_34 = fn ex_loop_34, k ->
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
        ex_loop_34.(ex_loop_34, k)
      else
        k
      end
    end
    _k = ex_loop_34.(ex_loop_34, k)
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
        Temper.MarginaliaCore.alignmentKey__101(p1)
      end
      ak = TemperCore.List.map(a, fn_1)
      fn_2 = fn p2 ->
        Temper.MarginaliaCore.alignmentKey__101(p2)
      end
      bk = TemperCore.List.map(b, fn_2)
      n = TemperCore.List.length(a)
      m = TemperCore.List.length(b)
      width = TemperCore.int32(m + 1)
      table = TemperCore.List.builder()
      k = 0
      ex_loop_39 = fn ex_loop_39, k ->
        if k < TemperCore.int32(TemperCore.int32(n + 1) * width) do
          TemperCore.List.add(table, 0)
          k = TemperCore.int32(k + 1)
          ex_loop_39.(ex_loop_39, k)
        else
          k
        end
      end
      _k = ex_loop_39.(ex_loop_39, k)
      i1 = TemperCore.int32(n - 1)
      ex_loop_41 = fn ex_loop_41, i1 ->
        if i1 >= 0 do
          j2 = TemperCore.int32(m - 1)
          ex_loop_43 = fn ex_loop_43, j2 ->
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
              ex_loop_43.(ex_loop_43, j2)
            else
              j2
            end
          end
          _j2 = ex_loop_43.(ex_loop_43, j2)
          i1 = TemperCore.int32(i1 - 1)
          ex_loop_41.(ex_loop_41, i1)
        else
          i1
        end
      end
      _i1 = ex_loop_41.(ex_loop_41, i1)
      out = TemperCore.List.builder()
      dels = TemperCore.List.builder()
      ins = TemperCore.List.builder()
      i2 = 0
      j1 = 0
      ex_loop_45 = fn ex_loop_45, i2, j1 ->
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
              Temper.MarginaliaCore.flushRun__102(dels, ins, out)
              TemperCore.List.add(out, Temper.MarginaliaCore.Row.new("same", TemperCore.List.get(a, i2), TemperCore.List.get(a, i2)))
              i2 = TemperCore.int32(i2 + 1)
              j1 = TemperCore.int32(j1 + 1)
              ex_loop_45.(ex_loop_45, i2, j1)
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
                ex_loop_45.(ex_loop_45, i2, j1)
              else
                TemperCore.List.add(dels, TemperCore.List.get(a, i2))
                i2 = TemperCore.int32(i2 + 1)
                ex_loop_45.(ex_loop_45, i2, j1)
              end
            end
          end
        else
          {i2, j1}
        end
      end
      {_i2, _j1} = ex_loop_45.(ex_loop_45, i2, j1)
      Temper.MarginaliaCore.flushRun__102(dels, ins, out)
      TemperCore.List.to_list(out)
    end)
  end
  def trailingStart(s) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      e = TemperCore.String.end_of(s)
      ex_loop_48 = fn ex_loop_48, e ->
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
            ex_loop_48.(ex_loop_48, e)
          end
        else
          e
        end
      end
      e = ex_loop_48.(ex_loop_48, e)
      e
    end)
  end
  def wordsOf(text) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      out = TemperCore.List.builder()
      i = TemperCore.String.begin()
      ex_loop_51 = fn ex_loop_51, i ->
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
            ex_loop_51.(ex_loop_51, i)
          end
        else
          i
        end
      end
      i = ex_loop_51.(ex_loop_51, i)
      ex_loop_53 = fn ex_loop_53, i ->
        if TemperCore.String.has_index(text, i) do
          start = i
          ex_loop_55 = fn ex_loop_55, i ->
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
                ex_loop_55.(ex_loop_55, i)
              end
            else
              i
            end
          end
          i = ex_loop_55.(ex_loop_55, i)
          ex_loop_57 = fn ex_loop_57, i ->
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
                ex_loop_57.(ex_loop_57, i)
              end
            else
              i
            end
          end
          i = ex_loop_57.(ex_loop_57, i)
          TemperCore.List.add(out, TemperCore.String.slice(text, start, i))
          ex_loop_53.(ex_loop_53, i)
        else
          i
        end
      end
      _i = ex_loop_53.(ex_loop_53, i)
      TemperCore.List.to_list(out)
    end)
  end
  def distinct__104(words) do
    set = TemperCore.Map.builder()
    k = 0
    ex_loop_60 = fn ex_loop_60, k ->
      if k < TemperCore.List.length(words) do
        TemperCore.Map.set(set, TemperCore.List.get(words, k), true)
        k = TemperCore.int32(k + 1)
        ex_loop_60.(ex_loop_60, k)
      else
        k
      end
    end
    _k = ex_loop_60.(ex_loop_60, k)
    set
  end
  def unrelated__103(ak, bk) do
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
          a = TemperCore.Map.to_map(Temper.MarginaliaCore.distinct__104(ak))
          b = TemperCore.Map.to_map(Temper.MarginaliaCore.distinct__104(bk))
          bKeys = TemperCore.Map.keys(b)
          shared = 0
          k = 0
          ex_loop_64 = fn ex_loop_64, k, shared ->
            if k < TemperCore.List.length(bKeys) do
              shared = if TemperCore.Map.has(a, TemperCore.List.get(bKeys, k)) do
                shared = TemperCore.int32(shared + 1)
                shared
              else
                shared
              end
              k = TemperCore.int32(k + 1)
              ex_loop_64.(ex_loop_64, k, shared)
            else
              {k, shared}
            end
          end
          {_k, shared} = ex_loop_64.(ex_loop_64, k, shared)
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
          throw({:temper_return, :ex_return_62, TemperCore.Float.lt(TemperCore.int_to_float(shared), TemperCore.Float.mul(0.05, TemperCore.int_to_float(smaller)))})
        end
      end
      return
    catch
      {:temper_return, :ex_return_62, ex_value_66} ->
        ex_value_66
    end
  end
  def attach__111(script, aw, bw, parts) do
    ai = 0
    bi = 0
    c = 0
    ex_loop_68 = fn ex_loop_68, ai, bi, c ->
      if c < TemperCore.List.length(script) do
        chunk = TemperCore.List.get(script, c)
        count = TemperCore.List.length(Temper.MarginaliaCore.Chunk.get_words(chunk))
        k = 0
        ex_loop_70 = fn ex_loop_70, ai, bi, k ->
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
            ex_loop_70.(ex_loop_70, ai, bi, k)
          else
            {ai, bi, k}
          end
        end
        {ai, bi, _k} = ex_loop_70.(ex_loop_70, ai, bi, k)
        c = TemperCore.int32(c + 1)
        ex_loop_68.(ex_loop_68, ai, bi, c)
      else
        {ai, bi, c}
      end
    end
    {_ai, _bi, _c} = ex_loop_68.(ex_loop_68, ai, bi, c)
    nil
  end
  def moveDown__106(p, a) do
    if Temper.MarginaliaCore.Path.get_i(p) < TemperCore.List.length(a) do
      Temper.MarginaliaCore.Path.new(TemperCore.int32(Temper.MarginaliaCore.Path.get_y(p) + 1), TemperCore.int32(Temper.MarginaliaCore.Path.get_i(p) + 1), Temper.MarginaliaCore.Path.get_j(p), Temper.MarginaliaCore.Edit.new(1, TemperCore.List.get(a, Temper.MarginaliaCore.Path.get_i(p)), Temper.MarginaliaCore.Path.get_edits(p)))
    else
      Temper.MarginaliaCore.Path.new(TemperCore.int32(Temper.MarginaliaCore.Path.get_y(p) + 1), Temper.MarginaliaCore.Path.get_i(p), Temper.MarginaliaCore.Path.get_j(p), Temper.MarginaliaCore.Path.get_edits(p))
    end
  end
  def moveRight__105(p, b) do
    if Temper.MarginaliaCore.Path.get_j(p) < TemperCore.List.length(b) do
      Temper.MarginaliaCore.Path.new(Temper.MarginaliaCore.Path.get_y(p), Temper.MarginaliaCore.Path.get_i(p), TemperCore.int32(Temper.MarginaliaCore.Path.get_j(p) + 1), Temper.MarginaliaCore.Edit.new(2, TemperCore.List.get(b, Temper.MarginaliaCore.Path.get_j(p)), Temper.MarginaliaCore.Path.get_edits(p)))
    else
      p
    end
  end
  def followSnake__107(p, a, b) do
    y = Temper.MarginaliaCore.Path.get_y(p)
    i = Temper.MarginaliaCore.Path.get_i(p)
    j = Temper.MarginaliaCore.Path.get_j(p)
    edits = Temper.MarginaliaCore.Path.get_edits(p)
    ex_loop_75 = fn ex_loop_75, edits, i, j, y ->
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
          ex_loop_75.(ex_loop_75, edits, i, j, y)
        end
      else
        {edits, i, j, y}
      end
    end
    {edits, i, j, y} = ex_loop_75.(ex_loop_75, edits, i, j, y)
    Temper.MarginaliaCore.Path.new(y, i, j, edits)
  end
  def sameWords__110(x, y) do
    try do
      return = nil
      return = try do
        if TemperCore.List.length(x) != TemperCore.List.length(y) do
          return = false
          return
        else
          k = 0
          ex_loop_79 = fn ex_loop_79, k, return ->
            if k < TemperCore.List.length(x) do
              if TemperCore.List.get(x, k) != TemperCore.List.get(y, k) do
                return = false
                throw({:temper_break, :ex_block_78, return})
              else
                k = TemperCore.int32(k + 1)
                ex_loop_79.(ex_loop_79, k, return)
              end
            else
              {k, return}
            end
          end
          {_k, _return} = ex_loop_79.(ex_loop_79, k, return)
          throw({:temper_return, :ex_return_77, true})
        end
      catch
        {:temper_break, :ex_block_78, ex_vars_81} ->
          ex_vars_81
      end
      return
    catch
      {:temper_return, :ex_return_77, ex_value_82} ->
        ex_value_82
    end
  end
  def compact__109(edits) do
    out = TemperCore.List.builder()
    e = edits
    ex_loop_84 = fn ex_loop_84, e ->
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
          ex_loop_84.(ex_loop_84, e)
        else
          _t2 = nil
          t2 = if n >= 3 do
            if Temper.MarginaliaCore.Chunk.get_kind(TemperCore.List.get(out, TemperCore.int32(n - 1))) == 0 do
              if Temper.MarginaliaCore.Chunk.get_kind(TemperCore.List.get(out, TemperCore.int32(n - 2))) == 2 do
                if Temper.MarginaliaCore.Chunk.get_kind(TemperCore.List.get(out, TemperCore.int32(n - 3))) == 0 do
                  t2 = Temper.MarginaliaCore.sameWords__110(Temper.MarginaliaCore.Chunk.get_words(TemperCore.List.get(out, TemperCore.int32(n - 1))), Temper.MarginaliaCore.Chunk.get_words(TemperCore.List.get(out, TemperCore.int32(n - 2))))
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
            ex_loop_84.(ex_loop_84, e)
          else
            words = TemperCore.List.builder()
            TemperCore.List.add(words, Temper.MarginaliaCore.Edit.get_word(edit))
            TemperCore.List.add(out, Temper.MarginaliaCore.Chunk.new(Temper.MarginaliaCore.Edit.get_kind(edit), words))
            e = Temper.MarginaliaCore.Edit.get_before(edit)
            ex_loop_84.(ex_loop_84, e)
          end
        end
      else
        e
      end
    end
    _e = ex_loop_84.(ex_loop_84, e)
    TemperCore.List.reverse(out)
    k = 0
    ex_loop_86 = fn ex_loop_86, k ->
      if k < TemperCore.List.length(out) do
        TemperCore.List.reverse(Temper.MarginaliaCore.Chunk.get_words(TemperCore.List.get(out, k)))
        k = TemperCore.int32(k + 1)
        ex_loop_86.(ex_loop_86, k)
      else
        k
      end
    end
    _k = ex_loop_86.(ex_loop_86, k)
    TemperCore.List.to_list(out)
  end
  def myers__108(a, b) do
    return = nil
    return = try do
      paths = %TemperCore.Vec{t: {Temper.MarginaliaCore.Path.new(0, 0, 0, nil)}}
      envelope = 0
      ex_loop_90 = fn ex_loop_90, envelope, paths, return ->
        if true do
          next = TemperCore.List.builder()
          at = 0
          diag = TemperCore.int32(-envelope)
          ex_loop_92 = fn ex_loop_92, at, diag, return ->
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
                  path = Temper.MarginaliaCore.moveDown__106(path, a)
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
                    path = Temper.MarginaliaCore.moveRight__105(path, b)
                    at = TemperCore.int32(at + 1)
                    {at, path}
                  else
                    _t4 = nil
                    second = TemperCore.List.get(paths, TemperCore.int32(at + 1))
                    t4 = if Temper.MarginaliaCore.Path.get_y(path) > Temper.MarginaliaCore.Path.get_y(second) do
                      t4 = Temper.MarginaliaCore.moveRight__105(path, b)
                      t4
                    else
                      t4 = Temper.MarginaliaCore.moveDown__106(second, a)
                      t4
                    end
                    path = t4
                    at = TemperCore.int32(at + 1)
                    {at, path}
                  end
              end
              path = Temper.MarginaliaCore.followSnake__107(path, a, b)
              _t2 = nil
              t2 = if Temper.MarginaliaCore.Path.get_i(path) == TemperCore.List.length(a) do
                t2 = Temper.MarginaliaCore.Path.get_j(path) == TemperCore.List.length(b)
                t2
              else
                t2 = false
                t2
              end
              if t2 do
                return = Temper.MarginaliaCore.compact__109(Temper.MarginaliaCore.Path.get_edits(path))
                throw({:temper_break, :ex_block_89, return})
              else
                TemperCore.List.add(next, path)
                diag = TemperCore.int32(diag + 2)
                ex_loop_92.(ex_loop_92, at, diag, return)
              end
            else
              {at, diag, return}
            end
          end
          {_at, _diag, return} = ex_loop_92.(ex_loop_92, at, diag, return)
          paths = TemperCore.List.to_list(next)
          envelope = TemperCore.int32(envelope + 1)
          ex_loop_90.(ex_loop_90, envelope, paths, return)
        else
          {envelope, paths, return}
        end
      end
      {_envelope, _paths, return} = ex_loop_90.(ex_loop_90, envelope, paths, return)
      return
    catch
      {:temper_break, :ex_block_89, ex_vars_94} ->
        ex_vars_94
    end
    return
  end
  def merge__112(parts) do
    out = TemperCore.List.builder()
    k = 0
    ex_loop_96 = fn ex_loop_96, k ->
      if k < TemperCore.List.length(parts) do
        kind = Temper.MarginaliaCore.Part.get_kind(TemperCore.List.get(parts, k))
        text = TemperCore.StringBuilder.new()
        ex_loop_98 = fn ex_loop_98, k ->
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
              ex_loop_98.(ex_loop_98, k)
            end
          else
            k
          end
        end
        k = ex_loop_98.(ex_loop_98, k)
        TemperCore.List.add(out, Temper.MarginaliaCore.Part.new(kind, TemperCore.StringBuilder.to_string(text)))
        ex_loop_96.(ex_loop_96, k)
      else
        k
      end
    end
    _k = ex_loop_96.(ex_loop_96, k)
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
      if Temper.MarginaliaCore.unrelated__103(ak, bk) do
        k1 = 0
        ex_loop_103 = fn ex_loop_103, k1 ->
          if k1 < TemperCore.List.length(aw) do
            TemperCore.List.add(parts, Temper.MarginaliaCore.Part.new("del", TemperCore.List.get(aw, k1)))
            k1 = TemperCore.int32(k1 + 1)
            ex_loop_103.(ex_loop_103, k1)
          else
            k1
          end
        end
        _k1 = ex_loop_103.(ex_loop_103, k1)
        k2 = 0
        ex_loop_105 = fn ex_loop_105, k2 ->
          if k2 < TemperCore.List.length(bw) do
            TemperCore.List.add(parts, Temper.MarginaliaCore.Part.new("ins", TemperCore.List.get(bw, k2)))
            k2 = TemperCore.int32(k2 + 1)
            ex_loop_105.(ex_loop_105, k2)
          else
            k2
          end
        end
        _k2 = ex_loop_105.(ex_loop_105, k2)
        nil
      else
        Temper.MarginaliaCore.attach__111(Temper.MarginaliaCore.myers__108(ak, bk), aw, bw, parts)
        nil
      end
      Temper.MarginaliaCore.merge__112(TemperCore.List.to_list(parts))
    end)
  end
  def __temper_init__() do
    TemperCore.init_once(:"Temper.MarginaliaCore", fn ->
      TemperCore.Global.put(:"Temper.MarginaliaCore.v_EQ__113", 0)
      TemperCore.Global.put(:"Temper.MarginaliaCore.v_DEL__114", 1)
      TemperCore.Global.put(:"Temper.MarginaliaCore.v_INS__115", 2)
      nil
    end)
  end
  def main() do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Async.drain()
  end
end
