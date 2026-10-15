# Accounts

Ported from `Marginalia.Accounts` and the schemas under it
(`User`, `UserToken`, `UserNotifier`, `Mailer`). Auth is password only: no
magic-link login, no reset flow, no confirmation email on registration.

The Elixir returned Ecto changesets from the `change_*` functions and
`{:ok, x} | {:error, changeset}` from the writers. Here a changeset is a
`List<AccountsError>` (field and message, the Ecto messages verbatim), and a
writer returns an `AccountsResult`.

    let { Db } = import("db/src");
    let {
      sysUtcNow, sysRandomHex, sysRandomToken, sysPbkdf2, sysConstantTimeEq,
      sysGetEnv, sysGraphemeLength, sysGraphemeTake, sysByteLength, sysStringTrim,
      sysNowMs, sysUtcFromMs, sysUtf8Downcase, sysStringReplace,
    } = import("sys/src");

## Results and errors

    export class AccountsError(public field: String, public message: String) {}

`ok` is the user when the write happened. `errors` is the changeset's
errors when validation failed. `error` is a reason that is not a field
error: `transaction_aborted`, `unknown_provider`, `not_a_guest`. `expired`
is what `update_user_password` deleted (the Elixir's second tuple element).

    export class AccountsResult(
      public ok: User?,
      public errors: List<AccountsError>,
      public error: String?,
      public expired: List<UserToken>,
    ) {}

    let resultOk(user: User): AccountsResult {
      new AccountsResult(user, [], null, [])
    }

    let resultInvalid(errors: List<AccountsError>): AccountsResult {
      new AccountsResult(null, errors, null, [])
    }

    let resultFailed(reason: String): AccountsResult {
      new AccountsResult(null, [], reason, [])
    }

The messages on one field, as `errors_on(changeset).field` gave them.

    export let accountsErrorsOn(errors: List<AccountsError>, field: String): List<String> {
      let out = new ListBuilder<String>();
      for (let e of errors) {
        if (e.field == field) { out.add(e.message); }
      }
      out.toList()
    }

## Passwords

PBKDF2-HMAC-SHA256, a 16-byte salt, 32 bytes out, stored as
`pbkdf2-sha256$<iterations>$<salt hex>$<hash hex>`. The iteration count
stored in the hash is the one verification uses, so changing the setting does
not lock anyone out. New hashes use `MARGINALIA_PBKDF2_ITERATIONS`, default
600,000.

    export let accountsPbkdf2Iterations(): Int {
      let v = sysGetEnv("MARGINALIA_PBKDF2_ITERATIONS");
      if (v != null) {
        var n = 600000;
        let ok = do { n = v.toInt32(); true } orelse false;
        if (ok && n >= 1) { return n; }
      }
      600000
    }

    export let accountsHashPassword(password: String): String {
      let iterations = accountsPbkdf2Iterations();
      let salt = sysRandomHex(16);
      let hash = sysPbkdf2(password, salt, iterations, 32);
      "pbkdf2-sha256$${iterations.toString()}$${salt}$${hash}"
    }

    let verifyHash(password: String, stored: String): Boolean {
      let parts = stored.split("$");
      if (parts.length != 4) { return false; }
      if (parts[0] != "pbkdf2-sha256") { return false; }
      var iterations = 0;
      let ok = do { iterations = parts[1].toInt32(); true } orelse false;
      if (!ok || iterations < 1) { return false; }
      let got = sysPbkdf2(password, parts[2], iterations, 32);
      sysConstantTimeEq(got, parts[3])
    }

The fixed salt the dummy hash uses.

    let dummySalt(): String { "00000000000000000000000000000000" }

`User.valid_password?`. With no user, no hash, or an empty password the
Elixir called `Bcrypt.no_user_verify()` to spend the same time and then
answered false; the dummy hash here costs one PBKDF2 at the current
iteration count.

    export let accountsValidPassword(user: User?, password: String): Boolean {
      if (user != null) {
        let stored = user.hashedPassword;
        if (stored != null) {
          if (sysByteLength(password) > 0) {
            return verifyHash(password, stored);
          }
        }
      }
      sysPbkdf2("no user", dummySalt(), accountsPbkdf2Iterations(), 32);
      false
    }

## Changeset rules

Ecto's `cast` turns an empty (or whitespace-only) string into no value.

    let isBlank(s: String): Boolean { sysStringTrim(s) == "" }

    let blankToNull(s: String): String? {
      if (isBlank(s)) { null } else { s }
    }

`^[^@,;\s]+@[^@,;\s]+$`: exactly one `@`, something on each side, and none
of comma, semicolon or white space anywhere.

    let noBadChars(s: String): Boolean {
      let bad = [",", ";", " ", "\t", "\n", "\r", "\u{b}", "\u{c}"];
      var i = 0;
      while (i < bad.length) {
        if (s.split(bad[i]).length > 1) { return false; }
        i += 1;
      }
      true
    }

    let emailShapeOk(e: String): Boolean {
      let parts = e.split("@");
      if (parts.length != 2) { return false; }
      parts[0] != "" && parts[1] != "" && noBadChars(parts[0]) && noBadChars(parts[1])
    }

    let emailTaken(db: Db, email: String, exceptId: Int): Boolean throws Bubble {
      db.one("SELECT id FROM users WHERE email = $1 AND id != $2", [email, exceptId.toString()]) != null
    }

`User.email_changeset(user, attrs, opts)`. `currentEmail` and `currentId` are
the user's (null and -1 for a new one). Order of errors is Ecto's: required,
format, length, then (with `validateUnique`) uniqueness and "did not change".
Uniqueness is skipped when the email already has an error, as Ecto's
`unsafe_validate_unique` does. Format and length only look at a changed
value.

    let emailErrors(
      db: Db, currentEmail: String?, currentId: Int,
      params: Map<String, String>, validateUnique: Boolean,
    ): List<AccountsError> throws Bubble {
      let out = new ListBuilder<AccountsError>();
      var effective: String? = currentEmail;
      var changed = false;
      if (params.has("email")) {
        let v = blankToNull(params.getOr("email", ""));
        if (v != currentEmail) {
          changed = true;
          effective = v;
        }
      }
      let eff = effective;
      if (eff != null) {
        if (changed) {
          if (!emailShapeOk(eff)) {
            out.add(new AccountsError("email", "must have the @ sign and no spaces"));
          }
          if (sysGraphemeLength(eff) > 160) {
            out.add(new AccountsError("email", "should be at most 160 character(s)"));
          }
        }
      } else {
        out.add(new AccountsError("email", "can't be blank"));
      }
      if (validateUnique) {
        if (eff != null) {
          if (out.length == 0) {
            if (emailTaken(db, eff, currentId)) {
              out.add(new AccountsError("email", "has already been taken"));
            }
          }
          if (!changed) {
            out.add(new AccountsError("email", "did not change"));
          }
        }
      }
      out.toList()
    }

`User.password_changeset`: confirmation (only when a `password_confirmation`
key is supplied), required, 12 to 72 characters. `checkBytes` is the hashing
branch: if nothing else is wrong (`priorErrors` empty too, as Ecto's
`changeset.valid?` covers the whole chain), the password must also be at
most 72 bytes.

    let passwordErrors(
      params: Map<String, String>, checkBytes: Boolean, priorErrors: Int,
    ): List<AccountsError> {
      let out = new ListBuilder<AccountsError>();
      let pw = blankToNull(params.getOr("password", ""));
      if (params.has("password_confirmation")) {
        let conf = params.getOr("password_confirmation", "");
        let same = if (pw != null) { conf == pw } else { conf == "" };
        if (!same) {
          out.add(new AccountsError("password_confirmation", "does not match password"));
        }
      }
      if (pw != null) {
        let n = sysGraphemeLength(pw);
        if (n < 12) {
          out.add(new AccountsError("password", "should be at least 12 character(s)"));
        }
        if (n > 72) {
          out.add(new AccountsError("password", "should be at most 72 character(s)"));
        }
        if (checkBytes && out.length == 0 && priorErrors == 0 && sysByteLength(pw) > 72) {
          out.add(new AccountsError("password", "should be at most 72 byte(s)"));
        }
      } else {
        out.add(new AccountsError("password", "can't be blank"));
      }
      out.toList()
    }

    let concat(a: List<AccountsError>, b: List<AccountsError>): List<AccountsError> {
      let out = new ListBuilder<AccountsError>();
      for (let e of a) { out.add(e); }
      for (let e of b) { out.add(e); }
      out.toList()
    }

## Getters

    export let accountsGetUserByEmail(db: Db, email: String): User? throws Bubble {
      let row = db.one("SELECT ${userColumns} FROM users WHERE email = $1", [email]);
      if (row != null) { User.fromRow(row) } else { null }
    }

    export let accountsGetUserByEmailAndPassword(db: Db, email: String, password: String): User? throws Bubble {
      let user = accountsGetUserByEmail(db, email);
      if (accountsValidPassword(user, password)) { user } else { null }
    }

`get_user!`: a missing id bubbles (the Elixir raised `Ecto.NoResultsError`).

    export let accountsGetUser(db: Db, id: Int): User throws Bubble {
      let row = db.one("SELECT ${userColumns} FROM users WHERE id = $1", [id.toString()]);
      if (row != null) { User.fromRow(row) } else { bubble() }
    }

## Registration

Registers a user. `params` has `email`, `password` and optionally
`password_confirmation`. The account is usable at once: `confirmed_at` is
set. A unique-index failure at the insert (two registrations racing) is
reported as the same "has already been taken".

    export let accountsRegisterUser(db: Db, params: Map<String, String>): AccountsResult throws Bubble {
      let e1 = emailErrors(db, null, -1, params, true);
      let errs = concat(e1, passwordErrors(params, true, e1.length));
      if (errs.length > 0) { return resultInvalid(errs); }
      let now = sysUtcNow();
      var id = 0;
      let inserted = do {
        id = db.insert(
          "INSERT INTO users (email, hashed_password, confirmed_at, inserted_at, updated_at) VALUES ($1, $2, $3, $4, $4)",
          [params.getOr("email", ""), accountsHashPassword(params.getOr("password", "")), now, now],
        );
        true
      } orelse false;
      if (!inserted) {
        return resultInvalid([new AccountsError("email", "has already been taken")]);
      }
      resultOk(accountsGetUser(db, id))
    }

The registration form's changeset: email (no uniqueness) and password (no
hashing). The empty list is a valid form.

    export let accountsChangeUserRegistration(db: Db, params: Map<String, String>): List<AccountsError> throws Bubble {
      let e1 = emailErrors(db, null, -1, params, false);
      concat(e1, passwordErrors(params, false, e1.length))
    }

