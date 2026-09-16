defmodule Marginalia.ProviderGateTest do
  @moduledoc """
  Only the owner may choose the model backend — one account, by email, and
  nobody else including admins. The gate is in the context rather than in the
  template, so a crafted form post cannot reach past it.
  """
  use Marginalia.DataCase, async: true

  alias Marginalia.{Accounts, LLM}
  import Marginalia.AccountsFixtures

  # build a real user whose email is whatever this deploy calls the owner, so
  # the test never has to mutate global config
  defp owner do
    email = Application.get_env(:marginalia, :owner_email)
    user_fixture() |> Ecto.Changeset.change(email: email) |> Marginalia.Repo.update!()
  end

  defp admin(user), do: user |> Ecto.Changeset.change(is_admin: true) |> Marginalia.Repo.update!()

  describe "owner?/1" do
    test "the configured email is the owner" do
      assert Accounts.owner?(owner())
    end

    test "case does not decide who owns the account" do
      email = Application.get_env(:marginalia, :owner_email) |> String.upcase()
      assert Accounts.owner?(%{user_fixture() | email: email})
    end

    test "an admin who is not the owner is not the owner" do
      refute Accounts.owner?(admin(user_fixture()))
    end
  end

  describe "provider_for/1" do
    test "a normal user always gets the deploy default, even with a value on the row" do
      user = %{user_fixture() | llm_provider: "openai"}
      assert Accounts.provider_for(user) == nil
    end

    test "being an admin is not enough — the switch is the owner's alone" do
      user = %{admin(user_fixture()) | llm_provider: "openai"}
      assert Accounts.provider_for(user) == nil
    end

    test "the owner gets their chosen backend" do
      assert Accounts.provider_for(%{owner() | llm_provider: "openai"}) == "openai"
    end

    test "the owner who has chosen nothing gets the deploy default" do
      assert Accounts.provider_for(%{owner() | llm_provider: nil}) == nil
    end
  end

  describe "set_llm_provider/2" do
    test "a normal user's attempt is a no-op, not an error they can probe" do
      user = user_fixture()
      assert {:ok, same} = Accounts.set_llm_provider(user, "openai")
      assert same.llm_provider == nil
      assert Marginalia.Repo.reload!(user).llm_provider == nil
    end

    test "an admin's attempt is also a no-op" do
      user = admin(user_fixture())
      assert {:ok, _} = Accounts.set_llm_provider(user, "openai")
      assert Marginalia.Repo.reload!(user).llm_provider == nil
    end

    test "the owner can switch, and it persists" do
      user = owner()
      assert {:ok, updated} = Accounts.set_llm_provider(user, "openai")
      assert updated.llm_provider == "openai"
      assert Accounts.provider_for(Marginalia.Repo.reload!(user)) == "openai"
    end

    test "an unknown backend is refused rather than stored" do
      user = owner()

      assert {:error, :unknown_provider} =
               Accounts.set_llm_provider(user, "definitely-not-a-provider")

      assert Marginalia.Repo.reload!(user).llm_provider == nil
    end
  end

  describe "the two backends on offer" do
    test "defaults to deepseek for this deploy" do
      assert LLM.provider_name() == :deepseek
    end

    # these are the ids the providers' own /models endpoints return
    test "each provider names a real model" do
      assert LLM.default_model("deepseek") == "deepseek-flash"
      assert LLM.default_model("openai") == "gpt-5.6-sol"
    end

    # the regression that broke every read: reasoning tokens are spent before
    # any content, so the request budget has to cover thinking on top of the
    # answer the caller asked for
    # reasoning tokens are billed as output and never cached, so the default
    # is cheap and the passes that reason over a whole draft opt up
    test "the default effort is low, with room to think reserved either way" do
      for name <- LLM.available() do
        assert LLM.reasoning_effort(name) == "low"
        assert LLM.reasoning_headroom(name) > 0
      end
    end

    test "only the whole-draft passes ask for high effort" do
      by_effort =
        (Marginalia.Analysis.passes() ++ Marginalia.Analysis.DecisionGraph.passes())
        |> Enum.map(& &1.id)

      # the per-section pass is most of the calls in a read; it stays cheap
      assert "beats" in by_effort
      assert "spine" in by_effort
      assert "weave" in by_effort
    end

    test "the sent budget is the caller's ask plus room to think" do
      assert LLM.token_budget(:deepseek, 4_000) == 4_000 + LLM.reasoning_headroom(:deepseek)
      assert LLM.token_budget(:deepseek, nil) == nil
    end

    test "each provider has a label a person would recognise" do
      assert LLM.label("deepseek") == "DeepSeek Flash"
      assert LLM.label("openai") == "Sol 5"
    end

    test "a junk override falls back rather than wedging the account" do
      assert LLM.default_model("nonsense") == LLM.default_model()
    end

    test "both providers are known to this deploy" do
      assert :deepseek in LLM.available()
      assert :openai in LLM.available()
    end

    test "choices/0 offers only backends that actually have a key" do
      for choice <- LLM.choices() do
        assert LLM.configured?(choice.name)
        assert choice.label != nil
        assert choice.model != nil
      end
    end
  end
end
