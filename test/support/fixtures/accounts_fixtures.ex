defmodule Marginalia.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Marginalia.Accounts` context.
  """

  import Ecto.Query

  alias Marginalia.Accounts
  alias Marginalia.Accounts.Scope

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "hello world!"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      password: valid_user_password()
    })
  end

  @doc """
  A user with no confirmed_at. The app no longer produces these — registration
  confirms immediately — but `Marginalia.Accounts` still exposes the
  confirmation API, so its tests need one.
  """
  def unconfirmed_user_fixture(attrs \\ %{}) do
    user = user_fixture(attrs)
    user |> Ecto.Changeset.change(confirmed_at: nil) |> Marginalia.Repo.update!()
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Accounts.register_user()

    user
  end

  def user_scope_fixture do
    user = user_fixture()
    user_scope_fixture(user)
  end

  def user_scope_fixture(user) do
    Scope.for_user(user)
  end

  def set_password(user) do
    {:ok, {user, _expired_tokens}} =
      Accounts.update_user_password(user, %{password: valid_user_password()})

    user
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    Marginalia.Repo.update_all(
      from(t in Accounts.UserToken,
        where: t.token == ^token
      ),
      set: [authenticated_at: authenticated_at]
    )
  end

  def generate_user_magic_link_token(user) do
    {encoded_token, user_token} = Accounts.UserToken.build_email_token(user, "login")
    Marginalia.Repo.insert!(user_token)
    {encoded_token, user_token.token}
  end

  def offset_user_token(token, amount_to_add, unit) do
    dt = DateTime.add(DateTime.utc_now(:second), amount_to_add, unit)

    Marginalia.Repo.update_all(
      from(ut in Accounts.UserToken, where: ut.token == ^token),
      set: [inserted_at: dt, authenticated_at: dt]
    )
  end

  @doc """
  A user who is the owner of the deploy.

  Trace and Prompts are internals — how the thing works rather than what it
  found — so they are theirs alone. Tests that need them need this.
  """
  def owner_fixture do
    email = Application.get_env(:marginalia, :owner_email)

    user_fixture()
    |> Ecto.Changeset.change(email: email)
    |> Marginalia.Repo.update!()
  end

end