## Guests

A throwaway account tied to one browser session: a real row, marked
`is_guest`, with a password nobody knows, so it is only reachable through the
session token made for it. Email `guest-<22 url-safe characters>@guest.marginalia.local`.

    export let accountsCreateGuest(db: Db): User throws Bubble {
      let token = sysGraphemeTake(sysRandomToken(), 22);
      let now = sysUtcNow();
      let id = db.insert(
        "INSERT INTO users (email, hashed_password, confirmed_at, is_guest, inserted_at, updated_at) VALUES ($1, $2, $3, 1, $4, $4)",
        ["guest-${token}@guest.marginalia.local", accountsHashPassword(sysRandomToken()), now, now],
      );
      accountsGetUser(db, id)
    }

    export let accountsIsGuest(user: User): Boolean { user.isGuest }

Turns a guest into a real account on the same row, so everything they
uploaded stays theirs. A user who is not a guest gets `error` =
`not_a_guest` (the Elixir returned `{:error, user}`).

    export let accountsClaimGuestAccount(db: Db, user: User, params: Map<String, String>): AccountsResult throws Bubble {
      if (!user.isGuest) { return resultFailed("not_a_guest"); }
      let e1 = emailErrors(db, user.email, user.id, params, true);
      let errs = concat(e1, passwordErrors(params, true, e1.length));
      if (errs.length > 0) { return resultInvalid(errs); }
      let now = sysUtcNow();
      var done = false;
      let ok = do {
        db.exec(
          "UPDATE users SET email = $1, hashed_password = $2, is_guest = 0, confirmed_at = $3, updated_at = $3 WHERE id = $4",
          [params.getOr("email", ""), accountsHashPassword(params.getOr("password", "")), now, user.id.toString()],
        );
        done = true;
        true
      } orelse false;
      if (!ok) {
        return resultInvalid([new AccountsError("email", "has already been taken")]);
      }
      resultOk(accountsGetUser(db, user.id))
    }

