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
defmodule Temper.MarginaliaCore.Param do
  defstruct [:kind, :text]
  def __temper_supertypes__() do
    [Temper.MarginaliaCore.Param]
  end
  def new(kind, text) do
    Temper.MarginaliaCore.__temper_init__()
    this = %Temper.MarginaliaCore.Param{}
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
defmodule Temper.MarginaliaCore.Statement do
  defstruct [:text, :params]
  def __temper_supertypes__() do
    [Temper.MarginaliaCore.Statement]
  end
  def new(text, params) do
    Temper.MarginaliaCore.__temper_init__()
    this = %Temper.MarginaliaCore.Statement{}
    this = %{this | :text => text}
    this = %{this | :params => params}
    this
  end
  def get_text(this) do
    this.text
  end
  def get_params(this) do
    this.params
  end
end
defmodule Temper.MarginaliaCore.FieldError do
  defstruct [:field, :message]
  def __temper_supertypes__() do
    [Temper.MarginaliaCore.FieldError]
  end
  def new(field, message) do
    Temper.MarginaliaCore.__temper_init__()
    this = %Temper.MarginaliaCore.FieldError{}
    this = %{this | :field => field}
    this = %{this | :message => message}
    this
  end
  def get_field(this) do
    this.field
  end
  def get_message(this) do
    this.message
  end
