defmodule Marginalia.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Marginalia.Repo

  alias Marginalia.Accounts.{User, UserToken, UserNotifier}

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  A throwaway account tied to one browser session.

  Uploading a draft does not require signing up. The visitor still gets a real
  user row, so every ownership check in the app keeps working unchanged and
  one guest cannot reach another's drafts — the row is simply marked as a
  guest, and carries a password nobody knows, so it can only ever be reached
  through the session token it was created with.
  """
  def create_guest_user do
    token = :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)

    %User{}
    |> User.email_changeset(%{email: "guest-#{token}@guest.marginalia.local"},
      validate_unique: false
    )
    |> User.password_changeset(%{
      password: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    })
    |> Ecto.Changeset.put_change(:confirmed_at, DateTime.utc_now(:second))
    |> Ecto.Changeset.put_change(:is_guest, true)
    |> Repo.insert()
  end

  @doc """
  Turn a guest into a real account, keeping everything they have uploaded.

  This is the whole point of backing guests with a user row: signing up is a
  change of email and password on the row they already own, not a migration
  of their work from one owner to another.
  """
  def claim_guest_account(%User{is_guest: true} = user, attrs) do
    user
    |> User.email_changeset(attrs)
    |> User.password_changeset(attrs)
    |> Ecto.Changeset.put_change(:is_guest, false)
    |> Ecto.Changeset.put_change(:confirmed_at, DateTime.utc_now(:second))
    |> Repo.update()
  end

  def claim_guest_account(user, _attrs), do: {:error, user}

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    # Password-only auth: registration sets the password and the account is
    # usable immediately. There is no emailed confirmation step, so there is
    # nothing to confirm — leaving confirmed_at nil would lock the account out
    # of every path that checks it.
    %User{}
    |> User.email_changeset(attrs)
    |> User.password_changeset(attrs)
    |> Ecto.Changeset.put_change(:confirmed_at, DateTime.utc_now(:second))
    |> Repo.insert()
  end

  @doc "Changeset for the registration form: email and password together."
  def change_user_registration(user \\ %User{}, attrs \\ %{}) do
    user
    |> User.email_changeset(attrs, validate_unique: false)
    |> User.password_changeset(attrs, hash_password: false)
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `Marginalia.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `Marginalia.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end

  ## Model backend

  @doc """
  Whether this user may choose a backend at all.

  One account — the owner's — and nobody else, admin or not. Switching backend
  spends someone's money and changes what every analysis in the app was run
  against, so it is deliberately not a role that can be granted.
  """
  def owner?(%User{email: email}) when is_binary(email) do
    String.downcase(email) == String.downcase(owner_email())
  end

  def owner?(_user), do: false

  @doc "The account this deploy belongs to, or nil."
  def owner do
    case owner_email() do
      "" ->
        nil

      email ->
        Repo.one(from u in User, where: fragment("lower(?)", u.email) == ^String.downcase(email))
    end
  end

  defp owner_email, do: Application.get_env(:marginalia, :owner_email, "")

  @doc """
  Which model backend this user's work runs against.

  Returns nil for everyone but the owner, which makes the deploy default
  apply. The gate is here rather than in the UI so a crafted form post cannot
  switch backends.
  """
  def provider_for(%User{llm_provider: p} = user) when is_binary(p) and p != "" do
    if owner?(user), do: p, else: nil
  end

  def provider_for(_user), do: nil

  @doc "Set the owner's backend. Anyone else is silently left alone."
  def set_llm_provider(%User{} = user, provider) when is_binary(provider) do
    known = Enum.map(Marginalia.LLM.available(), &Atom.to_string/1)

    cond do
      not owner?(user) -> {:ok, user}
      provider not in known -> {:error, :unknown_provider}
      true -> user |> Ecto.Changeset.change(llm_provider: provider) |> Repo.update()
    end
  end

  def set_llm_provider(user, _provider), do: {:ok, user}

  ## Tours

  @doc "Has this person already had this tab explained?"
  def seen_tour?(%User{seen_tours: seen}, view) when is_list(seen),
    do: to_string(view) in seen

  def seen_tour?(_user, _view), do: true

  @doc """
  Record that a tab has been explained.

  Written when the tour is shown rather than when it is dismissed: a tour
  that reappears because someone navigated away mid-read is a tour that
  feels broken, and the Help button is there for anyone who wants it back.
  """
  def mark_tour_seen(%User{} = user, view) do
    view = to_string(view)

    if view in (user.seen_tours || []) do
      {:ok, user}
    else
      user
      |> Ecto.Changeset.change(seen_tours: Enum.uniq([view | user.seen_tours || []]))
      |> Repo.update()
    end
  end

  def mark_tour_seen(user, _view), do: {:ok, user}
end