## Sudo mode

The Elixir kept `authenticated_at` on the user struct, copied from the
session token. `User` here has no such field, so the time is passed: the web
layer reads it with `accountsSessionAuthenticatedAt`. Sudo mode is "last
authenticated no further back than `minutes` minutes" (`minutes` is
negative, default -20; the `require_sudo_mode` hook used -10). Null is not
in sudo mode.

    export let accountsSudoModeWithin(authenticatedAt: String?, minutes: Int): Boolean {
      if (authenticatedAt != null) {
        let cutoff = sysUtcFromMs(sysNowMs() + (minutes * 60000).toInt64());
        authenticatedAt > cutoff
      } else { false }
    }

    export let accountsSudoMode(authenticatedAt: String?): Boolean {
      accountsSudoModeWithin(authenticatedAt, -20)
    }

## Email change

The changeset for the settings form: with `validateUnique` it also reports
"has already been taken" and "did not change".

    export let accountsChangeUserEmail(db: Db, user: User, params: Map<String, String>, validateUnique: Boolean): List<AccountsError> throws Bubble {
      emailErrors(db, user.email, user.id, params, validateUnique)
    }

The only email the application sends. Swoosh ran its Local adapter in prod
and dev: the mail went to an in-memory mailbox no route ever showed, so the
flow could not finish in prod. Here the same mail is a row in `outbox`,
created lazily, which a person with the database can read. Nothing sends it.

    export class AccountsMail(
      public to: String,
      public from: String,
      public subject: String,
      public body: String,
    ) {}

    let outboxTable(db: Db): Void throws Bubble {
      db.script("CREATE TABLE IF NOT EXISTS outbox (id INTEGER PRIMARY KEY, to_addr TEXT NOT NULL, from_addr TEXT NOT NULL, subject TEXT NOT NULL, body TEXT NOT NULL, inserted_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%S','now')))");
    }

    let updateEmailBody(email: String, url: String): String {
      "\n==============================\n\nHi ${email},\n\nYou can change your email by visiting the URL below:\n\n${url}\n\nIf you didn't request this change, please ignore this.\n\n==============================\n"
    }

