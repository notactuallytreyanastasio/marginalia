defmodule Marginalia.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use Marginalia.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias Marginalia.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Marginalia.DataCase
    end
  end

  setup tags do
    Marginalia.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Marginalia.Repo, shared: not tags[:async])

    on_exit(fn ->
      drain_tasks()
      Ecto.Adapters.SQL.Sandbox.stop_owner(pid)
    end)
  end

  @doc """
  Wait for the app's detached tasks before the sandbox owner goes away.

  A read and a link pass are both fire-and-forget: the LiveView asks for
  one and answers the socket immediately, which is the right shape for
  the product and a race in a test. The test finishes, its sandbox owner
  exits, and the task is still holding that connection — so it dies with
  a `DBConnection.ConnectionError` that is reported against whichever
  test happens to be running at the time.

  That made the suite fail perhaps one run in five, always somewhere
  unrelated to the change in hand, which is the most expensive kind of
  test failure there is: the kind you learn to ignore.

  Draining here rather than in each test, because the tests that start a
  pass are not the ones that were failing.
  """
  def drain_tasks(timeout \\ 2_000) do
    deadline = System.monotonic_time(:millisecond) + timeout

    # Empty twice in a row, not once. A read spawns a supervised task
    # which itself runs an async_stream, and those children belong to the
    # task rather than to the supervisor — so there is a moment where the
    # supervisor looks idle and a section is still writing its failure.
    wait = fn again, calm ->
      case Task.Supervisor.children(Marginalia.TaskSupervisor) do
        [] when calm ->
          :ok

        [] ->
          Process.sleep(25)
          again.(again, true)

        _children ->
          if System.monotonic_time(:millisecond) < deadline do
            Process.sleep(10)
            again.(again, false)
          else
            # Not fatal: a wedged task is a bug in the task, not in the
            # test that happened to be last. Leave it and let the owner
            # go, rather than hanging the suite.
            :timeout
          end
      end
    end

    wait.(wait, false)
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
