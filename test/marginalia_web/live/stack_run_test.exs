defmodule MarginaliaWeb.StackRunTest do
  @moduledoc """
  The folder page as a viewer of a pass, rather than its owner.

  Reading a folder forwards is one model call per document, in order,
  because each document is told what the ones before it established. For a
  hundred and forty-seven pull requests that is close to two hours. It used
  to run in a task linked to the socket, so closing the tab killed it and
  the money was already gone.

  What is asserted here is the consequence: a page that arrives while a pass
  is running shows the pass, and a page that presses the button while one is
  running is told rather than starting a second.
  """
  use MarginaliaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Marginalia.AccountsFixtures

  alias Marginalia.{Folders, Runs, Works}

  setup %{conn: conn} do
    Ecto.Adapters.SQL.Sandbox.mode(Marginalia.Repo, {:shared, self()})

    user = user_fixture()
    {:ok, folder} = Folders.create_folder(user.id, %{name: "Phoenix 1.8"})

    {:ok, work} =
      Works.create_work(user.id, %{
        "title" => "1. A chapter",
        "body" => "# A chapter\n\n" <> String.duplicate("word ", 120)
      })

    {:ok, _} = Folders.move_work(user.id, work.id, folder.id)

    # the compose control only exists once the folder has been read, so the
    # fixture is a folder that has been
    Marginalia.Repo.insert!(%Marginalia.Stacks.Step{
      folder_id: folder.id,
      work_id: work.id,
      ordinal: 1,
      capability: "read a folder forwards"
    })

    key = {:stack, folder.id}
    on_exit(fn -> Runs.forget(key) end)

    %{conn: log_in_user(conn, user), user: user, folder: folder, key: key}
  end

  # a pass that will not finish until the test lets it
  defp hold(key, kind) do
    me = self()

    {:ok, _} =
      Runs.start(key, kind, fn ->
        send(me, {:running, self()})
        receive do: ({:finish, v} -> v), after: (5_000 -> :timed_out)
      end)

    assert_receive {:running, pid}, 1_000
    pid
  end

  # Wait for the bookkeeping, rather than for a number of milliseconds.
  #
  # `Runs.progress/2` is a cast and the run's completion arrives at `Runs` as
  # a message from the task, so in both cases the call that follows raced the
  # broadcast: `render(view)` synchronises with the *view*, which is no help
  # if the view has not been sent anything yet. This failed about one run in
  # nine and took a deploy with it.
  #
  # A call to `Runs` is queued behind whatever it has already been sent, so
  # when this returns the broadcast has been made and the message is in the
  # view's mailbox — which puts it ahead of the `render` call that comes
  # next. No sleep can promise that, and a longer one only hides it better.
  defp settled do
    _ = :sys.get_state(Runs)
    :ok
  end

  # ...and for a worker that is finishing: the task sends its result to `Runs`
  # before it exits, so once it is gone that message is already queued there.
  defp settled(worker) do
    ref = Process.monitor(worker)
    assert_receive {:DOWN, ^ref, :process, ^worker, _}, 1_000
    settled()
  end

  test "a page that arrives mid-read shows the read, not the button", %{
    conn: conn,
    folder: folder,
    key: key
  } do
    worker = hold(key, :read)
    Runs.progress(key, done: 4, total: 12)
    settled()

    {:ok, _view, html} = live(conn, ~p"/stacks/#{folder.id}")

    assert html =~ "4 of 12"
    assert html =~ "you can close the page"
    assert html =~ "disabled"

    send(worker, {:finish, {:errors, 0}})
  end

  test "a page that arrives mid-compose says which part it is on", %{
    conn: conn,
    folder: folder,
    key: key
  } do
    worker = hold(key, :compose)
    Runs.progress(key, stage: "writing", done: 2, total: 5)
    settled()

    {:ok, _view, html} = live(conn, ~p"/stacks/#{folder.id}")

    assert html =~ "Composing — part 2 of 5"

    send(worker, {:finish, :ok})
  end

  test "an open page follows a pass it did not start", %{conn: conn, folder: folder, key: key} do
    {:ok, view, html} = live(conn, ~p"/stacks/#{folder.id}")
    refute html =~ "Composing"

    # something else entirely starts one — another tab, another device
    worker = hold(key, :compose)
    Runs.progress(key, stage: "outlining")
    settled()

    assert render(view) =~ "Composing — outlining"

    send(worker, {:finish, :ok})
    settled(worker)
    refute render(view) =~ "Composing —"
  end

  test "pressing the button twice does not start a second pass", %{
    conn: conn,
    folder: folder,
    key: key
  } do
    worker = hold(key, :read)

    {:ok, view, _} = live(conn, ~p"/stacks/#{folder.id}")
    html = render_click(view, "compose", %{})

    assert html =~ "A read pass is already running"
    assert %{kind: :read} = Runs.get(key), "the running pass is untouched"

    send(worker, {:finish, {:errors, 0}})
  end

  test "the socket going away leaves the pass alone", %{conn: conn, folder: folder, key: key} do
    {:ok, view, _} = live(conn, ~p"/stacks/#{folder.id}")

    worker = hold(key, :read)
    assert render(view) =~ "0 of"

    # what a closed tab or a dead wifi does
    ref = Process.monitor(worker)
    GenServer.stop(view.pid)

    refute_receive {:DOWN, ^ref, :process, ^worker, _}, 200
    assert Process.alive?(worker), "the pass must not be linked to the socket"
    assert %{kind: :read} = Runs.get(key)

    # and the next page finds it
    {:ok, _again, html} = live(conn, ~p"/stacks/#{folder.id}")
    assert html =~ "of"
    assert Runs.running?(key)

    send(worker, {:finish, {:errors, 0}})
  end

  test "a pass that crashes frees the folder and says so", %{
    conn: conn,
    folder: folder,
    key: key
  } do
    {:ok, view, _} = live(conn, ~p"/stacks/#{folder.id}")

    me = self()

    {:ok, _} =
      Runs.start(key, :compose, fn ->
        send(me, {:running, self()})
        receive do: (:crash -> raise "boom"), after: (5_000 -> :ok)
      end)

    assert_receive {:running, worker}, 1_000
    send(worker, :crash)
    settled(worker)

    html = render(view)
    assert html =~ "crashed"
    refute Runs.running?(key)
  end

  test "a progress tick shows the work, not only the count", ctx do
    {:ok, view, html} = live(ctx.conn, ~p"/stacks/#{ctx.folder.id}")
    refute html =~ "the second capability"

    worker = hold(ctx.key, :read)

    # what read_stack does: writes the step, then reports the tick. A second
    # document, because a step is unique to its document in its folder.
    {:ok, second} =
      Works.create_work(ctx.user.id, %{
        "title" => "2. Another chapter",
        "body" => "# Another\n\n" <> String.duplicate("word ", 120)
      })

    {:ok, _} = Folders.move_work(ctx.user.id, second.id, ctx.folder.id)

    Marginalia.Repo.insert!(%Marginalia.Stacks.Step{
      folder_id: ctx.folder.id,
      work_id: second.id,
      ordinal: 2,
      capability: "the second capability"
    })

    Runs.progress(ctx.key, done: 2, total: 12)
    settled()

    html = render(view)

    assert html =~ "2 of 12"

    assert html =~ "the second capability",
           "a forward read takes hours; showing only the counter while the steps sit " <>
             "unshown in the database is a page that looks like it is doing nothing"

    send(worker, {:finish, {:errors, 0}})
  end

  test "the summarise pass has its own button and its own sentence", ctx do
    {:ok, view, html} = live(ctx.conn, ~p"/stacks/#{ctx.folder.id}")

    assert html =~ "Summarise each document"
    assert html =~ "0 summarised"

    worker = hold(ctx.key, :summarise)
    Runs.progress(ctx.key, done: 1, total: 3)
    settled()

    html = render(view)

    assert html =~ "1 of 3"

    assert html =~ "one whole-document summary each",
           "the sentence has to say which pass this is: the forward read's " <>
             "\"waits on the one before it\" is not true of summaries"

    refute html =~ "waits on the one before it"

    send(worker, {:finish, {:errors, 0}})
  end

  test "it will not start while another pass is running", ctx do
    worker = hold(ctx.key, :read)

    {:ok, view, _} = live(ctx.conn, ~p"/stacks/#{ctx.folder.id}")
    html = render_click(view, "summarise", %{})

    assert html =~ "A read pass is already running"
    assert %{kind: :read} = Runs.get(ctx.key)

    send(worker, {:finish, {:errors, 0}})
  end
end