`deliver_user_update_email_instructions`. The caller passes the user with the
new email applied (so the token's `sent_to` and the mail's `to` are the new
address) and `currentEmail`, the address on file, which names the token's
context `change:<currentEmail>`. `urlFor` turns the token into the URL.

    export let accountsDeliverUserUpdateEmailInstructions(
      db: Db, user: User, currentEmail: String, urlFor: fn (String): String,
    ): AccountsMail throws Bubble {
      let token = userTokenBuildEmail(db, user.id, user.email, "change:${currentEmail}");
      let mail = new AccountsMail(
        user.email, "Marginalia <contact@example.com>", "Update email instructions",
        updateEmailBody(user.email, urlFor(token)),
      );
      outboxTable(db);
      db.insert(
        "INSERT INTO outbox (to_addr, from_addr, subject, body) VALUES ($1, $2, $3, $4)",
        [mail.to, mail.from, mail.subject, mail.body],
      );
      mail
    }

`update_user_email`: the token must be a `change:` token for the user's
current email, under 7 days old; the email becomes the address it was sent
to (with the uniqueness and did-not-change checks) and the user's tokens in
that context are deleted. Any failure is `error` = `transaction_aborted`
and nothing is changed.

    export let accountsUpdateUserEmail(db: Db, user: User, token: String): AccountsResult throws Bubble {
      let context = "change:${user.email}";
      let row = userTokenChangeEmailRow(db, token, context);
      if (row != null) {
        let sentTo = row.sentTo;
        if (sentTo != null) {
          return updateEmailTo(db, user, context, sentTo);
        }
      }
      resultFailed("transaction_aborted")
    }

    let updateEmailTo(db: Db, user: User, context: String, sentTo: String): AccountsResult throws Bubble {
      let newParams = new MapBuilder<String, String>();
      newParams.set("email", sentTo);
      let params = newParams.toMap();
      if (emailErrors(db, user.email, user.id, params, true).length > 0) {
        return resultFailed("transaction_aborted");
      }
      db.begin();
      let ok = do {
        db.exec(
          "UPDATE users SET email = $1, updated_at = $2 WHERE id = $3",
          [sentTo, sysUtcNow(), user.id.toString()],
        );
        db.exec(
          "DELETE FROM users_tokens WHERE user_id = $1 AND context = $2",
          [user.id.toString(), context],
        );
        true
      } orelse false;
      if (!ok) {
        db.rollback();
        return resultFailed("transaction_aborted");
      }
      db.commit();
      resultOk(accountsGetUser(db, user.id))
    }