end
defmodule Temper.MarginaliaCore.Prepared do
  defstruct [:statement, :errors]
  def __temper_supertypes__() do
    [Temper.MarginaliaCore.Prepared]
  end
  def new(statement, errors) do
    Temper.MarginaliaCore.__temper_init__()
    this = %Temper.MarginaliaCore.Prepared{}
    this = %{this | :statement => statement}
    this = %{this | :errors => errors}
    this
  end
  def get_statement(this) do
    this.statement
  end
  def get_errors(this) do
    this.errors
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
            throw({:temper_return, :ex_return_0, Temper.MarginaliaCore.joinWith(TemperCore.List.map(Temper.MarginaliaCore.blocks(text), fn_), "\n\n")})
          end
        end
        return
      catch
        {:temper_return, :ex_return_0, ex_value_3} ->
          ex_value_3
      end
    end)
  end
  def startsWith(s, prefix) do
    try do
      return = nil
      return = try do
        i = TemperCore.String.begin()
        j = TemperCore.String.begin()
        ex_loop_2 = fn ex_loop_2, i, j, return ->
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
              throw({:temper_break, :ex_block_1, return})
            else
              i = TemperCore.String.next(s, i)
              j = TemperCore.String.next(prefix, j)
              ex_loop_2.(ex_loop_2, i, j, return)
            end
          else
            {i, j, return}
          end
        end
        {_i, _j, _return} = ex_loop_2.(ex_loop_2, i, j, return)
        throw({:temper_return, :ex_return_0, true})
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
  def isRegexSpace(cp) do
    cond do
      cp == 32 ->
        true
      cp >= 9 ->
        cp <= 13
      true ->
        false
    end
  end
  def isTrimSpace(cp) do
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
  end
  def leadingEnd(s) do
    b = TemperCore.String.begin()
    ex_loop_1 = fn ex_loop_1, b ->
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
          ex_loop_1.(ex_loop_1, b)
        end
      else
        b
      end
    end
    b = ex_loop_1.(ex_loop_1, b)
    b
  end
  def trimLeading(s) do
    TemperCore.String.slice(s, Temper.MarginaliaCore.leadingEnd(s), TemperCore.String.end_of(s))
  end
  def joinWith(parts, sep) do
    fn_ = fn p ->
      p
    end
    TemperCore.List.join(parts, sep, fn_)
  end
  def flushBlock(current, out) do
    if not TemperCore.List.is_empty(current) do
      TemperCore.List.add(out, Temper.MarginaliaCore.joinWith(TemperCore.List.to_list(current), "\n"))
      TemperCore.List.clear(current)
      nil
    else
      nil
    end
    nil
  end
  def fenceOpener(line) do
    try do
      _return = nil
      return = if true do
        i = TemperCore.String.begin()
        ex_loop_2 = fn ex_loop_2, i ->
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
              ex_loop_2.(ex_loop_2, i)
            end
          else
            i
          end
        end
        i = ex_loop_2.(ex_loop_2, i)
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
            ex_loop_4 = fn ex_loop_4, count, i ->
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
                  ex_loop_4.(ex_loop_4, count, i)
                end
              else
                {count, i}
              end
            end
            {count, i} = ex_loop_4.(ex_loop_4, count, i)
            if count >= 3 do
              throw({:temper_return, :ex_return_0, TemperCore.String.slice(line, start, i)})
            else
              throw({:temper_return, :ex_return_0, nil})
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
  def trim(s) do
    b = TemperCore.String.begin()
    ex_loop_1 = fn ex_loop_1, b ->
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
          ex_loop_1.(ex_loop_1, b)
        end
      else
        b
      end
    end
    b = ex_loop_1.(ex_loop_1, b)
    e = TemperCore.String.end_of(s)
    ex_loop_3 = fn ex_loop_3, e ->
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
          ex_loop_3.(ex_loop_3, e)
        end
      else
        e
      end
    end
    e = ex_loop_3.(ex_loop_3, e)
    TemperCore.String.slice(s, b, e)
  end
  def trailingStart(s) do
    e = TemperCore.String.end_of(s)
    ex_loop_1 = fn ex_loop_1, e ->
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
          ex_loop_1.(ex_loop_1, e)
        end
      else
        e
      end
    end
    e = ex_loop_1.(ex_loop_1, e)
    e
  end
  def trimTrailing(s) do
    TemperCore.String.slice(s, TemperCore.String.begin(), Temper.MarginaliaCore.trailingStart(s))
  end
  def blocks(body) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      out = TemperCore.List.builder()
      current = TemperCore.List.builder()
      fence = nil
      lines = TemperCore.String.split(body, "\n")
      k1 = 0
      ex_loop_1 = fn ex_loop_1, fence, k1 ->
        if k1 < TemperCore.List.length(lines) do
          line = TemperCore.List.get(lines, k1)
          open1 = fence
          fence = if not (open1 === nil) do
            open2 = open1
            TemperCore.List.add(current, line)
            if Temper.MarginaliaCore.startsWith(Temper.MarginaliaCore.trimLeading(line), open2) do
              Temper.MarginaliaCore.flushBlock(current, out)
              fence = nil
              fence
            else
              fence
            end
          else
            opener1 = Temper.MarginaliaCore.fenceOpener(line)
            cond do
              not (opener1 === nil) ->
                opener2 = opener1
                Temper.MarginaliaCore.flushBlock(current, out)
                TemperCore.List.add(current, line)
                fence = opener2
                fence
              TemperCore.String.is_empty(Temper.MarginaliaCore.trim(line)) ->
                Temper.MarginaliaCore.flushBlock(current, out)
                fence
              true ->
                TemperCore.List.add(current, line)
                fence
            end
          end
          k1 = TemperCore.int32(k1 + 1)
          ex_loop_1.(ex_loop_1, fence, k1)
        else
          {fence, k1}
        end
      end
      {_fence, _k1} = ex_loop_1.(ex_loop_1, fence, k1)
      Temper.MarginaliaCore.flushBlock(current, out)
      kept = TemperCore.List.builder()
      all = TemperCore.List.to_list(out)
      k2 = 0
      ex_loop_3 = fn ex_loop_3, k2 ->
        if k2 < TemperCore.List.length(all) do
          block = Temper.MarginaliaCore.trimTrailing(TemperCore.List.get(all, k2))
          if not TemperCore.String.is_empty(Temper.MarginaliaCore.trim(block)) do
            TemperCore.List.add(kept, block)
            nil
          else
            nil
          end
          k2 = TemperCore.int32(k2 + 1)
          ex_loop_3.(ex_loop_3, k2)
        else
          k2
        end
      end
      _k2 = ex_loop_3.(ex_loop_3, k2)
      TemperCore.List.to_list(kept)
    end)
  end
  def flushParagraph(piece, out) do
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
      runStart = TemperCore.String.begin()
      i = TemperCore.String.begin()
      ex_loop_1 = fn ex_loop_1, i, newlines, runStart ->
        if TemperCore.String.has_index(text, i) do
          after_ = TemperCore.String.next(text, i)
          _crlf = nil
          crlf = if TemperCore.String.get(text, i) == 13 do
            if TemperCore.String.has_index(text, after_) do
              crlf = TemperCore.String.get(text, after_) == 10
              crlf
            else
              crlf = false
              crlf
            end
          else
            crlf = false
            crlf
          end
          _t = nil
          t = if TemperCore.String.get(text, i) == 10 do
            t = true
            t
          else
            t = crlf
            t
          end
          {i, newlines, runStart} = cond do
            t ->
              if newlines == 0 do
                TemperCore.StringBuilder.append_between(piece, text, runStart, i)
                nil
              else
                nil
              end
              newlines = TemperCore.int32(newlines + 1)
              if crlf do
                i = after_
                {i, newlines, runStart}
              else
                {i, newlines, runStart}
              end
            newlines > 0 ->
              if newlines >= 2 do
                Temper.MarginaliaCore.flushParagraph(piece, out)
                nil
              else
                TemperCore.StringBuilder.append(piece, "\n")
                nil
              end
              newlines = 0
              runStart = i
              {i, newlines, runStart}
            true ->
              {i, newlines, runStart}
          end
          i = TemperCore.String.next(text, i)
          ex_loop_1.(ex_loop_1, i, newlines, runStart)
        else
          {i, newlines, runStart}
        end
      end
      {_i, newlines, runStart} = ex_loop_1.(ex_loop_1, i, newlines, runStart)
      if newlines == 0 do
        TemperCore.StringBuilder.append_between(piece, text, runStart, TemperCore.String.end_of(text))
        nil
      else
        nil
      end
      if newlines == 1 do
        TemperCore.StringBuilder.append(piece, "\n")
        nil
      else
        nil
      end
      Temper.MarginaliaCore.flushParagraph(piece, out)
      TemperCore.List.to_list(out)
    end)
  end
  def alignmentKey(p) do
    out = TemperCore.StringBuilder.new()
    inSpace = false
    runStart = TemperCore.String.begin()
    i = TemperCore.String.begin()
    ex_loop_1 = fn ex_loop_1, i, inSpace, runStart ->
      if TemperCore.String.has_index(p, i) do
        {inSpace, runStart} = if Temper.MarginaliaCore.isRegexSpace(TemperCore.String.get(p, i)) do
          if not inSpace do
            TemperCore.StringBuilder.append_between(out, p, runStart, i)
            nil
          else
            nil
          end
          inSpace = true
          {inSpace, runStart}
        else
          runStart = if inSpace do
            TemperCore.StringBuilder.append(out, " ")
            runStart = i
            runStart
          else
            runStart
          end
          inSpace = false
          {inSpace, runStart}
        end
        i = TemperCore.String.next(p, i)
        ex_loop_1.(ex_loop_1, i, inSpace, runStart)
      else
        {i, inSpace, runStart}
      end
    end
    {_i, inSpace, runStart} = ex_loop_1.(ex_loop_1, i, inSpace, runStart)
    if inSpace do
      TemperCore.StringBuilder.append(out, " ")
      nil
    else
      TemperCore.StringBuilder.append_between(out, p, runStart, TemperCore.String.end_of(p))
      nil
    end
    Temper.MarginaliaCore.trim(TemperCore.StringBuilder.to_string(out))
  end
  def flushRun(dels, ins, out) do
    _longer = nil
    longer = if TemperCore.List.length(dels) > TemperCore.List.length(ins) do
      longer = TemperCore.List.length(dels)
      longer
    else
      longer = TemperCore.List.length(ins)
      longer
    end
    k = 0
    ex_loop_1 = fn ex_loop_1, k ->
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
        ex_loop_1.(ex_loop_1, k)
      else
        k
      end
    end
    _k = ex_loop_1.(ex_loop_1, k)
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
        Temper.MarginaliaCore.alignmentKey(p1)
      end
      ak = TemperCore.List.map(a, fn_1)
      fn_2 = fn p2 ->
        Temper.MarginaliaCore.alignmentKey(p2)
      end
      bk = TemperCore.List.map(b, fn_2)
      n = TemperCore.List.length(a)
      m = TemperCore.List.length(b)
      width = TemperCore.int32(m + 1)
      table = TemperCore.List.builder()
      k = 0
      ex_loop_3 = fn ex_loop_3, k ->
        if k < TemperCore.int32(TemperCore.int32(n + 1) * width) do
          TemperCore.List.add(table, 0)
          k = TemperCore.int32(k + 1)
          ex_loop_3.(ex_loop_3, k)
        else
          k
        end
      end
      _k = ex_loop_3.(ex_loop_3, k)
      i1 = TemperCore.int32(n - 1)
      ex_loop_5 = fn ex_loop_5, i1 ->
        if i1 >= 0 do
          j2 = TemperCore.int32(m - 1)
          ex_loop_7 = fn ex_loop_7, j2 ->
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
              ex_loop_7.(ex_loop_7, j2)
            else
              j2
            end
          end
          _j2 = ex_loop_7.(ex_loop_7, j2)
          i1 = TemperCore.int32(i1 - 1)
          ex_loop_5.(ex_loop_5, i1)
        else
          i1
        end
      end
      _i1 = ex_loop_5.(ex_loop_5, i1)
      out = TemperCore.List.builder()
      dels = TemperCore.List.builder()
      ins = TemperCore.List.builder()
      i2 = 0
      j1 = 0
      ex_loop_9 = fn ex_loop_9, i2, j1 ->
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
              Temper.MarginaliaCore.flushRun(dels, ins, out)
              TemperCore.List.add(out, Temper.MarginaliaCore.Row.new("same", TemperCore.List.get(a, i2), TemperCore.List.get(a, i2)))
              i2 = TemperCore.int32(i2 + 1)
              j1 = TemperCore.int32(j1 + 1)
              ex_loop_9.(ex_loop_9, i2, j1)
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
                ex_loop_9.(ex_loop_9, i2, j1)
              else
                TemperCore.List.add(dels, TemperCore.List.get(a, i2))
                i2 = TemperCore.int32(i2 + 1)
                ex_loop_9.(ex_loop_9, i2, j1)
              end
            end
          end
        else
          {i2, j1}
        end
      end
      {_i2, _j1} = ex_loop_9.(ex_loop_9, i2, j1)
      Temper.MarginaliaCore.flushRun(dels, ins, out)
      TemperCore.List.to_list(out)
    end)
  end
  def paramOf(part) do
    try do
      _return = nil
      return = if true do
        cond do
          TemperCore.is_a(part, Temper.Orm.SqlString) ->
            t1 = part
            t2 = t1
            return = Temper.MarginaliaCore.Param.new("text", Temper.Orm.SqlString.get_value(t2))
            return
          TemperCore.is_a(part, Temper.Orm.SqlInt64) ->
            t3 = part
            t4 = t3
            return = Temper.MarginaliaCore.Param.new("int", TemperCore.int_to_string(Temper.Orm.SqlInt64.get_value(t4)))
            return
          TemperCore.is_a(part, Temper.Orm.SqlInt32) ->
            t5 = part
            t6 = t5
            return = Temper.MarginaliaCore.Param.new("int", TemperCore.int_to_string(Temper.Orm.SqlInt32.get_value(t6)))
            return
          TemperCore.is_a(part, Temper.Orm.SqlBoolean) ->
            t7 = part
            _t8 = nil
            t9 = t7
            t8 = if Temper.Orm.SqlBoolean.get_value(t9) do
              t8 = "true"
              t8
            else
              t8 = "false"
              t8
            end
            return = Temper.MarginaliaCore.Param.new("bool", t8)
            return
          TemperCore.is_a(part, Temper.Orm.SqlFloat64) ->
            t10 = part
            t11 = t10
            return = Temper.MarginaliaCore.Param.new("float", TemperCore.Float.to_string(Temper.Orm.SqlFloat64.get_value(t11)))
            return
          TemperCore.is_a(part, Temper.Orm.SqlDate) ->
            t12 = part
            t13 = t12
            return = Temper.MarginaliaCore.Param.new("date", Temper.Std.Date.toString(Temper.Orm.SqlDate.get_value(t13)))
            return
          true ->
            throw({:temper_return, :ex_return_0, nil})
        end
      end
      return
    catch
      {:temper_return, :ex_return_0, ex_value_2} ->
        ex_value_2
    end
  end
  def statementOf(fragment) do
    text = TemperCore.StringBuilder.new()
    params = TemperCore.List.builder()
    this = Temper.Orm.SqlFragment.get_parts(fragment)
    n = TemperCore.List.length(this)
    i = 0
    ex_loop_1 = fn ex_loop_1, i ->
      if i < n do
        el = TemperCore.List.get(this, i)
        i = TemperCore.int32(i + 1)
        part = el
        param = Temper.MarginaliaCore.paramOf(part)
        if param === nil do
          TemperCore.call(part, :formatTo, [text])
          ex_loop_1.(ex_loop_1, i)
        else
          TemperCore.List.add(params, param)
          TemperCore.StringBuilder.append(text, "$")
          TemperCore.StringBuilder.append(text, TemperCore.int_to_string(TemperCore.List.length(params)))
          ex_loop_1.(ex_loop_1, i)
        end
      else
        i
      end
    end
    _i = ex_loop_1.(ex_loop_1, i)
    Temper.MarginaliaCore.Statement.new(TemperCore.StringBuilder.to_string(text), TemperCore.List.to_list(params))
  end
  def id(name) do
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
  def columnIds() do
    fn_ = fn c ->
      Temper.MarginaliaCore.id(c)
    end
    TemperCore.List.map(TemperCore.Global.get(:"Temper.MarginaliaCore.columns"), fn_)
  end
  def returning(statement) do
    b = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendFragment(b, statement)
    Temper.Orm.SqlBuilder.appendSafe(b, " RETURNING ")
    fn_ = fn c ->
      c
    end
    Temper.Orm.SqlBuilder.appendSafe(b, TemperCore.List.join(TemperCore.Global.get(:"Temper.MarginaliaCore.columns"), ", ", fn_))
    Temper.MarginaliaCore.statementOf(Temper.Orm.SqlBuilder.get_accumulated(b))
  end
  def nullable(value) do
    if value === nil do
      Temper.Orm.SqlSource.new("NULL")
    else
      Temper.Orm.SqlInt64.new(value)
    end
  end
  def listFolders(userId) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      exprs = TemperCore.List.builder()
      this = TemperCore.Global.get(:"Temper.MarginaliaCore.columns")
      n = TemperCore.List.length(this)
      i = 0
      ex_loop_1 = fn ex_loop_1, i ->
        if i < n do
          el = TemperCore.List.get(this, i)
          i = TemperCore.int32(i + 1)
          c = el
          TemperCore.List.add(exprs, Temper.Orm.col(Temper.MarginaliaCore.id("folders"), Temper.MarginaliaCore.id(c)))
          ex_loop_1.(ex_loop_1, i)
        else
          i
        end
      end
      _i = ex_loop_1.(ex_loop_1, i)
      accumulator1 = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(accumulator1, "lower(name) AS name_key")
      TemperCore.List.add(exprs, Temper.Orm.SqlBuilder.get_accumulated(accumulator1))
      t = Temper.Orm.Query.selectExpr(Temper.Orm.from(Temper.MarginaliaCore.id("folders")), TemperCore.List.to_list(exprs))
      accumulator2 = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(accumulator2, "user_id = ")
      Temper.Orm.SqlBuilder.appendInt64(accumulator2, userId)
      Temper.MarginaliaCore.statementOf(Temper.Orm.Query.toSql(Temper.Orm.Query.orderBy(Temper.Orm.Query.orderBy(Temper.Orm.Query.where(t, Temper.Orm.SqlBuilder.get_accumulated(accumulator2)), Temper.MarginaliaCore.id("name_key"), true), Temper.MarginaliaCore.id("id"), true)))
    end)
  end
  def getFolder(userId, folderId) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      t1 = Temper.Orm.Query.select(Temper.Orm.from(Temper.MarginaliaCore.id("folders")), Temper.MarginaliaCore.columnIds())
      accumulator1 = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(accumulator1, "user_id = ")
      Temper.Orm.SqlBuilder.appendInt64(accumulator1, userId)
      t2 = Temper.Orm.Query.where(t1, Temper.Orm.SqlBuilder.get_accumulated(accumulator1))
      accumulator2 = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(accumulator2, "id = ")
      Temper.Orm.SqlBuilder.appendInt64(accumulator2, folderId)
      Temper.MarginaliaCore.statementOf(Temper.Orm.Query.toSql(Temper.Orm.Query.where(t2, Temper.Orm.SqlBuilder.get_accumulated(accumulator2))))
    end)
  end
  def foldersByIds(ids) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      fn_ = fn i ->
        Temper.Orm.SqlInt64.new(i)
      end
      Temper.MarginaliaCore.statementOf(Temper.Orm.Query.toSql(Temper.Orm.Query.whereIn(Temper.Orm.Query.select(Temper.Orm.from(Temper.MarginaliaCore.id("folders")), Temper.MarginaliaCore.columnIds()), Temper.MarginaliaCore.id("id"), TemperCore.List.map(ids, fn_))))
    end)
  end
  def folderByName(userId, name) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      t1 = Temper.Orm.Query.select(Temper.Orm.from(Temper.MarginaliaCore.id("folders")), Temper.MarginaliaCore.columnIds())
      accumulator1 = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(accumulator1, "user_id = ")
      Temper.Orm.SqlBuilder.appendInt64(accumulator1, userId)
      t2 = Temper.Orm.Query.where(t1, Temper.Orm.SqlBuilder.get_accumulated(accumulator1))
      accumulator2 = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(accumulator2, "name = ")
      Temper.Orm.SqlBuilder.appendString(accumulator2, name)
      Temper.MarginaliaCore.statementOf(Temper.Orm.Query.toSql(Temper.Orm.Query.where(t2, Temper.Orm.SqlBuilder.get_accumulated(accumulator2))))
    end)
  end
  def sibling(userId, name, parentId1) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      t1 = Temper.Orm.Query.select(Temper.Orm.from(Temper.MarginaliaCore.id("folders")), Temper.MarginaliaCore.columnIds())
      accumulator1 = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(accumulator1, "user_id = ")
      Temper.Orm.SqlBuilder.appendInt64(accumulator1, userId)
      t2 = Temper.Orm.Query.where(t1, Temper.Orm.SqlBuilder.get_accumulated(accumulator1))
      accumulator2 = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(accumulator2, "name = ")
      Temper.Orm.SqlBuilder.appendString(accumulator2, name)
      q = Temper.Orm.Query.where(t2, Temper.Orm.SqlBuilder.get_accumulated(accumulator2))
      _scoped = nil
      scoped = if parentId1 === nil do
        scoped = Temper.Orm.Query.whereNull(q, Temper.MarginaliaCore.id("parent_id"))
        scoped
      else
        parentId2 = parentId1
        accumulator3 = Temper.Orm.SqlBuilder.new()
        Temper.Orm.SqlBuilder.appendSafe(accumulator3, "parent_id = ")
        Temper.Orm.SqlBuilder.appendInt64(accumulator3, parentId2)
        scoped = Temper.Orm.Query.where(q, Temper.Orm.SqlBuilder.get_accumulated(accumulator3))
        scoped
      end
      Temper.MarginaliaCore.statementOf(Temper.Orm.Query.toSql(scoped))
    end)
  end
  def nameErrors(cs) do
    fn_ = fn e ->
      Temper.MarginaliaCore.FieldError.new(Temper.Orm.ChangesetError.get_field(e), Temper.Orm.ChangesetError.get_message(e))
    end
    TemperCore.List.map(TemperCore.call(cs, :get_errors, []), fn_)
  end
  def createFolder(userId, name, parentId) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      try do
        _return = nil
        return = if true do
          _t = nil
          params = TemperCore.Map.builder()
          TemperCore.Map.set(params, "name", Temper.MarginaliaCore.trim(name))
          TemperCore.Map.set(params, "user_id", TemperCore.int_to_string(userId))
          if not (parentId === nil) do
            TemperCore.Map.set(params, "parent_id", TemperCore.int_to_string(parentId))
            nil
          else
            nil
          end
          cs = TemperCore.call(TemperCore.call(TemperCore.call(Temper.Orm.changeset(TemperCore.Global.get(:"Temper.MarginaliaCore.folders"), TemperCore.Map.to_map(params)), :cast, [%TemperCore.Vec{t: {Temper.MarginaliaCore.id("name"), Temper.MarginaliaCore.id("parent_id"), Temper.MarginaliaCore.id("user_id")}}]), :validateRequired, [%TemperCore.Vec{t: {Temper.MarginaliaCore.id("name")}}]), :validateLength, [Temper.MarginaliaCore.id("name"), 1, 80])
          if not TemperCore.call(cs, :get_isValid, []) do
            return = Temper.MarginaliaCore.Prepared.new(nil, Temper.MarginaliaCore.nameErrors(cs))
            return
          else
            t = try do
              t = TemperCore.call(cs, :toInsertSql, [])
              t
            rescue
              _ in TemperCore.Bubble ->
                raise(TemperCore.Panic)
            end
            throw({:temper_return, :ex_return_0, Temper.MarginaliaCore.Prepared.new(Temper.MarginaliaCore.returning(t), %TemperCore.Vec{t: {}})})
          end
        end
        return
      catch
        {:temper_return, :ex_return_0, ex_value_2} ->
          ex_value_2
      end
    end)
  end
  def renameFolder(userId, folderId, name) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      try do
        _return = nil
        return = if true do
          _t1 = nil
          params = TemperCore.Map.builder()
          TemperCore.Map.set(params, "name", Temper.MarginaliaCore.trim(name))
          cs = TemperCore.call(TemperCore.call(TemperCore.call(Temper.Orm.changeset(TemperCore.Global.get(:"Temper.MarginaliaCore.folders"), TemperCore.Map.to_map(params)), :cast, [%TemperCore.Vec{t: {Temper.MarginaliaCore.id("name")}}]), :validateRequired, [%TemperCore.Vec{t: {Temper.MarginaliaCore.id("name")}}]), :validateLength, [Temper.MarginaliaCore.id("name"), 1, 80])
          if not TemperCore.call(cs, :get_isValid, []) do
            return = Temper.MarginaliaCore.Prepared.new(nil, Temper.MarginaliaCore.nameErrors(cs))
            return
          else
            t1 = try do
              t2 = Temper.Orm.UpdateQuery.set(Temper.Orm.UpdateQuery.set(Temper.Orm.update(Temper.MarginaliaCore.id("folders")), Temper.MarginaliaCore.id("name"), Temper.Orm.SqlString.new(Temper.MarginaliaCore.trim(name))), Temper.MarginaliaCore.id("updated_at"), Temper.Orm.SqlSource.new("date_trunc('second', now() at time zone 'utc')"))
              accumulator1 = Temper.Orm.SqlBuilder.new()
              Temper.Orm.SqlBuilder.appendSafe(accumulator1, "user_id = ")
              Temper.Orm.SqlBuilder.appendInt64(accumulator1, userId)
              t3 = Temper.Orm.UpdateQuery.where(t2, Temper.Orm.SqlBuilder.get_accumulated(accumulator1))
              accumulator2 = Temper.Orm.SqlBuilder.new()
              Temper.Orm.SqlBuilder.appendSafe(accumulator2, "id = ")
              Temper.Orm.SqlBuilder.appendInt64(accumulator2, folderId)
              t1 = Temper.Orm.UpdateQuery.toSql(Temper.Orm.UpdateQuery.where(t3, Temper.Orm.SqlBuilder.get_accumulated(accumulator2)))
              t1
            rescue
              _ in TemperCore.Bubble ->
                raise(TemperCore.Panic)
            end
            throw({:temper_return, :ex_return_0, Temper.MarginaliaCore.Prepared.new(Temper.MarginaliaCore.returning(t1), %TemperCore.Vec{t: {}})})
          end
        end
        return
      catch
        {:temper_return, :ex_return_0, ex_value_2} ->
          ex_value_2
      end
    end)
  end
  def moveFolder(userId, folderId, parentId) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      _t1 = nil
      t1 = try do
        t2 = Temper.Orm.UpdateQuery.set(Temper.Orm.UpdateQuery.set(Temper.Orm.update(Temper.MarginaliaCore.id("folders")), Temper.MarginaliaCore.id("parent_id"), Temper.MarginaliaCore.nullable(parentId)), Temper.MarginaliaCore.id("updated_at"), Temper.Orm.SqlSource.new("date_trunc('second', now() at time zone 'utc')"))
        accumulator1 = Temper.Orm.SqlBuilder.new()
        Temper.Orm.SqlBuilder.appendSafe(accumulator1, "user_id = ")
        Temper.Orm.SqlBuilder.appendInt64(accumulator1, userId)
        t3 = Temper.Orm.UpdateQuery.where(t2, Temper.Orm.SqlBuilder.get_accumulated(accumulator1))
        accumulator2 = Temper.Orm.SqlBuilder.new()
        Temper.Orm.SqlBuilder.appendSafe(accumulator2, "id = ")
        Temper.Orm.SqlBuilder.appendInt64(accumulator2, folderId)
        t1 = Temper.Orm.UpdateQuery.toSql(Temper.Orm.UpdateQuery.where(t3, Temper.Orm.SqlBuilder.get_accumulated(accumulator2)))
        t1
      rescue
        _ in TemperCore.Bubble ->
          raise(TemperCore.Panic)
      end
      Temper.MarginaliaCore.returning(t1)
    end)
  end
  def deleteFolder(folderId, parentId) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      _t1 = nil
      _t2 = nil
      _t3 = nil
      t1 = try do
        t4 = Temper.Orm.UpdateQuery.set(Temper.Orm.update(Temper.MarginaliaCore.id("works")), Temper.MarginaliaCore.id("folder_id"), Temper.MarginaliaCore.nullable(parentId))
        accumulator1 = Temper.Orm.SqlBuilder.new()
        Temper.Orm.SqlBuilder.appendSafe(accumulator1, "folder_id = ")
        Temper.Orm.SqlBuilder.appendInt64(accumulator1, folderId)
        t1 = Temper.Orm.UpdateQuery.toSql(Temper.Orm.UpdateQuery.where(t4, Temper.Orm.SqlBuilder.get_accumulated(accumulator1)))
        t1
      rescue
        _ in TemperCore.Bubble ->
          raise(TemperCore.Panic)
      end
      t2 = try do
        t5 = Temper.Orm.UpdateQuery.set(Temper.Orm.update(Temper.MarginaliaCore.id("folders")), Temper.MarginaliaCore.id("parent_id"), Temper.MarginaliaCore.nullable(parentId))
        accumulator2 = Temper.Orm.SqlBuilder.new()
        Temper.Orm.SqlBuilder.appendSafe(accumulator2, "parent_id = ")
        Temper.Orm.SqlBuilder.appendInt64(accumulator2, folderId)
        t2 = Temper.Orm.UpdateQuery.toSql(Temper.Orm.UpdateQuery.where(t5, Temper.Orm.SqlBuilder.get_accumulated(accumulator2)))
        t2
      rescue
        _ in TemperCore.Bubble ->
          raise(TemperCore.Panic)
      end
      t3 = try do
        t6 = Temper.Orm.deleteFrom(Temper.MarginaliaCore.id("folders"))
        accumulator3 = Temper.Orm.SqlBuilder.new()
        Temper.Orm.SqlBuilder.appendSafe(accumulator3, "id = ")
        Temper.Orm.SqlBuilder.appendInt64(accumulator3, folderId)
        t3 = Temper.Orm.DeleteQuery.toSql(Temper.Orm.DeleteQuery.where(t6, Temper.Orm.SqlBuilder.get_accumulated(accumulator3)))
        t3
      rescue
        _ in TemperCore.Bubble ->
          raise(TemperCore.Panic)
      end
      %TemperCore.Vec{t: {Temper.MarginaliaCore.statementOf(t1), Temper.MarginaliaCore.statementOf(t2), Temper.MarginaliaCore.returning(t3)}}
    end)
  end
  def moveWork(userId, workId, folderId) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      _t1 = nil
      t1 = try do
        t2 = Temper.Orm.UpdateQuery.set(Temper.Orm.UpdateQuery.set(Temper.Orm.update(Temper.MarginaliaCore.id("works")), Temper.MarginaliaCore.id("folder_id"), Temper.MarginaliaCore.nullable(folderId)), Temper.MarginaliaCore.id("updated_at"), Temper.Orm.SqlSource.new("date_trunc('second', now() at time zone 'utc')"))
        accumulator1 = Temper.Orm.SqlBuilder.new()
        Temper.Orm.SqlBuilder.appendSafe(accumulator1, "user_id = ")
        Temper.Orm.SqlBuilder.appendInt64(accumulator1, userId)
        t3 = Temper.Orm.UpdateQuery.where(t2, Temper.Orm.SqlBuilder.get_accumulated(accumulator1))
        accumulator2 = Temper.Orm.SqlBuilder.new()
        Temper.Orm.SqlBuilder.appendSafe(accumulator2, "id = ")
        Temper.Orm.SqlBuilder.appendInt64(accumulator2, workId)
        t1 = Temper.Orm.UpdateQuery.toSql(Temper.Orm.UpdateQuery.where(t3, Temper.Orm.SqlBuilder.get_accumulated(accumulator2)))
        t1
      rescue
        _ in TemperCore.Bubble ->
          raise(TemperCore.Panic)
      end
      Temper.MarginaliaCore.statementOf(t1)
    end)
  end
  def looseWorks(userId) do
    t = Temper.Orm.from(Temper.MarginaliaCore.id("works"))
    accumulator = Temper.Orm.SqlBuilder.new()
    Temper.Orm.SqlBuilder.appendSafe(accumulator, "user_id = ")
    Temper.Orm.SqlBuilder.appendInt64(accumulator, userId)
    Temper.Orm.Query.whereNull(Temper.Orm.Query.whereNotNull(Temper.Orm.Query.where(t, Temper.Orm.SqlBuilder.get_accumulated(accumulator)), Temper.MarginaliaCore.id("collection")), Temper.MarginaliaCore.id("folder_id"))
  end
  def unfiledCount(userId) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      Temper.MarginaliaCore.statementOf(Temper.Orm.Query.countSql(Temper.MarginaliaCore.looseWorks(userId)))
    end)
  end
  def looseWorkCollections(userId) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      Temper.MarginaliaCore.statementOf(Temper.Orm.Query.toSql(Temper.Orm.Query.select(Temper.MarginaliaCore.looseWorks(userId), %TemperCore.Vec{t: {Temper.MarginaliaCore.id("id"), Temper.MarginaliaCore.id("collection")}})))
    end)
  end
  def fileWorks(workIds, folderId) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      _t1 = nil
      t1 = try do
        t2 = Temper.Orm.UpdateQuery.set(Temper.Orm.update(Temper.MarginaliaCore.id("works")), Temper.MarginaliaCore.id("folder_id"), Temper.Orm.SqlInt64.new(folderId))
        accumulator = Temper.Orm.SqlBuilder.new()
        Temper.Orm.SqlBuilder.appendSafe(accumulator, "id IN (")
        Temper.Orm.SqlBuilder.appendInt64List(accumulator, workIds)
        Temper.Orm.SqlBuilder.appendSafe(accumulator, ")")
        t1 = Temper.Orm.UpdateQuery.toSql(Temper.Orm.UpdateQuery.where(t2, Temper.Orm.SqlBuilder.get_accumulated(accumulator)))
        t1
      rescue
        _ in TemperCore.Bubble ->
          raise(TemperCore.Panic)
      end
      Temper.MarginaliaCore.statementOf(t1)
    end)
  end
  def publish(userId, folderId, slug) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      _t1 = nil
      t1 = try do
        t2 = Temper.Orm.UpdateQuery.set(Temper.Orm.UpdateQuery.set(Temper.Orm.UpdateQuery.set(Temper.Orm.update(Temper.MarginaliaCore.id("folders")), Temper.MarginaliaCore.id("published_at"), Temper.Orm.SqlSource.new("date_trunc('second', now() at time zone 'utc')")), Temper.MarginaliaCore.id("slug"), Temper.Orm.SqlString.new(slug)), Temper.MarginaliaCore.id("updated_at"), Temper.Orm.SqlSource.new("date_trunc('second', now() at time zone 'utc')"))
        accumulator1 = Temper.Orm.SqlBuilder.new()
        Temper.Orm.SqlBuilder.appendSafe(accumulator1, "user_id = ")
        Temper.Orm.SqlBuilder.appendInt64(accumulator1, userId)
        t3 = Temper.Orm.UpdateQuery.where(t2, Temper.Orm.SqlBuilder.get_accumulated(accumulator1))
        accumulator2 = Temper.Orm.SqlBuilder.new()
        Temper.Orm.SqlBuilder.appendSafe(accumulator2, "id = ")
        Temper.Orm.SqlBuilder.appendInt64(accumulator2, folderId)
        t1 = Temper.Orm.UpdateQuery.toSql(Temper.Orm.UpdateQuery.where(t3, Temper.Orm.SqlBuilder.get_accumulated(accumulator2)))
        t1
      rescue
        _ in TemperCore.Bubble ->
          raise(TemperCore.Panic)
      end
      Temper.MarginaliaCore.returning(t1)
    end)
  end
  def unpublish(userId, folderId) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      _t1 = nil
      t1 = try do
        t2 = Temper.Orm.UpdateQuery.set(Temper.Orm.UpdateQuery.set(Temper.Orm.update(Temper.MarginaliaCore.id("folders")), Temper.MarginaliaCore.id("published_at"), Temper.Orm.SqlSource.new("NULL")), Temper.MarginaliaCore.id("updated_at"), Temper.Orm.SqlSource.new("date_trunc('second', now() at time zone 'utc')"))
        accumulator1 = Temper.Orm.SqlBuilder.new()
        Temper.Orm.SqlBuilder.appendSafe(accumulator1, "user_id = ")
        Temper.Orm.SqlBuilder.appendInt64(accumulator1, userId)
        t3 = Temper.Orm.UpdateQuery.where(t2, Temper.Orm.SqlBuilder.get_accumulated(accumulator1))
        accumulator2 = Temper.Orm.SqlBuilder.new()
        Temper.Orm.SqlBuilder.appendSafe(accumulator2, "id = ")
        Temper.Orm.SqlBuilder.appendInt64(accumulator2, folderId)
        t1 = Temper.Orm.UpdateQuery.toSql(Temper.Orm.UpdateQuery.where(t3, Temper.Orm.SqlBuilder.get_accumulated(accumulator2)))
        t1
      rescue
        _ in TemperCore.Bubble ->
          raise(TemperCore.Panic)
      end
      Temper.MarginaliaCore.returning(t1)
    end)
  end
  def publishedBySlug(slug) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      t = Temper.Orm.Query.select(Temper.Orm.from(Temper.MarginaliaCore.id("folders")), Temper.MarginaliaCore.columnIds())
      accumulator = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(accumulator, "slug = ")
      Temper.Orm.SqlBuilder.appendString(accumulator, slug)
      Temper.MarginaliaCore.statementOf(Temper.Orm.Query.toSql(Temper.Orm.Query.whereNotNull(Temper.Orm.Query.where(t, Temper.Orm.SqlBuilder.get_accumulated(accumulator)), Temper.MarginaliaCore.id("published_at"))))
    end)
  end
  def published() do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      Temper.MarginaliaCore.statementOf(Temper.Orm.Query.toSql(Temper.Orm.Query.orderBy(Temper.Orm.Query.whereNotNull(Temper.Orm.Query.select(Temper.Orm.from(Temper.MarginaliaCore.id("folders")), Temper.MarginaliaCore.columnIds()), Temper.MarginaliaCore.id("published_at")), Temper.MarginaliaCore.id("published_at"), false)))
    end)
  end
  def slugTaken(slug) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      _t1 = nil
      t2 = Temper.Orm.Query.select(Temper.Orm.from(Temper.MarginaliaCore.id("folders")), %TemperCore.Vec{t: {Temper.MarginaliaCore.id("id")}})
      accumulator = Temper.Orm.SqlBuilder.new()
      Temper.Orm.SqlBuilder.appendSafe(accumulator, "slug = ")
      Temper.Orm.SqlBuilder.appendString(accumulator, slug)
      q = Temper.Orm.Query.where(t2, Temper.Orm.SqlBuilder.get_accumulated(accumulator))
      t1 = try do
        t1 = Temper.Orm.Query.limit(q, 1)
        t1
      rescue
        _ in TemperCore.Bubble ->
          raise(TemperCore.Panic)
      end
      Temper.MarginaliaCore.statementOf(Temper.Orm.Query.toSql(t1))
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
      ex_loop_1 = fn ex_loop_1, k, nonBlank ->
        if k < TemperCore.List.length(lines) do
          nonBlank = if not TemperCore.String.is_empty(Temper.MarginaliaCore.trim(TemperCore.List.get(lines, k))) do
            nonBlank = TemperCore.int32(nonBlank + 1)
            nonBlank
          else
            nonBlank
          end
          k = TemperCore.int32(k + 1)
          ex_loop_1.(ex_loop_1, k, nonBlank)
        else
          {k, nonBlank}
        end
      end
      {_k, nonBlank} = ex_loop_1.(ex_loop_1, k, nonBlank)
      gaps = 0
      i = TemperCore.String.begin()
      ex_loop_3 = fn ex_loop_3, gaps, i ->
        if TemperCore.String.has_index(text, i) do
          if Temper.MarginaliaCore.isRegexSpace(TemperCore.String.get(text, i)) do
            newlines = 0
            ex_loop_5 = fn ex_loop_5, i, newlines ->
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
                  ex_loop_5.(ex_loop_5, i, newlines)
                end
              else
                {i, newlines}
              end
            end
            {i, newlines} = ex_loop_5.(ex_loop_5, i, newlines)
            if newlines >= 2 do
              gaps = TemperCore.int32(gaps + 1)
              ex_loop_3.(ex_loop_3, gaps, i)
            else
              ex_loop_3.(ex_loop_3, gaps, i)
            end
          else
            i = TemperCore.String.next(text, i)
            ex_loop_3.(ex_loop_3, gaps, i)
          end
        else
          {gaps, i}
        end
      end
      {gaps, _i} = ex_loop_3.(ex_loop_3, gaps, i)
      if nonBlank >= 12 do
        gaps <= TemperCore.int32(div(nonBlank, 12))
      else
        false
      end
    end)
  end
  def isWordChar(cp) do
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
  def intactHyphens(text) do
    found = TemperCore.Map.builder()
    i = TemperCore.String.begin()
    ex_loop_1 = fn ex_loop_1, i ->
      if TemperCore.String.has_index(text, i) do
        if not Temper.MarginaliaCore.isWordChar(TemperCore.String.get(text, i)) do
          i = TemperCore.String.next(text, i)
          ex_loop_1.(ex_loop_1, i)
        else
          start = i
          ex_loop_3 = fn ex_loop_3, i ->
            if true do
              _t2 = nil
              t2 = if TemperCore.String.has_index(text, i) do
                t2 = Temper.MarginaliaCore.isWordChar(TemperCore.String.get(text, i))
                t2
              else
                t2 = false
                t2
              end
              if not t2 do
                i
              else
                i = TemperCore.String.next(text, i)
                ex_loop_3.(ex_loop_3, i)
              end
            else
              i
            end
          end
          i = ex_loop_3.(ex_loop_3, i)
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
              t3 = Temper.MarginaliaCore.isWordChar(TemperCore.String.get(text, after_))
              t3
            else
              t3 = false
              t3
            end
            if t3 do
              e = after_
              ex_loop_5 = fn ex_loop_5, e ->
                if true do
                  _t4 = nil
                  t4 = if TemperCore.String.has_index(text, e) do
                    t4 = Temper.MarginaliaCore.isWordChar(TemperCore.String.get(text, e))
                    t4
                  else
                    t4 = false
                    t4
                  end
                  if not t4 do
                    e
                  else
                    e = TemperCore.String.next(text, e)
                    ex_loop_5.(ex_loop_5, e)
                  end
                else
                  e
                end
              end
              e = ex_loop_5.(ex_loop_5, e)
              TemperCore.Map.set(found, Temper.MarginaliaCore.downcase(TemperCore.String.slice(text, start, e)), true)
              i = e
              ex_loop_1.(ex_loop_1, i)
            else
              ex_loop_1.(ex_loop_1, i)
            end
          else
            ex_loop_1.(ex_loop_1, i)
          end
        end
      else
        i
      end
    end
    _i = ex_loop_1.(ex_loop_1, i)
    found
  end
  def normalizeNewlines(text) do
    Temper.MarginaliaCore.joinWith(TemperCore.String.split(text, "\r\n"), "\n")
  end
  def isJudgeLine(line) do
    try do
      _return = nil
      return = if true do
        i = TemperCore.String.begin()
        names = 0
        ex_loop_2 = fn ex_loop_2, i, names ->
          if true do
            j = i
            caps = 0
            ex_loop_4 = fn ex_loop_4, caps, j ->
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
                  ex_loop_4.(ex_loop_4, caps, j)
                end
              else
                {caps, j}
              end
            end
            {caps, j} = ex_loop_4.(ex_loop_4, caps, j)
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
                ex_loop_2.(ex_loop_2, i, names)
              end
            end
          else
            {i, names}
          end
        end
        {i, names} = ex_loop_2.(ex_loop_2, i, names)
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
            ex_loop_6 = fn ex_loop_6, k, spaces ->
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
                  ex_loop_6.(ex_loop_6, k, spaces)
                end
              else
                {k, spaces}
              end
            end
            {k, spaces} = ex_loop_6.(ex_loop_6, k, spaces)
            word = TemperCore.String.slice(tail, k, TemperCore.String.end_of(tail))
            if spaces >= 1 do
              if Temper.MarginaliaCore.startsWith(word, "concurring") do
                throw({:temper_return, :ex_return_0, true})
              else
                throw({:temper_return, :ex_return_0, Temper.MarginaliaCore.startsWith(word, "dissenting")})
              end
            else
              throw({:temper_return, :ex_return_0, false})
            end
          end
        end
      end
      return
    catch
      {:temper_return, :ex_return_0, ex_value_8} ->
        ex_value_8
    end
  end
  def allAsciiDigits(s, from, to) do
    try do
      return = nil
      return = try do
        i = from
        ex_loop_2 = fn ex_loop_2, i, return ->
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
              throw({:temper_break, :ex_block_1, return})
            else
              i = TemperCore.String.next(s, i)
              ex_loop_2.(ex_loop_2, i, return)
            end
          else
            {i, return}
          end
        end
        {_i, _return} = ex_loop_2.(ex_loop_2, i, return)
        throw({:temper_return, :ex_return_0, true})
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
  def isPageNumber(line) do
    n = TemperCore.String.count_between(line, TemperCore.String.begin(), TemperCore.String.end_of(line))
    if n >= 1 do
      if n <= 3 do
        Temper.MarginaliaCore.allAsciiDigits(line, TemperCore.String.begin(), TemperCore.String.end_of(line))
      else
        false
      end
    else
      false
    end
  end
  def withoutPageNumbers(line) do
    s = line
    i = TemperCore.String.begin()
    digits = 0
    ex_loop_1 = fn ex_loop_1, digits, i ->
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
          ex_loop_1.(ex_loop_1, digits, i)
        end
      else
        {digits, i}
      end
    end
    {digits, i} = ex_loop_1.(ex_loop_1, digits, i)
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
      ex_loop_3 = fn ex_loop_3, i ->
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
            ex_loop_3.(ex_loop_3, i)
          end
        else
          i
        end
      end
      i = ex_loop_3.(ex_loop_3, i)
      s = TemperCore.String.slice(s, i, TemperCore.String.end_of(s))
      {i, s}
    else
      {i, s}
    end
    e = TemperCore.String.end_of(s)
    tailDigits = 0
    ex_loop_5 = fn ex_loop_5, e, tailDigits ->
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
          ex_loop_5.(ex_loop_5, e, tailDigits)
        end
      else
        {e, tailDigits}
      end
    end
    {e, tailDigits} = ex_loop_5.(ex_loop_5, e, tailDigits)
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
      ex_loop_7 = fn ex_loop_7, e ->
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
            ex_loop_7.(ex_loop_7, e)
          end
        else
          e
        end
      end
      e = ex_loop_7.(ex_loop_7, e)
      s = TemperCore.String.slice(s, TemperCore.String.begin(), e)
      {e, s}
    else
      {e, s}
    end
    s
  end
  def isCaption(line) do
    try do
      _return = nil
      return = if true do
        body = Temper.MarginaliaCore.withoutPageNumbers(line)
        letters = 0
        upper = 0
        i = TemperCore.String.begin()
        ex_loop_2 = fn ex_loop_2, i, letters, upper ->
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
            ex_loop_2.(ex_loop_2, i, letters, upper)
          else
            {i, letters, upper}
          end
        end
        {_i, letters, upper} = ex_loop_2.(ex_loop_2, i, letters, upper)
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
          throw({:temper_return, :ex_return_0, TemperCore.Float.ge(ratio, 0.75)})
        end
      end
      return
    catch
      {:temper_return, :ex_return_0, ex_value_4} ->
        ex_value_4
    end
  end
  def isFurniture(line) do
    cond do
      Temper.MarginaliaCore.startsWith(line, "Cite as:") ->
        true
      line == "Opinion of the Court" ->
        true
      line == "Syllabus" ->
        true
      line == "Per Curiam" ->
        true
      Temper.MarginaliaCore.isJudgeLine(line) ->
        true
      Temper.MarginaliaCore.isPageNumber(line) ->
        true
      true ->
        Temper.MarginaliaCore.isCaption(line)
    end
  end
  def contains(chars, cp) do
    try do
      return = nil
      return = try do
        i = TemperCore.String.begin()
        ex_loop_2 = fn ex_loop_2, i, return ->
          if TemperCore.String.has_index(chars, i) do
            if TemperCore.String.get(chars, i) == cp do
              return = true
              throw({:temper_break, :ex_block_1, return})
            else
              i = TemperCore.String.next(chars, i)
              ex_loop_2.(ex_loop_2, i, return)
            end
          else
            {i, return}
          end
        end
        {_i, _return} = ex_loop_2.(ex_loop_2, i, return)
        throw({:temper_return, :ex_return_0, false})
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
  def allIn(s, chars) do
    try do
      return = nil
      return = try do
        i = TemperCore.String.begin()
        ex_loop_2 = fn ex_loop_2, i, return ->
          if TemperCore.String.has_index(s, i) do
            if not Temper.MarginaliaCore.contains(chars, TemperCore.String.get(s, i)) do
              return = false
              throw({:temper_break, :ex_block_1, return})
            else
              i = TemperCore.String.next(s, i)
              ex_loop_2.(ex_loop_2, i, return)
            end
          else
            {i, return}
          end
        end
        {_i, _return} = ex_loop_2.(ex_loop_2, i, return)
        throw({:temper_return, :ex_return_0, true})
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
  def isHeading(line) do
    try do
      return = nil
      return = try do
        i = TemperCore.String.begin()
        hashes = 0
        ex_loop_2 = fn ex_loop_2, hashes, i ->
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
              ex_loop_2.(ex_loop_2, hashes, i)
            end
          else
            {hashes, i}
          end
        end
        {hashes, i} = ex_loop_2.(ex_loop_2, hashes, i)
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
          ex_loop_4 = fn ex_loop_4, i ->
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
                ex_loop_4.(ex_loop_4, i)
              end
            else
              i
            end
          end
          i = ex_loop_4.(ex_loop_4, i)
          if TemperCore.String.has_index(line, i) do
            return = true
            throw({:temper_break, :ex_block_1, return})
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
            t2 = Temper.MarginaliaCore.allIn(line, "IVXL")
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
              throw({:temper_return, :ex_return_0, TemperCore.String.get(line, TemperCore.String.begin()) <= 90})
            else
              throw({:temper_return, :ex_return_0, false})
            end
          true ->
            throw({:temper_return, :ex_return_0, false})
        end
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
  def chunkParagraphs(lines, measure) do
    done = TemperCore.List.builder()
    current = TemperCore.List.builder()
    k = 0
    ex_loop_1 = fn ex_loop_1, k ->
      if k < TemperCore.List.length(lines) do
        line = TemperCore.List.get(lines, k)
        cond do
          Temper.MarginaliaCore.isHeading(line) ->
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
        ex_loop_1.(ex_loop_1, k)
      else
        k
      end
    end
    _k = ex_loop_1.(ex_loop_1, k)
    TemperCore.List.add(done, TemperCore.List.to_list(current))
    fn_ = fn p ->
      not TemperCore.List.is_empty(p)
    end
    TemperCore.List.filter(TemperCore.List.to_list(done), fn_)
  end
  def measure(lines) do
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
          throw({:temper_return, :ex_return_0, TemperCore.List.get(lengths, TemperCore.int32(div(TemperCore.int32(TemperCore.List.length(lengths) * 2), 3)))})
        end
      end
      return
    catch
      {:temper_return, :ex_return_0, ex_value_4} ->
        ex_value_4
    end
  end
  def endsWithAt(s, end_, suffix) do
    try do
      return = nil
      return = try do
        i = end_
        j = TemperCore.String.end_of(suffix)
        ex_loop_2 = fn ex_loop_2, i, j, return ->
          if j > TemperCore.String.begin() do
            if i <= TemperCore.String.begin() do
              return = false
              throw({:temper_break, :ex_block_1, return})
            else
              i = TemperCore.String.prev(s, i)
              j = TemperCore.String.prev(suffix, j)
              if TemperCore.String.get(s, i) != TemperCore.String.get(suffix, j) do
                return = false
                throw({:temper_break, :ex_block_1, return})
              else
                ex_loop_2.(ex_loop_2, i, j, return)
              end
            end
          else
            {i, j, return}
          end
        end
        {_i, _j, _return} = ex_loop_2.(ex_loop_2, i, j, return)
        throw({:temper_return, :ex_return_0, true})
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
  def withoutTrailingHyphens(s) do
    e = TemperCore.String.end_of(s)
    ex_loop_1 = fn ex_loop_1, e ->
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
          ex_loop_1.(ex_loop_1, e)
        end
      else
        e
      end
    end
    e = ex_loop_1.(ex_loop_1, e)
    TemperCore.String.slice(s, TemperCore.String.begin(), e)
  end
  def lastAsciiSpaceField(s) do
    b = TemperCore.String.end_of(s)
    ex_loop_1 = fn ex_loop_1, b ->
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
          ex_loop_1.(ex_loop_1, b)
        end
      else
        b
      end
    end
    b = ex_loop_1.(ex_loop_1, b)
    TemperCore.String.slice(s, b, TemperCore.String.end_of(s))
  end
  def firstAsciiSpaceField(s) do
    e = TemperCore.String.begin()
    ex_loop_1 = fn ex_loop_1, e ->
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
          ex_loop_1.(ex_loop_1, e)
        end
      else
        e
      end
    end
    e = ex_loop_1.(ex_loop_1, e)
    TemperCore.String.slice(s, TemperCore.String.begin(), e)
  end
  def stripTrailingPunct(word) do
    e = TemperCore.String.end_of(word)
    ex_loop_1 = fn ex_loop_1, e ->
      if true do
        _t = nil
        t = if e > TemperCore.String.begin() do
          if not Temper.MarginaliaCore.isWordChar(TemperCore.String.get(word, TemperCore.String.prev(word, e))) do
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
          ex_loop_1.(ex_loop_1, e)
        end
      else
        e
      end
    end
    e = ex_loop_1.(ex_loop_1, e)
    TemperCore.String.slice(word, TemperCore.String.begin(), e)
  end
  def mend(acc, line, keep) do
    unhyphened = Temper.MarginaliaCore.withoutTrailingHyphens(acc)
    stem = Temper.MarginaliaCore.lastAsciiSpaceField(unhyphened)
    head = Temper.MarginaliaCore.firstAsciiSpaceField(line)
    word = Temper.MarginaliaCore.downcase(stem <> "-" <> Temper.MarginaliaCore.stripTrailingPunct(head))
    if TemperCore.Map.has(keep, word) do
      acc <> line
    else
      unhyphened <> line
    end
  end
  def join(lines, keep) do
    acc = ""
    k = 0
    ex_loop_1 = fn ex_loop_1, acc, k ->
      if k < TemperCore.List.length(lines) do
        line = TemperCore.List.get(lines, k)
        acc = cond do
          TemperCore.String.is_empty(acc) ->
            acc = line
            acc
          Temper.MarginaliaCore.endsWithAt(acc, TemperCore.String.end_of(acc), "-") ->
            acc = Temper.MarginaliaCore.mend(acc, line, keep)
            acc
          true ->
            acc = acc <> " " <> line
            acc
        end
        k = TemperCore.int32(k + 1)
        ex_loop_1.(ex_loop_1, acc, k)
      else
        {acc, k}
      end
    end
    {acc, _k} = ex_loop_1.(ex_loop_1, acc, k)
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
            keep = Temper.MarginaliaCore.intactHyphens(text)
            raw = TemperCore.String.split(Temper.MarginaliaCore.normalizeNewlines(text), "\n")
            lines = TemperCore.List.builder()
            k1 = 0
            ex_loop_2 = fn ex_loop_2, k1 ->
              if k1 < TemperCore.List.length(raw) do
                line = Temper.MarginaliaCore.trim(TemperCore.List.get(raw, k1))
                _t = nil
                t = if not Temper.MarginaliaCore.isFurniture(line) do
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
                ex_loop_2.(ex_loop_2, k1)
              else
                k1
              end
            end
            _k1 = ex_loop_2.(ex_loop_2, k1)
            all = TemperCore.List.to_list(lines)
            paragraphs = Temper.MarginaliaCore.chunkParagraphs(all, Temper.MarginaliaCore.measure(all))
            out = TemperCore.List.builder()
            k2 = 0
            ex_loop_4 = fn ex_loop_4, k2 ->
              if k2 < TemperCore.List.length(paragraphs) do
                p = Temper.MarginaliaCore.join(TemperCore.List.get(paragraphs, k2), keep)
                if not TemperCore.String.is_empty(p) do
                  TemperCore.List.add(out, p)
                  nil
                else
                  nil
                end
                k2 = TemperCore.int32(k2 + 1)
                ex_loop_4.(ex_loop_4, k2)
              else
                k2
              end
            end
            _k2 = ex_loop_4.(ex_loop_4, k2)
            throw({:temper_return, :ex_return_0, Temper.MarginaliaCore.joinWith(TemperCore.List.to_list(out), "\n\n")})
          end
        end
        return
      catch
        {:temper_return, :ex_return_0, ex_value_6} ->
          ex_value_6
      end
    end)
  end
  def align(quote_, source) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      raw = TemperCore.String.split(Temper.MarginaliaCore.normalizeNewlines(quote_), "\n")
      lines = TemperCore.List.builder()
      k = 0
      ex_loop_1 = fn ex_loop_1, k ->
        if k < TemperCore.List.length(raw) do
          line = Temper.MarginaliaCore.trim(TemperCore.List.get(raw, k))
          if not TemperCore.String.is_empty(line) do
            TemperCore.List.add(lines, line)
            nil
          else
            nil
          end
          k = TemperCore.int32(k + 1)
          ex_loop_1.(ex_loop_1, k)
        else
          k
        end
      end
      _k = ex_loop_1.(ex_loop_1, k)
      Temper.MarginaliaCore.join(TemperCore.List.to_list(lines), Temper.MarginaliaCore.intactHyphens(source))
    end)
  end
  def graphemePrefix(s, n) do
    TemperConnected.graphemePrefix(s, n)
  end
  def normalize(raw) do
    unixed = Temper.MarginaliaCore.joinWith(TemperCore.String.split(Temper.MarginaliaCore.joinWith(TemperCore.String.split(raw, "\r\n"), "\n"), "\r"), "\n")
    out = TemperCore.StringBuilder.new()
    newlines = 0
    runStart = TemperCore.String.begin()
    i = TemperCore.String.begin()
    ex_loop_1 = fn ex_loop_1, i, newlines, runStart ->
      if TemperCore.String.has_index(unixed, i) do
        {newlines, runStart} = cond do
          TemperCore.String.get(unixed, i) == 10 ->
            if newlines == 0 do
              TemperCore.StringBuilder.append_between(out, unixed, runStart, i)
              nil
            else
              nil
            end
            newlines = TemperCore.int32(newlines + 1)
            {newlines, runStart}
          newlines > 0 ->
            if newlines >= 3 do
              TemperCore.StringBuilder.append(out, "\n\n")
              nil
            else
              k2 = 0
              ex_loop_3 = fn ex_loop_3, k2 ->
                if k2 < newlines do
                  TemperCore.StringBuilder.append(out, "\n")
                  k2 = TemperCore.int32(k2 + 1)
                  ex_loop_3.(ex_loop_3, k2)
                else
                  k2
                end
              end
              _k2 = ex_loop_3.(ex_loop_3, k2)
              nil
            end
            newlines = 0
            runStart = i
            {newlines, runStart}
          true ->
            {newlines, runStart}
        end
        i = TemperCore.String.next(unixed, i)
        ex_loop_1.(ex_loop_1, i, newlines, runStart)
      else
        {i, newlines, runStart}
      end
    end
    {_i, newlines, runStart} = ex_loop_1.(ex_loop_1, i, newlines, runStart)
    if newlines == 0 do
      TemperCore.StringBuilder.append_between(out, unixed, runStart, TemperCore.String.end_of(unixed))
      nil
    else
      nil
    end
    if newlines >= 3 do
      TemperCore.StringBuilder.append(out, "\n\n")
      nil
    else
      k1 = 0
      ex_loop_5 = fn ex_loop_5, k1 ->
        if k1 < newlines do
          TemperCore.StringBuilder.append(out, "\n")
          k1 = TemperCore.int32(k1 + 1)
          ex_loop_5.(ex_loop_5, k1)
        else
          k1
        end
      end
      _k1 = ex_loop_5.(ex_loop_5, k1)
      nil
    end
    Temper.MarginaliaCore.trim(TemperCore.StringBuilder.to_string(out))
  end
  def isMarkdownHead(line) do
    try do
      _return = nil
      return = if true do
        i = TemperCore.String.begin()
        hashes = 0
        ex_loop_2 = fn ex_loop_2, hashes, i ->
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
              ex_loop_2.(ex_loop_2, hashes, i)
            end
          else
            {hashes, i}
          end
        end
        {hashes, i} = ex_loop_2.(ex_loop_2, hashes, i)
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
            t1 = not Temper.MarginaliaCore.isRegexSpace(TemperCore.String.get(line, i))
            t1
        end
        if t1 do
          return = false
          return
        else
          ex_loop_4 = fn ex_loop_4, i ->
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
                ex_loop_4.(ex_loop_4, i)
              end
            else
              i
            end
          end
          i = ex_loop_4.(ex_loop_4, i)
          throw({:temper_return, :ex_return_0, TemperCore.String.has_index(line, i)})
        end
      end
      return
    catch
      {:temper_return, :ex_return_0, ex_value_6} ->
        ex_value_6
    end
  end
  def wordCount(s) do
    n = 0
    inWord = false
    i = TemperCore.String.begin()
    ex_loop_1 = fn ex_loop_1, i, inWord, n ->
      if TemperCore.String.has_index(s, i) do
        {inWord, n} = if Temper.MarginaliaCore.isRegexSpace(TemperCore.String.get(s, i)) do
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
        ex_loop_1.(ex_loop_1, i, inWord, n)
      else
        {i, inWord, n}
      end
    end
    {_i, _inWord, n} = ex_loop_1.(ex_loop_1, i, inWord, n)
    n
  end
  def paragraphPieces(text) do
    out = TemperCore.List.builder()
    start = TemperCore.String.begin()
    i = TemperCore.String.begin()
    ex_loop_1 = fn ex_loop_1, i, start ->
      if TemperCore.String.has_index(text, i) do
        if Temper.MarginaliaCore.isRegexSpace(TemperCore.String.get(text, i)) do
          runStart = i
          newlines = 0
          lastNewline = i
          ex_loop_3 = fn ex_loop_3, i, lastNewline, newlines ->
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
                ex_loop_3.(ex_loop_3, i, lastNewline, newlines)
              end
            else
              {i, lastNewline, newlines}
            end
          end
          {i, lastNewline, newlines} = ex_loop_3.(ex_loop_3, i, lastNewline, newlines)
          if newlines >= 2 do
            firstNewline = runStart
            ex_loop_5 = fn ex_loop_5, firstNewline ->
              if TemperCore.String.get(text, firstNewline) != 10 do
                firstNewline = TemperCore.String.next(text, firstNewline)
                ex_loop_5.(ex_loop_5, firstNewline)
              else
                firstNewline
              end
            end
            firstNewline = ex_loop_5.(ex_loop_5, firstNewline)
            piece = TemperCore.String.slice(text, start, firstNewline)
            if not TemperCore.String.is_empty(piece) do
              TemperCore.List.add(out, piece)
              nil
            else
              nil
            end
            start = TemperCore.String.next(text, lastNewline)
            ex_loop_1.(ex_loop_1, i, start)
          else
            ex_loop_1.(ex_loop_1, i, start)
          end
        else
          i = TemperCore.String.next(text, i)
          ex_loop_1.(ex_loop_1, i, start)
        end
      else
        {i, start}
      end
    end
    {_i, start} = ex_loop_1.(ex_loop_1, i, start)
    last = TemperCore.String.slice(text, start, TemperCore.String.end_of(text))
    if not TemperCore.String.is_empty(last) do
      TemperCore.List.add(out, last)
      nil
    else
      nil
    end
    TemperCore.List.to_list(out)
  end
  def window(text) do
    pieces = Temper.MarginaliaCore.paragraphPieces(text)
    windows = TemperCore.List.builder()
    k = 0
    ex_loop_1 = fn ex_loop_1, k ->
      if k < TemperCore.List.length(pieces) do
        para = Temper.MarginaliaCore.trim(TemperCore.List.get(pieces, k))
        words = Temper.MarginaliaCore.wordCount(para)
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
        ex_loop_1.(ex_loop_1, k)
      else
        k
      end
    end
    _k = ex_loop_1.(ex_loop_1, k)
    fn_ = fn w ->
      Temper.MarginaliaCore.joinWith(TemperCore.List.to_list(Temper.MarginaliaCore.Window.get_paras(w)), "\n\n")
    end
    TemperCore.List.map(TemperCore.List.to_list(windows), fn_)
  end
  def subdivide(chunk) do
    try do
      _return = nil
      return = if true do
        if Temper.MarginaliaCore.wordCount(Temper.MarginaliaCore.Section.get_body(chunk)) <= 4000 do
          return = %TemperCore.Vec{t: {chunk}}
          return
        else
          parts = Temper.MarginaliaCore.window(Temper.MarginaliaCore.Section.get_body(chunk))
          n = TemperCore.List.length(parts)
          if n < 2 do
            return = %TemperCore.Vec{t: {chunk}}
            return
          else
            out = TemperCore.List.builder()
            k = 0
            ex_loop_2 = fn ex_loop_2, k ->
              if k < n do
                TemperCore.List.add(out, Temper.MarginaliaCore.Section.new(Temper.MarginaliaCore.Section.get_title(chunk) <> " (" <> TemperCore.int_to_string(TemperCore.int32(k + 1)) <> "/" <> TemperCore.int_to_string(n) <> ")", TemperCore.List.get(parts, k)))
                k = TemperCore.int32(k + 1)
                ex_loop_2.(ex_loop_2, k)
              else
                k
              end
            end
            _k = ex_loop_2.(ex_loop_2, k)
            throw({:temper_return, :ex_return_0, TemperCore.List.to_list(out)})
          end
        end
      end
      return
    catch
      {:temper_return, :ex_return_0, ex_value_4} ->
        ex_value_4
    end
  end
  def finish(chunks) do
    kept = TemperCore.List.builder()
    k1 = 0
    ex_loop_1 = fn ex_loop_1, k1 ->
      if k1 < TemperCore.List.length(chunks) do
        if true do
          chunk = TemperCore.List.get(chunks, k1)
          if TemperCore.String.is_empty(Temper.MarginaliaCore.trim(Temper.MarginaliaCore.Section.get_body(chunk))) do
            nil
          else
            n = TemperCore.List.length(kept)
            _t = nil
            t = if n > 0 do
              if Temper.MarginaliaCore.wordCount(Temper.MarginaliaCore.Section.get_body(chunk)) < 250 do
                t = Temper.MarginaliaCore.wordCount(Temper.MarginaliaCore.Section.get_body(TemperCore.List.get(kept, TemperCore.int32(n - 1)))) < 1800
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
        ex_loop_1.(ex_loop_1, k1)
      else
        k1
      end
    end
    _k1 = ex_loop_1.(ex_loop_1, k1)
    out = TemperCore.List.builder()
    all = TemperCore.List.to_list(kept)
    k2 = 0
    ex_loop_4 = fn ex_loop_4, k2 ->
      if k2 < TemperCore.List.length(all) do
        TemperCore.List.add_all(out, Temper.MarginaliaCore.subdivide(TemperCore.List.get(all, k2)))
        k2 = TemperCore.int32(k2 + 1)
        ex_loop_4.(ex_loop_4, k2)
      else
        k2
      end
    end
    _k2 = ex_loop_4.(ex_loop_4, k2)
    if TemperCore.List.is_empty(out) do
      nil
    else
      TemperCore.List.to_list(out)
    end
  end
  def asciiCaselessPrefix(line, at, word) do
    try do
      return = nil
      return = try do
        i = at
        j = TemperCore.String.begin()
        ex_loop_2 = fn ex_loop_2, i, j, return ->
          if TemperCore.String.has_index(word, j) do
            if not TemperCore.String.has_index(line, i) do
              return = nil
              throw({:temper_break, :ex_block_1, return})
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
                throw({:temper_break, :ex_block_1, return})
              else
                i = TemperCore.String.next(line, i)
                j = TemperCore.String.next(word, j)
                ex_loop_2.(ex_loop_2, i, j, return)
              end
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
  def isAsciiLetter(cp) do
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
  def isRomanLetter(cp) do
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
  def markerHead(line, at) do
    try do
      return = nil
      return = try do
        keywords = %TemperCore.Vec{t: {"chapter", "part", "book", "act", "section"}}
        k = 0
        ex_loop_2 = fn ex_loop_2, k, return ->
          if k < TemperCore.List.length(keywords) do
            after_1 = Temper.MarginaliaCore.asciiCaselessPrefix(line, at, TemperCore.List.get(keywords, k))
            return = if not (after_1 === nil) do
              after_2 = after_1
              i = after_2
              spaces = 0
              ex_loop_4 = fn ex_loop_4, i, spaces ->
                if true do
                  _t8 = nil
                  t8 = if TemperCore.String.has_index(line, i) do
                    t8 = Temper.MarginaliaCore.isRegexSpace(TemperCore.String.get(line, i))
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
                    ex_loop_4.(ex_loop_4, i, spaces)
                  end
                else
                  {i, spaces}
                end
              end
              {i, spaces} = ex_loop_4.(ex_loop_4, i, spaces)
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
                    ex_loop_6 = fn ex_loop_6, i ->
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
                          ex_loop_6.(ex_loop_6, i)
                        end
                      else
                        i
                      end
                    end
                    i = ex_loop_6.(ex_loop_6, i)
                    return = i
                    throw({:temper_break, :ex_block_1, return})
                  Temper.MarginaliaCore.isAsciiLetter(cp) ->
                    ex_loop_8 = fn ex_loop_8, i ->
                      if true do
                        _t12 = nil
                        t12 = if TemperCore.String.has_index(line, i) do
                          t12 = Temper.MarginaliaCore.isAsciiLetter(TemperCore.String.get(line, i))
                          t12
                        else
                          t12 = false
                          t12
                        end
                        if not t12 do
                          i
                        else
                          i = TemperCore.String.next(line, i)
                          ex_loop_8.(ex_loop_8, i)
                        end
                      else
                        i
                      end
                    end
                    i = ex_loop_8.(ex_loop_8, i)
                    return = i
                    throw({:temper_break, :ex_block_1, return})
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
            ex_loop_2.(ex_loop_2, k, return)
          else
            {k, return}
          end
        end
        {_k, return} = ex_loop_2.(ex_loop_2, k, return)
        r = at
        romans = 0
        ex_loop_10 = fn ex_loop_10, r, romans ->
          if true do
            _t3 = nil
            t3 = if TemperCore.String.has_index(line, r) do
              t3 = Temper.MarginaliaCore.isRomanLetter(TemperCore.String.get(line, r))
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
              ex_loop_10.(ex_loop_10, r, romans)
            end
          else
            {r, romans}
          end
        end
        {r, romans} = ex_loop_10.(ex_loop_10, r, romans)
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
            ex_loop_12 = fn ex_loop_12, s, stars ->
              if stars < 3 do
                ex_loop_14 = fn ex_loop_14, s ->
                  if true do
                    _t10 = nil
                    t10 = if TemperCore.String.has_index(line, s) do
                      t10 = Temper.MarginaliaCore.isRegexSpace(TemperCore.String.get(line, s))
                      t10
                    else
                      t10 = false
                      t10
                    end
                    if not t10 do
                      s
                    else
                      s = TemperCore.String.next(line, s)
                      ex_loop_14.(ex_loop_14, s)
                    end
                  else
                    s
                  end
                end
                s = ex_loop_14.(ex_loop_14, s)
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
                  ex_loop_12.(ex_loop_12, s, stars)
                end
              else
                {s, stars}
              end
            end
            {s, stars} = ex_loop_12.(ex_loop_12, s, stars)
            if stars == 3 do
              return = s
              throw({:temper_break, :ex_block_1, return})
            else
              return
            end
          else
            return
          end
          m = at
          emDashes = 0
          ex_loop_16 = fn ex_loop_16, emDashes, m ->
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
                ex_loop_16.(ex_loop_16, emDashes, m)
              end
            else
              {emDashes, m}
            end
          end
          {emDashes, m} = ex_loop_16.(ex_loop_16, emDashes, m)
          if emDashes >= 3 do
            return = m
            return
          else
            d = at
            dashes = 0
            ex_loop_18 = fn ex_loop_18, d, dashes ->
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
                  ex_loop_18.(ex_loop_18, d, dashes)
                end
              else
                {d, dashes}
              end
            end
            {d, dashes} = ex_loop_18.(ex_loop_18, d, dashes)
            if dashes >= 3 do
              return = d
              return
            else
              throw({:temper_return, :ex_return_0, nil})
            end
          end
        end
      catch
        {:temper_break, :ex_block_1, ex_vars_20} ->
          ex_vars_20
      end
      return
    catch
      {:temper_return, :ex_return_0, ex_value_21} ->
        ex_value_21
    end
  end
  def utf8Length(s, from) do
    n = 0
    i = from
    ex_loop_1 = fn ex_loop_1, i, n ->
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
        ex_loop_1.(ex_loop_1, i, n)
      else
        {i, n}
      end
    end
    {_i, n} = ex_loop_1.(ex_loop_1, i, n)
    n
  end
  def isMarker(line) do
    try do
      _return = nil
      return = if true do
        _t1 = nil
        if Temper.MarginaliaCore.graphemeLength(Temper.MarginaliaCore.trim(line)) >= 90 do
          return = false
          return
        else
          i = TemperCore.String.begin()
          ex_loop_2 = fn ex_loop_2, i ->
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
                ex_loop_2.(ex_loop_2, i)
              end
            else
              i
            end
          end
          i = ex_loop_2.(ex_loop_2, i)
          head = Temper.MarginaliaCore.markerHead(line, i)
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
            ex_loop_4 = fn ex_loop_4, i ->
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
                  ex_loop_4.(ex_loop_4, i)
                end
              else
                i
              end
            end
            i = ex_loop_4.(ex_loop_4, i)
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
                ex_loop_6 = fn ex_loop_6, i ->
                  if true do
                    _t6 = nil
                    t6 = if TemperCore.String.has_index(line, i) do
                      t6 = Temper.MarginaliaCore.isRegexSpace(TemperCore.String.get(line, i))
                      t6
                    else
                      t6 = false
                      t6
                    end
                    if not t6 do
                      i
                    else
                      i = TemperCore.String.next(line, i)
                      ex_loop_6.(ex_loop_6, i)
                    end
                  else
                    i
                  end
                end
                i = ex_loop_6.(ex_loop_6, i)
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
            throw({:temper_return, :ex_return_0, TemperCore.int32(Temper.MarginaliaCore.utf8Length(line, i) - spare) <= 80})
          end
        end
      end
      return
    catch
      {:temper_return, :ex_return_0, ex_value_8} ->
        ex_value_8
    end
  end
  def markdownTitle(line) do
    i = TemperCore.String.begin()
    ex_loop_1 = fn ex_loop_1, i ->
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
          ex_loop_1.(ex_loop_1, i)
        end
      else
        i
      end
    end
    i = ex_loop_1.(ex_loop_1, i)
    ex_loop_3 = fn ex_loop_3, i ->
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
          ex_loop_3.(ex_loop_3, i)
        end
      else
        i
      end
    end
    i = ex_loop_3.(ex_loop_3, i)
    Temper.MarginaliaCore.trim(TemperCore.String.slice(line, i, TemperCore.String.end_of(line)))
  end
  def untitledIfBlank(title) do
    if TemperCore.String.is_empty(title) do
      "Untitled"
    else
      Temper.MarginaliaCore.graphemePrefix(title, 120)
    end
  end
  def chunkOn(lines, markdown) do
    chunks = TemperCore.List.builder()
    k = 0
    ex_loop_1 = fn ex_loop_1, k ->
      if k < TemperCore.List.length(lines) do
        line = TemperCore.List.get(lines, k)
        _isHead = nil
        isHead = if markdown do
          isHead = Temper.MarginaliaCore.isMarkdownHead(line)
          isHead
        else
          isHead = Temper.MarginaliaCore.isMarker(line)
          isHead
        end
        cond do
          isHead ->
            _title = nil
            title = if markdown do
              title = Temper.MarginaliaCore.markdownTitle(line)
              title
            else
              title = Temper.MarginaliaCore.trim(line)
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
        ex_loop_1.(ex_loop_1, k)
      else
        k
      end
    end
    _k = ex_loop_1.(ex_loop_1, k)
    fn_ = fn c ->
      Temper.MarginaliaCore.Section.new(Temper.MarginaliaCore.untitledIfBlank(Temper.MarginaliaCore.HeadChunk.get_title(c)), Temper.MarginaliaCore.trim(Temper.MarginaliaCore.joinWith(TemperCore.List.to_list(Temper.MarginaliaCore.HeadChunk.get_lines(c)), "\n")))
    end
    TemperCore.List.map(TemperCore.List.to_list(chunks), fn_)
  end
  def byMarkdown(text) do
    try do
      _return = nil
      return = if true do
        lines = TemperCore.String.split(text, "\n")
        fn_ = fn l ->
          Temper.MarginaliaCore.isMarkdownHead(l)
        end
        if TemperCore.List.length(TemperCore.List.filter(lines, fn_)) < 2 do
          return = nil
          return
        else
          throw({:temper_return, :ex_return_0, Temper.MarginaliaCore.finish(Temper.MarginaliaCore.chunkOn(lines, true))})
        end
      end
      return
    catch
      {:temper_return, :ex_return_0, ex_value_3} ->
        ex_value_3
    end
  end
  def byMarker(text) do
    try do
      _return = nil
      return = if true do
        lines = TemperCore.String.split(text, "\n")
        fn_ = fn l ->
          Temper.MarginaliaCore.isMarker(l)
        end
        if TemperCore.List.length(TemperCore.List.filter(lines, fn_)) < 2 do
          return = nil
          return
        else
          throw({:temper_return, :ex_return_0, Temper.MarginaliaCore.finish(Temper.MarginaliaCore.chunkOn(lines, false))})
        end
      end
      return
    catch
      {:temper_return, :ex_return_0, ex_value_3} ->
        ex_value_3
    end
  end
  def allOf(s, from, to, cp) do
    try do
      return = nil
      return = try do
        i = from
        ex_loop_2 = fn ex_loop_2, i, return ->
          if i < to do
            if TemperCore.String.get(s, i) != cp do
              return = false
              throw({:temper_break, :ex_block_1, return})
            else
              i = TemperCore.String.next(s, i)
              ex_loop_2.(ex_loop_2, i, return)
            end
          else
            {i, return}
          end
        end
        {_i, _return} = ex_loop_2.(ex_loop_2, i, return)
        throw({:temper_return, :ex_return_0, true})
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
  def isUnderline(s) do
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
            throw({:temper_return, :ex_return_0, Temper.MarginaliaCore.allOf(s, TemperCore.String.begin(), TemperCore.String.end_of(s), mark)})
          end
        end
      end
      return
    catch
      {:temper_return, :ex_return_0, ex_value_2} ->
        ex_value_2
    end
  end
  def delimiterCell(s, at) do
    try do
      _return = nil
      return = if true do
        i = at
        ex_loop_2 = fn ex_loop_2, i ->
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
              ex_loop_2.(ex_loop_2, i)
            end
          else
            i
          end
        end
        i = ex_loop_2.(ex_loop_2, i)
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
        ex_loop_4 = fn ex_loop_4, dashes, i ->
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
              ex_loop_4.(ex_loop_4, dashes, i)
            end
          else
            {dashes, i}
          end
        end
        {dashes, i} = ex_loop_4.(ex_loop_4, dashes, i)
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
          ex_loop_6 = fn ex_loop_6, i ->
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
                ex_loop_6.(ex_loop_6, i)
              end
            else
              i
            end
          end
          i = ex_loop_6.(ex_loop_6, i)
          throw({:temper_return, :ex_return_0, i})
        end
      end
      return
    catch
      {:temper_return, :ex_return_0, ex_value_8} ->
        ex_value_8
    end
  end
  def isTableDelimiter(s) do
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
      first = Temper.MarginaliaCore.delimiterCell(s, i)
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
        ex_loop_2 = fn ex_loop_2, i, return ->
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
                cell = Temper.MarginaliaCore.delimiterCell(s, after_)
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
                  ex_loop_2.(ex_loop_2, i, return)
                end
            end
          else
            {i, return}
          end
        end
        {_i, return} = ex_loop_2.(ex_loop_2, i, return)
        return
      end
    end
    return
  end
  def isAtxHeading(s) do
    i = TemperCore.String.begin()
    hashes = 0
    ex_loop_1 = fn ex_loop_1, hashes, i ->
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
          ex_loop_1.(ex_loop_1, hashes, i)
        end
      else
        {hashes, i}
      end
    end
    {hashes, i} = ex_loop_1.(ex_loop_1, hashes, i)
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
  def isIndentedCode(block) do
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
          ex_loop_2 = fn ex_loop_2, i, spaces ->
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
                ex_loop_2.(ex_loop_2, i, spaces)
              end
            else
              {i, spaces}
            end
          end
          {_i, spaces} = ex_loop_2.(ex_loop_2, i, spaces)
          throw({:temper_return, :ex_return_0, spaces >= 4})
        end
      end
      return
    catch
      {:temper_return, :ex_return_0, ex_value_4} ->
        ex_value_4
    end
  end
  def isListItem(s) do
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
            ex_loop_2 = fn ex_loop_2, digits, i ->
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
                  ex_loop_2.(ex_loop_2, digits, i)
                end
              else
                {digits, i}
              end
            end
            {digits, i} = ex_loop_2.(ex_loop_2, digits, i)
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
                throw({:temper_return, :ex_return_0, Temper.MarginaliaCore.isRegexSpace(TemperCore.String.get(s, next))})
              else
                throw({:temper_return, :ex_return_0, false})
              end
            end
          end
        end
      end
      return
    catch
      {:temper_return, :ex_return_0, ex_value_4} ->
        ex_value_4
    end
  end
  def isHtml(s) do
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
              throw({:temper_return, :ex_return_0, true})
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
                  throw({:temper_return, :ex_return_0, true})
                c == 33 ->
                  throw({:temper_return, :ex_return_0, true})
                true ->
                  throw({:temper_return, :ex_return_0, c == 47})
              end
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
  def isLoneLinkOrImage(block) do
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
          ex_loop_2 = fn ex_loop_2, i ->
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
                ex_loop_2.(ex_loop_2, i)
              end
            else
              i
            end
          end
          i = ex_loop_2.(ex_loop_2, i)
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
              ex_loop_4 = fn ex_loop_4, i ->
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
                    ex_loop_4.(ex_loop_4, i)
                  end
                else
                  i
                end
              end
              i = ex_loop_4.(ex_loop_4, i)
              if not TemperCore.String.has_index(block, i) do
                return = false
                return
              else
                i = TemperCore.String.next(block, i)
                ex_loop_6 = fn ex_loop_6, i ->
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
                      ex_loop_6.(ex_loop_6, i)
                    end
                  else
                    i
                  end
                end
                i = ex_loop_6.(ex_loop_6, i)
                throw({:temper_return, :ex_return_0, not TemperCore.String.has_index(block, i)})
              end
            end
          end
        end
      end
      return
    catch
      {:temper_return, :ex_return_0, ex_value_8} ->
        ex_value_8
    end
  end
  def isRule(s) do
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
            ex_loop_2 = fn ex_loop_2, count, i ->
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
                  ex_loop_2.(ex_loop_2, count, i)
                end
              else
                {count, i}
              end
            end
            {count, i} = ex_loop_2.(ex_loop_2, count, i)
            ex_loop_4 = fn ex_loop_4, i ->
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
                  ex_loop_4.(ex_loop_4, i)
                end
              else
                i
              end
            end
            i = ex_loop_4.(ex_loop_4, i)
            if count >= 3 do
              throw({:temper_return, :ex_return_0, not TemperCore.String.has_index(s, i)})
            else
              throw({:temper_return, :ex_return_0, false})
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
  def isProse(block) do
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
          Temper.MarginaliaCore.isUnderline(second) ->
            return = false
            return
          Temper.MarginaliaCore.isTableDelimiter(second) ->
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
              Temper.MarginaliaCore.isAtxHeading(first) ->
                return = false
                return
              Temper.MarginaliaCore.isIndentedCode(block) ->
                return = false
                return
              Temper.MarginaliaCore.isListItem(first) ->
                return = false
                return
              Temper.MarginaliaCore.isHtml(first) ->
                return = false
                return
              Temper.MarginaliaCore.isLoneLinkOrImage(block) ->
                return = false
                return
              Temper.MarginaliaCore.isRule(first) ->
                return = false
                return
              true ->
                allPiped = true
                k = 0
                ex_loop_2 = fn ex_loop_2, allPiped, k ->
                  if k < TemperCore.List.length(lines) do
                    allPiped = if not Temper.MarginaliaCore.startsWith(Temper.MarginaliaCore.trimLeading(TemperCore.List.get(lines, k)), "|") do
                      allPiped = false
                      allPiped
                    else
                      allPiped
                    end
                    k = TemperCore.int32(k + 1)
                    ex_loop_2.(ex_loop_2, allPiped, k)
                  else
                    {allPiped, k}
                  end
                end
                {allPiped, _k} = ex_loop_2.(ex_loop_2, allPiped, k)
                throw({:temper_return, :ex_return_0, not allPiped})
            end
        end
      end
      return
    catch
      {:temper_return, :ex_return_0, ex_value_4} ->
        ex_value_4
    end
  end
  def isQuoted(block) do
    i = TemperCore.String.begin()
    ex_loop_1 = fn ex_loop_1, i ->
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
          ex_loop_1.(ex_loop_1, i)
        end
      else
        i
      end
    end
    i = ex_loop_1.(ex_loop_1, i)
    if TemperCore.String.has_index(block, i) do
      TemperCore.String.get(block, i) == 62
    else
      false
    end
  end
  def stripQuoteMark(line) do
    try do
      _return = nil
      return = if true do
        i = TemperCore.String.begin()
        ex_loop_2 = fn ex_loop_2, i ->
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
              ex_loop_2.(ex_loop_2, i)
            end
          else
            i
          end
        end
        i = ex_loop_2.(ex_loop_2, i)
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
          throw({:temper_return, :ex_return_0, TemperCore.String.slice(line, i, TemperCore.String.end_of(line))})
        end
      end
      return
    catch
      {:temper_return, :ex_return_0, ex_value_4} ->
        ex_value_4
    end
  end
  def reflowQuote(block) do
    lines = TemperCore.String.split(block, "\n")
    fn_1 = fn l1 ->
      Temper.MarginaliaCore.stripQuoteMark(l1)
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
  def isCloser(cp) do
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
  def isOpener(cp) do
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
  def breakSentences(text) do
    out = TemperCore.StringBuilder.new()
    runStart = TemperCore.String.begin()
    i = TemperCore.String.begin()
    ex_loop_1 = fn ex_loop_1, i, runStart ->
      if TemperCore.String.has_index(text, i) do
        ex_step_15 = try do
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
          {i, runStart} = if t1 do
            j = TemperCore.String.next(text, i)
            ex_loop_9 = fn ex_loop_9, j ->
              if true do
                _t3 = nil
                t3 = if TemperCore.String.has_index(text, j) do
                  t3 = Temper.MarginaliaCore.isCloser(TemperCore.String.get(text, j))
                  t3
                else
                  t3 = false
                  t3
                end
                if not t3 do
                  j
                else
                  j = TemperCore.String.next(text, j)
                  ex_loop_9.(ex_loop_9, j)
                end
              else
                j
              end
            end
            j = ex_loop_9.(ex_loop_9, j)
            k = j
            ex_loop_11 = fn ex_loop_11, k ->
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
                  ex_loop_11.(ex_loop_11, k)
                end
              else
                k
              end
            end
            k = ex_loop_11.(ex_loop_11, k)
            m = k
            ex_loop_13 = fn ex_loop_13, m ->
              if true do
                _t5 = nil
                t5 = if TemperCore.String.has_index(text, m) do
                  t5 = Temper.MarginaliaCore.isOpener(TemperCore.String.get(text, m))
                  t5
                else
                  t5 = false
                  t5
                end
                if not t5 do
                  m
                else
                  m = TemperCore.String.next(text, m)
                  ex_loop_13.(ex_loop_13, m)
                end
              else
                m
              end
            end
            m = ex_loop_13.(ex_loop_13, m)
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
              TemperCore.StringBuilder.append_between(out, text, runStart, j)
              TemperCore.StringBuilder.append(out, "\n")
              i = k
              runStart = k
              throw({:temper_continue, :ex_loop_2, {i, runStart}})
            else
              {i, runStart}
            end
          else
            {i, runStart}
          end
          i = TemperCore.String.next(text, i)
          {:temper_next, {i, runStart}}
        catch
          {:temper_continue, :ex_loop_2, ex_vars_16} ->
            {:temper_next, ex_vars_16}
          {:temper_break, :ex_loop_2, ex_vars_16} ->
            {:temper_done, ex_vars_16}
        end
        case ex_step_15 do
          {:temper_next, {i, runStart}} ->
            ex_loop_1.(ex_loop_1, i, runStart)
          {:temper_done, ex_vars_16} ->
            ex_vars_16
        end
      else
        {i, runStart}
      end
    end
    {_i, runStart} = ex_loop_1.(ex_loop_1, i, runStart)
    TemperCore.StringBuilder.append_between(out, text, runStart, TemperCore.String.end_of(text))
    TemperCore.StringBuilder.to_string(out)
  end
  def startsAWord(line, at) do
    if at <= TemperCore.String.begin() do
      true
    else
      Temper.MarginaliaCore.isUnicodeSpace(TemperCore.String.get(line, TemperCore.String.prev(line, at)))
    end
  end
  def abbreviationAt(line, dot, word) do
    try do
      _return = nil
      return = if true do
        if not Temper.MarginaliaCore.endsWithAt(line, dot, word) do
          return = false
          return
        else
          start = dot
          k = 0
          ex_loop_2 = fn ex_loop_2, k, start ->
            if k < TemperCore.String.count_between(word, TemperCore.String.begin(), TemperCore.String.end_of(word)) do
              start = TemperCore.String.prev(line, start)
              k = TemperCore.int32(k + 1)
              ex_loop_2.(ex_loop_2, k, start)
            else
              {k, start}
            end
          end
          {_k, start} = ex_loop_2.(ex_loop_2, k, start)
          throw({:temper_return, :ex_return_0, Temper.MarginaliaCore.startsAWord(line, start)})
        end
      end
      return
    catch
      {:temper_return, :ex_return_0, ex_value_4} ->
        ex_value_4
    end
  end
  def endsOnAbbreviation(line) do
    try do
      return = nil
      return = try do
        e = TemperCore.String.end_of(line)
        ex_loop_2 = fn ex_loop_2, e ->
          if true do
            _t2 = nil
            t2 = if e > TemperCore.String.begin() do
              t2 = Temper.MarginaliaCore.isCloser(TemperCore.String.get(line, TemperCore.String.prev(line, e)))
              t2
            else
              t2 = false
              t2
            end
            if not t2 do
              e
            else
              e = TemperCore.String.prev(line, e)
              ex_loop_2.(ex_loop_2, e)
            end
          else
            e
          end
        end
        e = ex_loop_2.(ex_loop_2, e)
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
          ex_loop_4 = fn ex_loop_4, k, return ->
            if k < TemperCore.List.length(TemperCore.Global.get(:"Temper.MarginaliaCore.abbreviations")) do
              if Temper.MarginaliaCore.abbreviationAt(line, dot, TemperCore.List.get(TemperCore.Global.get(:"Temper.MarginaliaCore.abbreviations"), k)) do
                return = true
                throw({:temper_break, :ex_block_1, return})
              else
                k = TemperCore.int32(k + 1)
                ex_loop_4.(ex_loop_4, k, return)
              end
            else
              {k, return}
            end
          end
          {_k, return} = ex_loop_4.(ex_loop_4, k, return)
          _return = if dot > TemperCore.String.begin() do
            c = TemperCore.String.prev(line, dot)
            cp = TemperCore.String.get(line, c)
            _t3 = nil
            t3 = if cp >= 65 do
              if cp <= 90 do
                t3 = Temper.MarginaliaCore.startsAWord(line, c)
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
              throw({:temper_break, :ex_block_1, return})
            else
              return
            end
          else
            return
          end
          throw({:temper_return, :ex_return_0, false})
        end
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
  def splitSentences(joined) do
    lines = TemperCore.String.split(Temper.MarginaliaCore.breakSentences(joined), "\n")
    out = TemperCore.List.builder()
    k = 0
    ex_loop_1 = fn ex_loop_1, k ->
      if k < TemperCore.List.length(lines) do
        n = TemperCore.List.length(out)
        _t = nil
        t = if n > 0 do
          t = Temper.MarginaliaCore.endsOnAbbreviation(TemperCore.List.get(out, TemperCore.int32(n - 1)))
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
        ex_loop_1.(ex_loop_1, k)
      else
        k
      end
    end
    _k = ex_loop_1.(ex_loop_1, k)
    Temper.MarginaliaCore.joinWith(TemperCore.List.to_list(out), "\n")
  end
  def squeezeBlanks(text) do
    out = TemperCore.StringBuilder.new()
    runStart = TemperCore.String.begin()
    i = TemperCore.String.begin()
    ex_loop_1 = fn ex_loop_1, i, runStart ->
      if TemperCore.String.has_index(text, i) do
        _t1 = nil
        t1 = if TemperCore.String.get(text, i) == 32 do
          t1 = true
          t1
        else
          t1 = TemperCore.String.get(text, i) == 9
          t1
        end
        if t1 do
          TemperCore.StringBuilder.append_between(out, text, runStart, i)
          TemperCore.StringBuilder.append(out, " ")
          ex_loop_3 = fn ex_loop_3, i ->
            if true do
              _t2 = nil
              t2 = if TemperCore.String.has_index(text, i) do
                if TemperCore.String.get(text, i) == 32 do
                  t2 = true
                  t2
                else
                  t2 = TemperCore.String.get(text, i) == 9
                  t2
                end
              else
                t2 = false
                t2
              end
              if not t2 do
                i
              else
                i = TemperCore.String.next(text, i)
                ex_loop_3.(ex_loop_3, i)
              end
            else
              i
            end
          end
          i = ex_loop_3.(ex_loop_3, i)
          runStart = i
          ex_loop_1.(ex_loop_1, i, runStart)
        else
          i = TemperCore.String.next(text, i)
          ex_loop_1.(ex_loop_1, i, runStart)
        end
      else
        {i, runStart}
      end
    end
    {_i, runStart} = ex_loop_1.(ex_loop_1, i, runStart)
    TemperCore.StringBuilder.append_between(out, text, runStart, TemperCore.String.end_of(text))
    TemperCore.StringBuilder.to_string(out)
  end
  def unwrap(block) do
    lines = TemperCore.String.split(block, "\n")
    last = TemperCore.int32(TemperCore.List.length(lines) - 1)
    pieces = TemperCore.List.builder()
    k = 0
    ex_loop_1 = fn ex_loop_1, k ->
      if k <= last do
        line = TemperCore.List.get(lines, k)
        b = TemperCore.String.begin()
        e = TemperCore.String.end_of(line)
        b = if k > 0 do
          ex_loop_3 = fn ex_loop_3, b ->
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
                ex_loop_3.(ex_loop_3, b)
              end
            else
              b
            end
          end
          b = ex_loop_3.(ex_loop_3, b)
          b
        else
          b
        end
        e = if k < last do
          ex_loop_5 = fn ex_loop_5, e ->
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
                ex_loop_5.(ex_loop_5, e)
              end
            else
              e
            end
          end
          e = ex_loop_5.(ex_loop_5, e)
          e
        else
          e
        end
        TemperCore.List.add(pieces, TemperCore.String.slice(line, b, e))
        k = TemperCore.int32(k + 1)
        ex_loop_1.(ex_loop_1, k)
      else
        k
      end
    end
    _k = ex_loop_1.(ex_loop_1, k)
    Temper.MarginaliaCore.joinWith(TemperCore.List.to_list(pieces), " ")
  end
  def reflowBlock(block) do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Heap.entry(fn ->
      try do
        _return = nil
        return = if true do
          cond do
            not Temper.MarginaliaCore.isProse(block) ->
              return = block
              return
            Temper.MarginaliaCore.isQuoted(block) ->
              return = Temper.MarginaliaCore.reflowQuote(block)
              return
            true ->
              throw({:temper_return, :ex_return_0, Temper.MarginaliaCore.splitSentences(Temper.MarginaliaCore.trim(Temper.MarginaliaCore.squeezeBlanks(Temper.MarginaliaCore.unwrap(block))))})
          end
        end
        return
      catch
        {:temper_return, :ex_return_0, ex_value_2} ->
          ex_value_2
      end
    end)
  end
  def deriveTitle(body, i) do
    first = TemperCore.List.get(TemperCore.String.split(body, "\n"), 0)
    h = TemperCore.String.begin()
    hashes = 0
    ex_loop_1 = fn ex_loop_1, h, hashes ->
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
          ex_loop_1.(ex_loop_1, h, hashes)
        end
      else
        {h, hashes}
      end
    end
    {h, hashes} = ex_loop_1.(ex_loop_1, h, hashes)
    _t1 = nil
    t1 = if hashes >= 1 do
      if hashes <= 6 do
        if TemperCore.String.has_index(first, h) do
          t1 = Temper.MarginaliaCore.isRegexSpace(TemperCore.String.get(first, h))
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
      ex_loop_3 = fn ex_loop_3, h ->
        if true do
          _t4 = nil
          t4 = if TemperCore.String.has_index(first, h) do
            t4 = Temper.MarginaliaCore.isRegexSpace(TemperCore.String.get(first, h))
            t4
          else
            t4 = false
            t4
          end
          if not t4 do
            h
          else
            h = TemperCore.String.next(first, h)
            ex_loop_3.(ex_loop_3, h)
          end
        else
          h
        end
      end
      h = ex_loop_3.(ex_loop_3, h)
      first = TemperCore.String.slice(first, h, TemperCore.String.end_of(first))
      {first, h}
    else
      {first, h}
    end
    plain = TemperCore.StringBuilder.new()
    k = TemperCore.String.begin()
    ex_loop_5 = fn ex_loop_5, k ->
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
        ex_loop_5.(ex_loop_5, k)
      else
        k
      end
    end
    _k = ex_loop_5.(ex_loop_5, k)
    label = Temper.MarginaliaCore.graphemePrefix(Temper.MarginaliaCore.trim(TemperCore.StringBuilder.to_string(plain)), 60)
    if Temper.MarginaliaCore.graphemeLength(label) > 12 do
      TemperCore.int_to_string(i) <> ". " <> label <> "…"
    else
      "Section " <> TemperCore.int_to_string(i)
    end
  end
  def byWindows(text) do
    bodies = Temper.MarginaliaCore.window(text)
    out = TemperCore.List.builder()
    k = 0
    ex_loop_1 = fn ex_loop_1, k ->
      if k < TemperCore.List.length(bodies) do
        body = Temper.MarginaliaCore.reflow(TemperCore.List.get(bodies, k))
        TemperCore.List.add(out, Temper.MarginaliaCore.Section.new(Temper.MarginaliaCore.deriveTitle(body, TemperCore.int32(k + 1)), body))
        k = TemperCore.int32(k + 1)
        ex_loop_1.(ex_loop_1, k)
      else
        k
      end
    end
    _k = ex_loop_1.(ex_loop_1, k)
    subject = Temper.MarginaliaCore.finish(TemperCore.List.to_list(out))
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
          text = Temper.MarginaliaCore.normalize(raw)
          if TemperCore.String.is_empty(text) do
            return = %TemperCore.Vec{t: {}}
            return
          else
            _chunks = nil
            _t = nil
            subject = Temper.MarginaliaCore.byMarkdown(text)
            t = if subject === nil do
              t = Temper.MarginaliaCore.byMarker(text)
              t
            else
              t = subject
              t
            end
            chunks = if t === nil do
              chunks = Temper.MarginaliaCore.byWindows(text)
              chunks
            else
              chunks = t
              chunks
            end
            fn_ = fn c ->
              Temper.MarginaliaCore.Section.new(Temper.MarginaliaCore.Section.get_title(c), Temper.MarginaliaCore.reflow(Temper.MarginaliaCore.Section.get_body(c)))
            end
            throw({:temper_return, :ex_return_0, TemperCore.List.map(chunks, fn_)})
          end
        end
        return
      catch
        {:temper_return, :ex_return_0, ex_value_3} ->
          ex_value_3
      end
    end)
  end
  def wordsOf(text) do
    out = TemperCore.List.builder()
    i = TemperCore.String.begin()
    ex_loop_1 = fn ex_loop_1, i ->
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
          ex_loop_1.(ex_loop_1, i)
        end
      else
        i
      end
    end
    i = ex_loop_1.(ex_loop_1, i)
    ex_loop_3 = fn ex_loop_3, i ->
      if TemperCore.String.has_index(text, i) do
        start = i
        ex_loop_5 = fn ex_loop_5, i ->
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
              ex_loop_5.(ex_loop_5, i)
            end
          else
            i
          end
        end
        i = ex_loop_5.(ex_loop_5, i)
        ex_loop_7 = fn ex_loop_7, i ->
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
              ex_loop_7.(ex_loop_7, i)
            end
          else
            i
          end
        end
        i = ex_loop_7.(ex_loop_7, i)
        TemperCore.List.add(out, TemperCore.String.slice(text, start, i))
        ex_loop_3.(ex_loop_3, i)
      else
        i
      end
    end
    _i = ex_loop_3.(ex_loop_3, i)
    TemperCore.List.to_list(out)
  end
  def distinct(words) do
    set = TemperCore.Map.builder()
    k = 0
    ex_loop_1 = fn ex_loop_1, k ->
      if k < TemperCore.List.length(words) do
        TemperCore.Map.set(set, TemperCore.List.get(words, k), true)
        k = TemperCore.int32(k + 1)
        ex_loop_1.(ex_loop_1, k)
      else
        k
      end
    end
    _k = ex_loop_1.(ex_loop_1, k)
    set
  end
  def unrelated(ak, bk) do
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
          a = TemperCore.Map.to_map(Temper.MarginaliaCore.distinct(ak))
          b = TemperCore.Map.to_map(Temper.MarginaliaCore.distinct(bk))
          bKeys = TemperCore.Map.keys(b)
          shared = 0
          k = 0
          ex_loop_2 = fn ex_loop_2, k, shared ->
            if k < TemperCore.List.length(bKeys) do
              shared = if TemperCore.Map.has(a, TemperCore.List.get(bKeys, k)) do
                shared = TemperCore.int32(shared + 1)
                shared
              else
                shared
              end
              k = TemperCore.int32(k + 1)
              ex_loop_2.(ex_loop_2, k, shared)
            else
              {k, shared}
            end
          end
          {_k, shared} = ex_loop_2.(ex_loop_2, k, shared)
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
          throw({:temper_return, :ex_return_0, TemperCore.Float.lt(TemperCore.int_to_float(shared), TemperCore.Float.mul(0.05, TemperCore.int_to_float(smaller)))})
        end
      end
      return
    catch
      {:temper_return, :ex_return_0, ex_value_4} ->
        ex_value_4
    end
  end
  def attach(script, aw, bw, parts) do
    ai = 0
    bi = 0
    c = 0
    ex_loop_1 = fn ex_loop_1, ai, bi, c ->
      if c < TemperCore.List.length(script) do
        chunk = TemperCore.List.get(script, c)
        count = TemperCore.List.length(Temper.MarginaliaCore.Chunk.get_words(chunk))
        k = 0
        ex_loop_3 = fn ex_loop_3, ai, bi, k ->
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
            ex_loop_3.(ex_loop_3, ai, bi, k)
          else
            {ai, bi, k}
          end
        end
        {ai, bi, _k} = ex_loop_3.(ex_loop_3, ai, bi, k)
        c = TemperCore.int32(c + 1)
        ex_loop_1.(ex_loop_1, ai, bi, c)
      else
        {ai, bi, c}
      end
    end
    {_ai, _bi, _c} = ex_loop_1.(ex_loop_1, ai, bi, c)
    nil
  end
  def moveDown(p, a) do
    if Temper.MarginaliaCore.Path.get_i(p) < TemperCore.List.length(a) do
      Temper.MarginaliaCore.Path.new(TemperCore.int32(Temper.MarginaliaCore.Path.get_y(p) + 1), TemperCore.int32(Temper.MarginaliaCore.Path.get_i(p) + 1), Temper.MarginaliaCore.Path.get_j(p), Temper.MarginaliaCore.Edit.new(1, TemperCore.List.get(a, Temper.MarginaliaCore.Path.get_i(p)), Temper.MarginaliaCore.Path.get_edits(p)))
    else
      Temper.MarginaliaCore.Path.new(TemperCore.int32(Temper.MarginaliaCore.Path.get_y(p) + 1), Temper.MarginaliaCore.Path.get_i(p), Temper.MarginaliaCore.Path.get_j(p), Temper.MarginaliaCore.Path.get_edits(p))
    end
  end
  def moveRight(p, b) do
    if Temper.MarginaliaCore.Path.get_j(p) < TemperCore.List.length(b) do
      Temper.MarginaliaCore.Path.new(Temper.MarginaliaCore.Path.get_y(p), Temper.MarginaliaCore.Path.get_i(p), TemperCore.int32(Temper.MarginaliaCore.Path.get_j(p) + 1), Temper.MarginaliaCore.Edit.new(2, TemperCore.List.get(b, Temper.MarginaliaCore.Path.get_j(p)), Temper.MarginaliaCore.Path.get_edits(p)))
    else
      p
    end
  end
  def followSnake(p, a, b) do
    y = Temper.MarginaliaCore.Path.get_y(p)
    i = Temper.MarginaliaCore.Path.get_i(p)
    j = Temper.MarginaliaCore.Path.get_j(p)
    edits = Temper.MarginaliaCore.Path.get_edits(p)
    ex_loop_1 = fn ex_loop_1, edits, i, j, y ->
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
          ex_loop_1.(ex_loop_1, edits, i, j, y)
        end
      else
        {edits, i, j, y}
      end
    end
    {edits, i, j, y} = ex_loop_1.(ex_loop_1, edits, i, j, y)
    Temper.MarginaliaCore.Path.new(y, i, j, edits)
  end
  def sameWords(x, y) do
    try do
      return = nil
      return = try do
        if TemperCore.List.length(x) != TemperCore.List.length(y) do
          return = false
          return
        else
          k = 0
          ex_loop_2 = fn ex_loop_2, k, return ->
            if k < TemperCore.List.length(x) do
              if TemperCore.List.get(x, k) != TemperCore.List.get(y, k) do
                return = false
                throw({:temper_break, :ex_block_1, return})
              else
                k = TemperCore.int32(k + 1)
                ex_loop_2.(ex_loop_2, k, return)
              end
            else
              {k, return}
            end
          end
          {_k, _return} = ex_loop_2.(ex_loop_2, k, return)
          throw({:temper_return, :ex_return_0, true})
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
  def compact(edits) do
    out = TemperCore.List.builder()
    e = edits
    ex_loop_1 = fn ex_loop_1, e ->
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
          ex_loop_1.(ex_loop_1, e)
        else
          _t2 = nil
          t2 = if n >= 3 do
            if Temper.MarginaliaCore.Chunk.get_kind(TemperCore.List.get(out, TemperCore.int32(n - 1))) == 0 do
              if Temper.MarginaliaCore.Chunk.get_kind(TemperCore.List.get(out, TemperCore.int32(n - 2))) == 2 do
                if Temper.MarginaliaCore.Chunk.get_kind(TemperCore.List.get(out, TemperCore.int32(n - 3))) == 0 do
                  t2 = Temper.MarginaliaCore.sameWords(Temper.MarginaliaCore.Chunk.get_words(TemperCore.List.get(out, TemperCore.int32(n - 1))), Temper.MarginaliaCore.Chunk.get_words(TemperCore.List.get(out, TemperCore.int32(n - 2))))
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
            ex_loop_1.(ex_loop_1, e)
          else
            words = TemperCore.List.builder()
            TemperCore.List.add(words, Temper.MarginaliaCore.Edit.get_word(edit))
            TemperCore.List.add(out, Temper.MarginaliaCore.Chunk.new(Temper.MarginaliaCore.Edit.get_kind(edit), words))
            e = Temper.MarginaliaCore.Edit.get_before(edit)
            ex_loop_1.(ex_loop_1, e)
          end
        end
      else
        e
      end
    end
    _e = ex_loop_1.(ex_loop_1, e)
    TemperCore.List.reverse(out)
    k = 0
    ex_loop_3 = fn ex_loop_3, k ->
      if k < TemperCore.List.length(out) do
        TemperCore.List.reverse(Temper.MarginaliaCore.Chunk.get_words(TemperCore.List.get(out, k)))
        k = TemperCore.int32(k + 1)
        ex_loop_3.(ex_loop_3, k)
      else
        k
      end
    end
    _k = ex_loop_3.(ex_loop_3, k)
    TemperCore.List.to_list(out)
  end
  def myers(a, b) do
    return = nil
    return = try do
      paths = %TemperCore.Vec{t: {Temper.MarginaliaCore.Path.new(0, 0, 0, nil)}}
      envelope = 0
      ex_loop_2 = fn ex_loop_2, envelope, paths, return ->
        if true do
          next = TemperCore.List.builder()
          at = 0
          diag = TemperCore.int32(-envelope)
          ex_loop_4 = fn ex_loop_4, at, diag, return ->
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
                  path = Temper.MarginaliaCore.moveDown(path, a)
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
                    path = Temper.MarginaliaCore.moveRight(path, b)
                    at = TemperCore.int32(at + 1)
                    {at, path}
                  else
                    _t4 = nil
                    second = TemperCore.List.get(paths, TemperCore.int32(at + 1))
                    t4 = if Temper.MarginaliaCore.Path.get_y(path) > Temper.MarginaliaCore.Path.get_y(second) do
                      t4 = Temper.MarginaliaCore.moveRight(path, b)
                      t4
                    else
                      t4 = Temper.MarginaliaCore.moveDown(second, a)
                      t4
                    end
                    path = t4
                    at = TemperCore.int32(at + 1)
                    {at, path}
                  end
              end
              path = Temper.MarginaliaCore.followSnake(path, a, b)
              _t2 = nil
              t2 = if Temper.MarginaliaCore.Path.get_i(path) == TemperCore.List.length(a) do
                t2 = Temper.MarginaliaCore.Path.get_j(path) == TemperCore.List.length(b)
                t2
              else
                t2 = false
                t2
              end
              if t2 do
                return = Temper.MarginaliaCore.compact(Temper.MarginaliaCore.Path.get_edits(path))
                throw({:temper_break, :ex_block_1, return})
              else
                TemperCore.List.add(next, path)
                diag = TemperCore.int32(diag + 2)
                ex_loop_4.(ex_loop_4, at, diag, return)
              end
            else
              {at, diag, return}
            end
          end
          {_at, _diag, return} = ex_loop_4.(ex_loop_4, at, diag, return)
          paths = TemperCore.List.to_list(next)
          envelope = TemperCore.int32(envelope + 1)
          ex_loop_2.(ex_loop_2, envelope, paths, return)
        else
          {envelope, paths, return}
        end
      end
      {_envelope, _paths, return} = ex_loop_2.(ex_loop_2, envelope, paths, return)
      return
    catch
      {:temper_break, :ex_block_1, ex_vars_6} ->
        ex_vars_6
    end
    return
  end
  def merge(parts) do
    out = TemperCore.List.builder()
    k = 0
    ex_loop_1 = fn ex_loop_1, k ->
      if k < TemperCore.List.length(parts) do
        kind = Temper.MarginaliaCore.Part.get_kind(TemperCore.List.get(parts, k))
        text = TemperCore.StringBuilder.new()
        ex_loop_3 = fn ex_loop_3, k ->
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
              ex_loop_3.(ex_loop_3, k)
            end
          else
            k
          end
        end
        k = ex_loop_3.(ex_loop_3, k)
        TemperCore.List.add(out, Temper.MarginaliaCore.Part.new(kind, TemperCore.StringBuilder.to_string(text)))
        ex_loop_1.(ex_loop_1, k)
      else
        k
      end
    end
    _k = ex_loop_1.(ex_loop_1, k)
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
      if Temper.MarginaliaCore.unrelated(ak, bk) do
        k1 = 0
        ex_loop_3 = fn ex_loop_3, k1 ->
          if k1 < TemperCore.List.length(aw) do
            TemperCore.List.add(parts, Temper.MarginaliaCore.Part.new("del", TemperCore.List.get(aw, k1)))
            k1 = TemperCore.int32(k1 + 1)
            ex_loop_3.(ex_loop_3, k1)
          else
            k1
          end
        end
        _k1 = ex_loop_3.(ex_loop_3, k1)
        k2 = 0
        ex_loop_5 = fn ex_loop_5, k2 ->
          if k2 < TemperCore.List.length(bw) do
            TemperCore.List.add(parts, Temper.MarginaliaCore.Part.new("ins", TemperCore.List.get(bw, k2)))
            k2 = TemperCore.int32(k2 + 1)
            ex_loop_5.(ex_loop_5, k2)
          else
            k2
          end
        end
        _k2 = ex_loop_5.(ex_loop_5, k2)
        nil
      else
        Temper.MarginaliaCore.attach(Temper.MarginaliaCore.myers(ak, bk), aw, bw, parts)
        nil
      end
      Temper.MarginaliaCore.merge(TemperCore.List.to_list(parts))
    end)
  end
  def __temper_init__() do
    TemperCore.init_once(:"Temper.MarginaliaCore", fn ->
      Temper.Orm.__temper_init__()
      Temper.Std.__temper_init__()
      TemperCore.Global.put(:"Temper.MarginaliaCore.columns", %TemperCore.Vec{t: {"id", "name", "published_at", "slug", "user_id", "parent_id", "inserted_at", "updated_at"}})
      TemperCore.Global.put(:"Temper.MarginaliaCore.folders", Temper.Orm.TableDef.new(Temper.MarginaliaCore.id("folders"), %TemperCore.Vec{t: {Temper.Orm.FieldDef.new(Temper.MarginaliaCore.id("name"), Temper.Orm.StringField.new(), false, nil, false), Temper.Orm.FieldDef.new(Temper.MarginaliaCore.id("parent_id"), Temper.Orm.Int64Field.new(), true, nil, false), Temper.Orm.FieldDef.new(Temper.MarginaliaCore.id("user_id"), Temper.Orm.Int64Field.new(), false, nil, false), Temper.Orm.FieldDef.new(Temper.MarginaliaCore.id("inserted_at"), Temper.Orm.DateField.new(), false, Temper.Orm.SqlSource.new("date_trunc('second', now() at time zone 'utc')"), false), Temper.Orm.FieldDef.new(Temper.MarginaliaCore.id("updated_at"), Temper.Orm.DateField.new(), false, Temper.Orm.SqlSource.new("date_trunc('second', now() at time zone 'utc')"), false)}}, nil))
      TemperCore.Global.put(:"Temper.MarginaliaCore.abbreviations", %TemperCore.Vec{t: {"e.g", "i.e", "vs", "etc", "cf", "viz", "ca", "Mr", "Mrs", "Ms", "Dr", "Prof", "St", "No", "Fig", "Jr", "Sr", "Inc", "Ltd", "Co"}})
      nil
    end)
  end
  def main() do
    Temper.MarginaliaCore.__temper_init__()
    TemperCore.Async.drain()
  end
end