## Password change

The form's changeset: the rules without hashing (so the byte limit, which
the Elixir applied only when hashing, is not checked).

    export let accountsChangeUserPassword(db: Db, user: User, params: Map<String, String>): List<AccountsError> {
      passwordErrors(params, false, 0)
    }

`update_user_password`: validates, stores the new hash, then deletes every
token the user has (sessions included) in the same transaction. The deleted
tokens are `expired` on the result, for the caller to disconnect sessions.

    export let accountsUpdateUserPassword(db: Db, user: User, params: Map<String, String>): AccountsResult throws Bubble {
      let errs = passwordErrors(params, true, 0);
      if (errs.length > 0) { return resultInvalid(errs); }
      let hash = accountsHashPassword(params.getOr("password", ""));
      let expired = new ListBuilder<UserToken>();
      db.begin();
      let ok = do {
        db.exec(
          "UPDATE users SET hashed_password = $1, updated_at = $2 WHERE id = $3",
          [hash, sysUtcNow(), user.id.toString()],
        );
        for (let r of db.query("SELECT ${userTokenColumns} FROM users_tokens WHERE user_id = $1", [user.id.toString()])) {
          expired.add(UserToken.fromRow(r));
        }
        db.exec("DELETE FROM users_tokens WHERE user_id = $1", [user.id.toString()]);
        true
      } orelse false;
      if (!ok) {
        db.rollback();
        bubble()
      }
      db.commit();
      new AccountsResult(accountsGetUser(db, user.id), [], null, expired.toList())
    }

## Sessions

A session token for the user, now. Returns the token string (what the
cookie carries). It is stored as given, 14 days of validity from now.

    export let accountsGenerateUserSessionToken(db: Db, user: User): String throws Bubble {
      let now = sysUtcNow();
      userTokenInsertSession(db, user.id, now, now)
    }

The same with an explicit `authenticated_at`, for reissuing a token to a
person who logged in earlier: the new token inherits when they really
authenticated.

    export let accountsGenerateUserSessionTokenAt(db: Db, user: User, authenticatedAt: String): String throws Bubble {
      userTokenInsertSession(db, user.id, authenticatedAt, sysUtcNow())
    }

The user and the token's `inserted_at`, or null for an unknown or expired
token.

    export let accountsGetUserBySessionToken(db: Db, token: String): Pair<User, String>? throws Bubble {
      let row = userTokenSessionRow(db, token);
      if (row != null) {
        new Pair<User, String>(accountsGetUser(db, row.userId), row.insertedAt)
      } else { null }
    }

When the session's token was made by a login (what `sudo_mode?` reads).

    export let accountsSessionAuthenticatedAt(db: Db, token: String): String? throws Bubble {
      let row = userTokenSessionRow(db, token);
      if (row != null) { row.authenticatedAt } else { null }
    }

True when the token is old enough that the web layer should issue a new one
(7 days).

    export let accountsSessionNeedsReissue(db: Db, insertedAt: String): Boolean throws Bubble {
      userTokenNeedsReissue(db, insertedAt)
    }

    export let accountsDeleteUserSessionToken(db: Db, token: String): Void throws Bubble {
      db.exec("DELETE FROM users_tokens WHERE token = $1 AND context = 'session'", [token]);
    }

## Owner, admin and the model backend

The deploy's owner email: `OWNER_EMAIL`, default `bobbbygrayson@gmail.com`.

    export let accountsOwnerEmail(): String {
      let v = sysGetEnv("OWNER_EMAIL");
      if (v != null) { v } else { "bobbbygrayson@gmail.com" }
    }

    export let accountsIsOwner(user: User): Boolean {
      sysUtf8Downcase(user.email) == sysUtf8Downcase(accountsOwnerEmail())
    }

The account this deploy belongs to, or null (also null if the owner email is
the empty string).

    export let accountsOwner(db: Db): User? throws Bubble {
      let email = accountsOwnerEmail();
      if (email == "") { return null; }
      accountsGetUserByEmail(db, email)
    }

`is_admin` is only set by `Release.make_admin`; admin confers nothing but the
flag. True if a user was found.

    export let accountsIsAdmin(user: User): Boolean { user.isAdmin }

    export let accountsMakeAdmin(db: Db, email: String): Boolean throws Bubble {
      let user = accountsGetUserByEmail(db, email);
      if (user != null) {
        db.exec("UPDATE users SET is_admin = 1, updated_at = $1 WHERE id = $2", [sysUtcNow(), user.id.toString()]);
        true
      } else { false }
    }

Which backend this user's work runs against: their `llm_provider` if it is
non-empty and they are the owner (not merely an admin); null means the deploy
default.

    export let accountsProviderFor(user: User): String? {
      let p = user.llmProvider;
      if (p != null && p != "" && accountsIsOwner(user)) { p } else { null }
    }

Sets the owner's backend. Anyone else is silently left alone (`ok` is the
unchanged user). An unknown provider is `error` = `unknown_provider`.

    export let accountsSetLlmProvider(db: Db, user: User, provider: String): AccountsResult throws Bubble {
      if (!accountsIsOwner(user)) { return resultOk(user); }
      if (provider != "deepseek" && provider != "openai") {
        return resultFailed("unknown_provider");
      }
      db.exec(
        "UPDATE users SET llm_provider = $1, updated_at = $2 WHERE id = $3",
        [provider, sysUtcNow(), user.id.toString()],
      );
      resultOk(accountsGetUser(db, user.id))
    }

## Tours

    export let accountsSeenTour(user: User, tour: String): Boolean {
      var i = 0;
      while (i < user.seenTours.length) {
        if (user.seenTours[i] == tour) { return true; }
        i += 1;
      }
      false
    }

    let jsonString(s: String): String {
      let a = sysStringReplace(s, "\\", "\\\\");
      "\"${sysStringReplace(a, "\"", "\\\"")}\""
    }

Records that a tab has been explained. A tour already seen leaves the row
alone; a new one is put at the front of `seen_tours` (the Elixir prepended).
Returns the user as it now is.

    export let accountsMarkTourSeen(db: Db, user: User, tour: String): User throws Bubble {
      if (accountsSeenTour(user, tour)) { return user; }
      let all = new ListBuilder<String>();
      all.add(tour);
      for (let t of user.seenTours) { all.add(t); }
      let json = "[${all.toList().join(",") { (t: String): String => jsonString(t) }}]";
      db.exec(
        "UPDATE users SET seen_tours = $1, updated_at = $2 WHERE id = $3",
        [json, sysUtcNow(), user.id.toString()],
      );
      accountsGetUser(db, user.id)
    }
