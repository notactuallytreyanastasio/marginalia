# Tests for accounts

Ported from `test/marginalia/accounts_test.exs` (33 tests, 67 assertions),
plus the guest, tour, owner and provider tests that lived in
`guest_upload_test.exs` and `provider_gate_test.exs`.

Every check runs inside a helper that takes the `test`, or the frontend
evaluates it while compiling. Every database is `:memory:` and migrated.

None of these tests sets `MARGINALIA_PBKDF2_ITERATIONS`: the ones that go
through registration pay for the real 600,000 iterations. The fixture used
everywhere else inserts a user whose stored hash has 1,000 iterations, which
verification honours because it reads the count from the hash.

    let { dbOpen, Db, DbRow } = import("db/src");
    let {
      sysUtcNow, sysUtcFromMs, sysNowMs, sysMonoMs, sysRandomHex, sysSha256,
      sysPbkdf2, sysByteLength, sysGraphemeLength, sysGraphemeTake, sysUtf8Upcase,
    } = import("sys/src");

    let expectText(test: Test, got: String, want: String): Void {
      assert(got == want) { "got:\n${got}\nwant:\n${want}" }
    }

    let expectInt(test: Test, got: Int, want: Int): Void {
      assert(got == want) { "got ${got.toString()}, want ${want.toString()}" }
    }

    let expectTrue(test: Test, got: Boolean, what: String): Void {
      assert(got) { what }
    }

    let expectFalse(test: Test, got: Boolean, what: String): Void {
      assert(!got) { what }
    }

    let joined(xs: List<String>): String {
      xs.join("|") { (x: String): String => x }
    }

    let repeated(piece: String, n: Int): String {
      let sb = new StringBuilder();
      for (var i = 0; i < n; i += 1) { sb.append(piece); }
      sb.toString()
    }

    let hasText(s: String, part: String): Boolean { s.split(part).length > 1 }

    let orNull(s: String?): String {
      if (s != null) { s } else { "NULL" }
    }

## Fixtures

    let validPassword(): String { "hello world!" }

    let uniqueEmail(): String { "user${sysRandomHex(6)}@example.com" }

    let paramsOf(email: String, password: String): Map<String, String> {
      let b = new MapBuilder<String, String>();
      b.set("email", email);
      b.set("password", password);
      b.toMap()
    }

    let emailOnly(email: String): Map<String, String> {
      let b = new MapBuilder<String, String>();
      b.set("email", email);
      b.toMap()
    }

    let passwordOnly(password: String): Map<String, String> {
      let b = new MapBuilder<String, String>();
      b.set("password", password);
      b.toMap()
    }

    let passwordWithConfirmation(password: String, confirmation: String): Map<String, String> {
      let b = new MapBuilder<String, String>();
      b.set("password", password);
      b.set("password_confirmation", confirmation);
      b.toMap()
    }

    let noParams(): Map<String, String> {
      new MapBuilder<String, String>().toMap()
    }

A hash in the stored format with 1,000 iterations, so a fixture is cheap.

    let cheapHash(password: String): String {
      let salt = "0123456789abcdef0123456789abcdef";
      "pbkdf2-sha256$1000$${salt}$${sysPbkdf2(password, salt, 1000, 32)}"
    }

`user_fixture`: a confirmed user with the valid password.

    let userAt(db: Db, email: String): User throws Bubble {
      let id = db.insert(
        "INSERT INTO users (email, hashed_password, confirmed_at) VALUES ($1, $2, $3)",
        [email, cheapHash(validPassword()), sysUtcNow()],
      );
      accountsGetUser(db, id)
    }

    let userFixture(db: Db): User throws Bubble { userAt(db, uniqueEmail()) }

    let count(db: Db, query: String): Int throws Bubble {
      let row = db.one(query, []);
      if (row != null) { row.int("n") } else { -1 }
    }

    let tokenCount(db: Db, userId: Int): Int throws Bubble {
      count(db, "SELECT count(*) AS n FROM users_tokens WHERE user_id = ${userId.toString()}")
    }

    let userCount(db: Db): Int throws Bubble { count(db, "SELECT count(*) AS n FROM users") }

    let ageTokens(db: Db, sqlOffset: String): Void throws Bubble {
      db.exec("UPDATE users_tokens SET inserted_at = datetime('now', $1)", [sqlOffset]);
    }

    let longAgo(db: Db): Void throws Bubble {
      db.exec("UPDATE users_tokens SET inserted_at = '2020-01-01 00:00:00', authenticated_at = '2020-01-01 00:00:00'", []);
    }

    let minutesAgo(n: Int): String {
      sysUtcFromMs(sysNowMs() - (n * 60000).toInt64())
    }

    let resultUser(r: AccountsResult): User throws Bubble {
      let u = r.ok;
      if (u != null) { u } else { bubble() }
    }

    let errorsText(r: AccountsResult, field: String): String {
      joined(accountsErrorsOn(r.errors, field))
    }

    let rowOf(row: DbRow?): DbRow throws Bubble {
      if (row != null) { row } else { bubble() }
    }

    let didBubble(db: Db, query: String, params: List<String?>): Boolean {
      do { db.insert(query, params); false } orelse true
    }

## get_user_by_email

    test("does not return the user if the email does not exist") { test =>
      let db = dbOpen(":memory:");
      expectTrue(test, accountsGetUserByEmail(db, "unknown@example.com") == null, "no such user");
    }

    test("returns the user if the email exists") { test =>
      let db = dbOpen(":memory:");
      let user = userFixture(db);
      let found = accountsGetUserByEmail(db, user.email);
      expectTrue(test, found != null, "found");
      expectInt(test, if (found != null) { found.id } else { -1 }, user.id);
    }

    test("the email lookup ignores case, as citext did") { test =>
      let db = dbOpen(":memory:");
      let user = userAt(db, "Mixed.Case@Example.com");
      let found = accountsGetUserByEmail(db, "mixed.case@example.COM");
      expectInt(test, if (found != null) { found.id } else { -1 }, user.id);
    }

## get_user_by_email_and_password

    test("email and password: no user for an unknown email") { test =>
      let db = dbOpen(":memory:");
      expectTrue(test, accountsGetUserByEmailAndPassword(db, "unknown@example.com", validPassword()) == null, "unknown");
    }

    test("email and password: no user for an invalid password") { test =>
      let db = dbOpen(":memory:");
      let user = userFixture(db);
      expectTrue(test, accountsGetUserByEmailAndPassword(db, user.email, "invalid") == null, "wrong password");
    }

    test("email and password: the user for a valid password") { test =>
      let db = dbOpen(":memory:");
      let user = userFixture(db);
      let found = accountsGetUserByEmailAndPassword(db, user.email, validPassword());
      expectInt(test, if (found != null) { found.id } else { -1 }, user.id);
    }

## get_user!

    test("get_user! bubbles if the id is invalid") { test =>
      let db = dbOpen(":memory:");
      let missing = do { accountsGetUser(db, -1); false } orelse true;
      expectTrue(test, missing, "a missing id bubbles");
    }

    test("get_user! returns the user with the given id") { test =>
      let db = dbOpen(":memory:");
      let user = userFixture(db);
      expectInt(test, accountsGetUser(db, user.id).id, user.id);
    }

## register_user

    test("registration requires email to be set") { test =>
      let db = dbOpen(":memory:");
      let r = accountsRegisterUser(db, noParams());
      expectTrue(test, r.ok == null, "not registered");
      expectText(test, errorsText(r, "email"), "can't be blank");
    }

    test("registration treats a blank email as not set") { test =>
      let db = dbOpen(":memory:");
      let r = accountsRegisterUser(db, paramsOf("   ", validPassword()));
      expectText(test, errorsText(r, "email"), "can't be blank");
    }

    test("registration validates email when given") { test =>
      let db = dbOpen(":memory:");
      let r = accountsRegisterUser(db, emailOnly("not valid"));
      expectText(test, errorsText(r, "email"), "must have the @ sign and no spaces");
    }

    test("registration rejects the shapes the format forbids") { test =>
      let db = dbOpen(":memory:");
      let bad = ["a@@b.c", "@b.c", "a@", "a b@c.d", "a@b c.d", "a,b@c.d", "a@b;c.d", "plain"];
      var i = 0;
      while (i < bad.length) {
        let r = accountsRegisterUser(db, paramsOf(bad[i], validPassword()));
        expectText(test, errorsText(r, "email"), "must have the @ sign and no spaces");
        i += 1;
      }
    }

    test("registration accepts an unusual but well-formed email") { test =>
      let db = dbOpen(":memory:");
      expectTrue(test, accountsChangeUserRegistration(db, paramsOf("a+b.c-d@e-f.g.h", validPassword())).length == 0, "valid");
    }

    test("registration validates maximum values for email for security") { test =>
      let db = dbOpen(":memory:");
      let tooLong = repeated("db", 100);
      expectInt(test, sysGraphemeLength(tooLong), 200);
      let r = accountsRegisterUser(db, emailOnly(tooLong));
      let messages = accountsErrorsOn(r.errors, "email");
      expectTrue(test, messages.length == 2, "the @ message and the length message");
      expectText(test, messages[0], "must have the @ sign and no spaces");
      expectText(test, messages[1], "should be at most 160 character(s)");
    }

    test("registration accepts an email of exactly 160 characters") { test =>
      let db = dbOpen(":memory:");
      let local = repeated("db", 100);
      let email = "${sysGraphemeTake(local, 154)}@e.com";
      expectInt(test, sysGraphemeLength(email), 160);
      expectInt(test, accountsChangeUserRegistration(db, paramsOf(email, validPassword())).length, 0);
    }

    test("registration validates email uniqueness, ignoring case") { test =>
      let db = dbOpen(":memory:");
      let user = userFixture(db);
      let r = accountsRegisterUser(db, emailOnly(user.email));
      expectTrue(test, accountsErrorsOn(r.errors, "email").length > 0, "errors");
      expectTrue(test, hasText(errorsText(r, "email"), "has already been taken"), errorsText(r, "email"));
      let up = accountsRegisterUser(db, emailOnly(sysUtf8Upcase(user.email)));
      expectTrue(test, hasText(errorsText(up, "email"), "has already been taken"), errorsText(up, "email"));
    }

    test("registers users with a password and confirms them immediately") { test =>
      let db = dbOpen(":memory:");
      let email = uniqueEmail();
      let r = accountsRegisterUser(db, paramsOf(email, validPassword()));
      let user = resultUser(r);
      expectText(test, user.email, email);
      expectTrue(test, user.hashedPassword != null, "hashed password stored");
      expectTrue(test, user.confirmedAt != null, "password-only registration has nothing to confirm");
      expectFalse(test, user.isGuest, "not a guest");
      expectFalse(test, user.isAdmin, "not an admin");
      expectInt(test, user.seenTours.length, 0);
    }

    test("a registered user can sign in with the password they chose") { test =>
      let db = dbOpen(":memory:");
      let email = uniqueEmail();
      resultUser(accountsRegisterUser(db, paramsOf(email, validPassword())));
      expectTrue(test, accountsGetUserByEmailAndPassword(db, email, validPassword()) != null, "signs in");
      expectTrue(test, accountsGetUserByEmailAndPassword(db, email, "hello world?") == null, "wrong password");
    }

    test("registration requires a password") { test =>
      let db = dbOpen(":memory:");
      let r = accountsRegisterUser(db, emailOnly(uniqueEmail()));
      expectText(test, errorsText(r, "password"), "can't be blank");
    }

    test("registration validates password length and confirmation") { test =>
      let db = dbOpen(":memory:");
      let r = accountsRegisterUser(db, paramsOf(uniqueEmail(), "short"));
      expectText(test, errorsText(r, "password"), "should be at least 12 character(s)");
      let m = accountsRegisterUser(db, passwordWithConfirmation("hello world!", "hello world?"));
      expectText(test, errorsText(m, "password_confirmation"), "does not match password");
    }

    test("a failed registration writes nothing") { test =>
      let db = dbOpen(":memory:");
      accountsRegisterUser(db, paramsOf("not valid", validPassword()));
      accountsRegisterUser(db, emailOnly(uniqueEmail()));
      expectInt(test, userCount(db), 0);
    }

    test("the registration form changeset has no uniqueness check and no hash") { test =>
      let db = dbOpen(":memory:");
      let user = userFixture(db);
      expectInt(test, accountsChangeUserRegistration(db, paramsOf(user.email, validPassword())).length, 0);
      expectText(test, joined(accountsErrorsOn(accountsChangeUserRegistration(db, noParams()), "email")), "can't be blank");
      expectText(test, joined(accountsErrorsOn(accountsChangeUserRegistration(db, noParams()), "password")), "can't be blank");
    }

## Password hashing

    test("a password hash is pbkdf2-sha256 with iterations, salt and hash") { test =>
      let h = accountsHashPassword("hello world!");
      let parts = h.split("$");
      expectInt(test, parts.length, 4);
      expectText(test, parts[0], "pbkdf2-sha256");
      expectText(test, parts[1], accountsPbkdf2Iterations().toString());
      expectInt(test, sysByteLength(parts[2]), 32);
      expectInt(test, sysByteLength(parts[3]), 64);
    }

    test("two hashes of one password differ, and both verify") { test =>
      let a = accountsHashPassword("hello world!");
      let b = accountsHashPassword("hello world!");
      expectTrue(test, a != b, "fresh salt each time");
    }

    test("the default is 600000 iterations when the variable is unset") { test =>
      let n = accountsPbkdf2Iterations();
      expectTrue(test, n >= 1, "positive");
    }

    test("hashing at the default cost is timed") { test =>
      let t0 = sysMonoMs();
      let h = accountsHashPassword("hello world!");
      let t1 = sysMonoMs();
      console.log("pbkdf2 hash at ${accountsPbkdf2Iterations().toString()} iterations: ${(t1 - t0).toString()} ms");
      expectTrue(test, accountsValidPassword(userWithHash(h), "hello world!"), "verifies");
      let t2 = sysMonoMs();
      console.log("pbkdf2 verify: ${(t2 - t1).toString()} ms");
    }

    let userWithHash(hash: String?): User {
      new User(1, "x@example.com", hash, null, false, null, false, [], "2020-01-01 00:00:00", "2020-01-01 00:00:00")
    }

    test("verification uses the iteration count stored in the hash") { test =>
      expectTrue(test, accountsValidPassword(userWithHash(cheapHash("secret password")), "secret password"), "right");
      expectFalse(test, accountsValidPassword(userWithHash(cheapHash("secret password")), "secret passwor"), "wrong");
    }

    test("no user, no hash, an empty password, or a mangled hash is false") { test =>
      expectFalse(test, accountsValidPassword(null, "hello world!"), "no user");
      expectFalse(test, accountsValidPassword(userWithHash(null), "hello world!"), "no hash");
      expectFalse(test, accountsValidPassword(userWithHash(cheapHash("x")), ""), "empty password");
      expectFalse(test, accountsValidPassword(userWithHash("not a hash"), "x"), "mangled");
      expectFalse(test, accountsValidPassword(userWithHash("pbkdf2-sha256$abc$00$00"), "x"), "bad iterations");
      expectFalse(test, accountsValidPassword(userWithHash("bcrypt$1000$00$00"), "x"), "other scheme");
    }

## sudo_mode?

    test("sudo mode validates the authenticated_at time") { test =>
      expectTrue(test, accountsSudoMode(sysUtcNow()), "now");
      expectTrue(test, accountsSudoMode(minutesAgo(19)), "19 minutes ago");
      expectFalse(test, accountsSudoMode(minutesAgo(21)), "the default window is 20 minutes");
      expectFalse(test, accountsSudoModeWithin(minutesAgo(11), -10), "minute override");
      expectTrue(test, accountsSudoModeWithin(minutesAgo(9), -10), "inside the override");
      expectFalse(test, accountsSudoMode(null), "not authenticated");
    }

## change_user_email

    test("change_user_email requires an email") { test =>
      let db = dbOpen(":memory:");
      let errs = accountsChangeUserEmail(db, new User(0, "", null, null, false, null, false, [], "", ""), noParams(), true);
      expectTrue(test, errs.length > 0, "errors");
    }

    test("change_user_email: an email that did not change is an error") { test =>
      let db = dbOpen(":memory:");
      let user = userFixture(db);
      expectText(test, joined(accountsErrorsOn(accountsChangeUserEmail(db, user, emailOnly(user.email), true), "email")), "did not change");
      expectText(test, joined(accountsErrorsOn(accountsChangeUserEmail(db, user, noParams(), true), "email")), "did not change");
      expectInt(test, accountsChangeUserEmail(db, user, emailOnly(user.email), false).length, 0);
    }

    test("change_user_email: a new valid email has no errors, a taken one does") { test =>
      let db = dbOpen(":memory:");
      let user = userFixture(db);
      let other = userFixture(db);
      expectInt(test, accountsChangeUserEmail(db, user, emailOnly(uniqueEmail()), true).length, 0);
      expectText(test, joined(accountsErrorsOn(accountsChangeUserEmail(db, user, emailOnly(other.email), true), "email")), "has already been taken");
      expectInt(test, accountsChangeUserEmail(db, user, emailOnly(other.email), false).length, 0);
      expectText(test, joined(accountsErrorsOn(accountsChangeUserEmail(db, user, emailOnly("nope"), true), "email")), "must have the @ sign and no spaces");
      expectText(test, joined(accountsErrorsOn(accountsChangeUserEmail(db, user, emailOnly(""), true), "email")), "can't be blank");
    }

## deliver_user_update_email_instructions

    let tokenOf(url: String): String {
      let parts = url.split("[TOKEN]");
      parts[1]
    }

    test("delivering instructions stores a hashed token and sends the mail") { test =>
      let db = dbOpen(":memory:");
      let user = userFixture(db);
      var captured = "";
      let mail = accountsDeliverUserUpdateEmailInstructions(
        db, user, "current@example.com",
        fn (token: String): String { "[TOKEN]${token}[TOKEN]" },
      );
      let parts = mail.body.split("[TOKEN]");
      expectInt(test, parts.length, 3);
      captured = parts[1];
      let row = db.one("SELECT ${userTokenColumns} FROM users_tokens WHERE token = $1", [sysSha256(captured)]);
      expectTrue(test, row != null, "stored token is the SHA-256 of the token in the URL");
      let t = UserToken.fromRow(rowOf(row));
      expectInt(test, t.userId, user.id);
      expectText(test, orNull(t.sentTo), user.email);
      expectText(test, t.context, "change:current@example.com");
      expectTrue(test, db.one("SELECT id FROM users_tokens WHERE token = $1", [captured]) == null, "the raw token is not stored");
    }

    test("the mail is the notifier's text, and lands in the outbox") { test =>
      let db = dbOpen(":memory:");
      let user = userFixture(db);
      let mail = accountsDeliverUserUpdateEmailInstructions(
        db, user, user.email, fn (token: String): String { "https://x.test/users/settings/confirm-email/${token}" },
      );
      expectText(test, mail.to, user.email);
      expectText(test, mail.from, "Marginalia <contact@example.com>");
      expectText(test, mail.subject, "Update email instructions");
      let token = mail.body.split("confirm-email/")[1].split("\n")[0];
      expectText(
        test, mail.body,
        "\n==============================\n\nHi ${user.email},\n\nYou can change your email by visiting the URL below:\n\nhttps://x.test/users/settings/confirm-email/${token}\n\nIf you didn't request this change, please ignore this.\n\n==============================\n",
      );
      let out = db.one("SELECT to_addr, from_addr, subject, body FROM outbox", []);
      expectTrue(test, out != null, "one outbox row");
      expectText(test, if (out != null) { out.str("body") } else { "" }, mail.body);
      expectText(test, if (out != null) { out.str("to_addr") } else { "" }, user.email);
      expectInt(test, count(db, "SELECT count(*) AS n FROM outbox"), 1);
    }

## update_user_email

    class EmailChange(public user: User, public token: String, public email: String) {}

The Elixir setup: a user, a new email, and a token mailed to the new address
whose context names the old one.

    let emailChange(db: Db): EmailChange throws Bubble {
      let user = userFixture(db);
      let email = uniqueEmail();
      let moved = new User(
        user.id, email, user.hashedPassword, user.confirmedAt, user.isAdmin, user.llmProvider,
        user.isGuest, user.seenTours, user.insertedAt, user.updatedAt,
      );
      let mail = accountsDeliverUserUpdateEmailInstructions(
        db, moved, user.email, fn (token: String): String { "[TOKEN]${token}[TOKEN]" },
      );
      new EmailChange(user, mail.body.split("[TOKEN]")[1], email)
    }

    test("updates the email with a valid token") { test =>
      let db = dbOpen(":memory:");
      let c = emailChange(db);
      let r = accountsUpdateUserEmail(db, c.user, c.token);
      expectText(test, resultUser(r).email, c.email);
      let changed = accountsGetUser(db, c.user.id);
      expectTrue(test, changed.email != c.user.email, "changed");
      expectText(test, changed.email, c.email);
      expectInt(test, tokenCount(db, c.user.id), 0);
    }

    test("does not update email with invalid token") { test =>
      let db = dbOpen(":memory:");
      let c = emailChange(db);
      let r = accountsUpdateUserEmail(db, c.user, "oops");
      expectText(test, orNull(r.error), "transaction_aborted");
      expectTrue(test, r.ok == null, "no user");
      expectText(test, accountsGetUser(db, c.user.id).email, c.user.email);
      expectInt(test, tokenCount(db, c.user.id), 1);
    }

    test("does not update email if user email changed") { test =>
      let db = dbOpen(":memory:");
      let c = emailChange(db);
      let other = new User(
        c.user.id, "current@example.com", c.user.hashedPassword, c.user.confirmedAt, false, null,
        false, [], c.user.insertedAt, c.user.updatedAt,
      );
      let r = accountsUpdateUserEmail(db, other, c.token);
      expectText(test, orNull(r.error), "transaction_aborted");
      expectText(test, accountsGetUser(db, c.user.id).email, c.user.email);
      expectInt(test, tokenCount(db, c.user.id), 1);
    }

    test("does not update email if token expired") { test =>
      let db = dbOpen(":memory:");
      let c = emailChange(db);
      expectInt(test, db.exec("UPDATE users_tokens SET inserted_at = '2020-01-01 00:00:00'", []), 1);
      let r = accountsUpdateUserEmail(db, c.user, c.token);
      expectText(test, orNull(r.error), "transaction_aborted");
      expectText(test, accountsGetUser(db, c.user.id).email, c.user.email);
      expectInt(test, tokenCount(db, c.user.id), 1);
    }

    test("an email-change token is good for 7 days and not 8") { test =>
      let db = dbOpen(":memory:");
      let c = emailChange(db);
      ageTokens(db, "-8 days");
      expectText(test, orNull(accountsUpdateUserEmail(db, c.user, c.token).error), "transaction_aborted");
      ageTokens(db, "-6 days");
      expectText(test, resultUser(accountsUpdateUserEmail(db, c.user, c.token)).email, c.email);
    }

    test("an email-change token works once") { test =>
      let db = dbOpen(":memory:");
      let c = emailChange(db);
      resultUser(accountsUpdateUserEmail(db, c.user, c.token));
      let moved = accountsGetUser(db, c.user.id);
      expectText(test, orNull(accountsUpdateUserEmail(db, moved, c.token).error), "transaction_aborted");
    }

    test("the email-change token is useless if the new address was taken meanwhile") { test =>
      let db = dbOpen(":memory:");
      let c = emailChange(db);
      userAt(db, c.email);
      let r = accountsUpdateUserEmail(db, c.user, c.token);
      expectText(test, orNull(r.error), "transaction_aborted");
      expectText(test, accountsGetUser(db, c.user.id).email, c.user.email);
      expectInt(test, tokenCount(db, c.user.id), 1);
    }

    test("a session token is not an email-change token") { test =>
      let db = dbOpen(":memory:");
      let user = userFixture(db);
      let session = accountsGenerateUserSessionToken(db, user);
      expectText(test, orNull(accountsUpdateUserEmail(db, user, session).error), "transaction_aborted");
      expectInt(test, tokenCount(db, user.id), 1);
    }

## change_user_password

    test("change_user_password requires a password") { test =>
      let db = dbOpen(":memory:");
      let user = userFixture(db);
      expectText(test, joined(accountsErrorsOn(accountsChangeUserPassword(db, user, noParams()), "password")), "can't be blank");
    }

    test("change_user_password allows fields to be set") { test =>
      let db = dbOpen(":memory:");
      let user = userFixture(db);
      expectInt(test, accountsChangeUserPassword(db, user, passwordOnly("new valid password")).length, 0);
      expectText(test, orNull(accountsGetUser(db, user.id).hashedPassword), orNull(user.hashedPassword));
    }

    test("change_user_password reports a mismatched confirmation") { test =>
      let db = dbOpen(":memory:");
      let user = userFixture(db);
      let errs = accountsChangeUserPassword(db, user, passwordWithConfirmation("new valid password", "another"));
      expectText(test, joined(accountsErrorsOn(errs, "password_confirmation")), "does not match password");
      expectInt(test, accountsChangeUserPassword(db, user, passwordWithConfirmation("new valid password", "new valid password")).length, 0);
    }

## update_user_password

    test("update_user_password validates password") { test =>
      let db = dbOpen(":memory:");
      let user = userFixture(db);
      let r = accountsUpdateUserPassword(db, user, passwordWithConfirmation("not valid", "another"));
      expectText(test, errorsText(r, "password"), "should be at least 12 character(s)");
      expectText(test, errorsText(r, "password_confirmation"), "does not match password");
      expectInt(test, r.errors.length, 2);
    }

    test("update_user_password validates maximum values for password for security") { test =>
      let db = dbOpen(":memory:");
      let user = userFixture(db);
      let tooLong = repeated("db", 100);
      let r = accountsUpdateUserPassword(db, user, passwordOnly(tooLong));
      expectTrue(test, hasText(errorsText(r, "password"), "should be at most 72 character(s)"), errorsText(r, "password"));
    }

    test("update_user_password caps the password at 72 bytes as well as characters") { test =>
      let db = dbOpen(":memory:");
      let user = userFixture(db);
      let wide = "\u{e9}\u{e9}\u{e9}\u{e9}\u{e9}\u{e9}\u{e9}\u{e9}\u{e9}\u{e9}\u{e9}\u{e9}\u{e9}\u{e9}\u{e9}\u{e9}\u{e9}\u{e9}\u{e9}\u{e9}\u{e9}\u{e9}\u{e9}\u{e9}\u{e9}\u{e9}\u{e9}\u{e9}\u{e9}\u{e9}\u{e9}\u{e9}\u{e9}\u{e9}\u{e9}\u{e9}\u{e9}\u{e9}\u{e9}\u{e9}\u{e9}\u{e9}";
      expectInt(test, sysGraphemeLength(wide), 42);
      expectInt(test, sysByteLength(wide), 84);
      let r = accountsUpdateUserPassword(db, user, passwordOnly(wide));
      expectText(test, errorsText(r, "password"), "should be at most 72 byte(s)");
      expectInt(test, accountsChangeUserPassword(db, user, passwordOnly(wide)).length, 0);
    }

    test("update_user_password updates the password") { test =>
      let db = dbOpen(":memory:");
      let user = userFixture(db);
      let r = accountsUpdateUserPassword(db, user, passwordOnly("new valid password"));
      expectInt(test, r.expired.length, 0);
      let updated = resultUser(r);
      expectTrue(test, accountsGetUserByEmailAndPassword(db, updated.email, "new valid password") != null, "new password works");
      expectTrue(test, accountsGetUserByEmailAndPassword(db, updated.email, validPassword()) == null, "old password does not");
    }

    test("update_user_password deletes all tokens for the given user and returns them") { test =>
      let db = dbOpen(":memory:");
      let user = userFixture(db);
      let other = userFixture(db);
      accountsGenerateUserSessionToken(db, user);
      accountsGenerateUserSessionToken(db, user);
      accountsGenerateUserSessionToken(db, other);
      accountsDeliverUserUpdateEmailInstructions(db, user, user.email, fn (t: String): String { t });
      expectInt(test, tokenCount(db, user.id), 3);
      let r = accountsUpdateUserPassword(db, user, passwordOnly("new valid password"));
      expectInt(test, tokenCount(db, user.id), 0);
      expectInt(test, r.expired.length, 3);
      expectInt(test, tokenCount(db, other.id), 1);
    }

    test("a failed password update keeps the tokens") { test =>
      let db = dbOpen(":memory:");
      let user = userFixture(db);
      accountsGenerateUserSessionToken(db, user);
      accountsUpdateUserPassword(db, user, passwordOnly("short"));
      expectInt(test, tokenCount(db, user.id), 1);
    }

## Session tokens

    test("generates a token") { test =>
      let db = dbOpen(":memory:");
      let user = userFixture(db);
      let token = accountsGenerateUserSessionToken(db, user);
      let row = db.one("SELECT ${userTokenColumns} FROM users_tokens WHERE token = $1", [token]);
      expectTrue(test, row != null, "stored raw");
      let t = UserToken.fromRow(rowOf(row));
      expectText(test, t.context, "session");
      expectTrue(test, t.authenticatedAt != null, "authenticated_at set");
      expectInt(test, t.userId, user.id);
      expectInt(test, sysByteLength(token), 43);
      let other = userFixture(db);
      expectTrue(
        test,
        didBubble(
          db, "INSERT INTO users_tokens (token, user_id, context) VALUES ($1, $2, 'session')",
          [t.token, other.id.toString()],
        ),
        "the same token for another user violates the unique index",
      );
    }

    test("two tokens differ") { test =>
      let db = dbOpen(":memory:");
      let user = userFixture(db);
      expectTrue(test, accountsGenerateUserSessionToken(db, user) != accountsGenerateUserSessionToken(db, user), "random");
      expectInt(test, tokenCount(db, user.id), 2);
    }

    test("duplicates the authenticated_at of given user in new token") { test =>
      let db = dbOpen(":memory:");
      let user = userFixture(db);
      let earlier = minutesAgo(60);
      let token = accountsGenerateUserSessionTokenAt(db, user, earlier);
      let row = db.one("SELECT ${userTokenColumns} FROM users_tokens WHERE token = $1", [token]);
      let t = UserToken.fromRow(rowOf(row));
      expectText(test, orNull(t.authenticatedAt), earlier);
      expectTrue(test, t.insertedAt > earlier, "inserted after it was authenticated");
      expectText(test, orNull(accountsSessionAuthenticatedAt(db, token)), earlier);
    }

    test("returns user by token") { test =>
      let db = dbOpen(":memory:");
      let user = userFixture(db);
      let token = accountsGenerateUserSessionToken(db, user);
      let got = accountsGetUserBySessionToken(db, token);
      expectTrue(test, got != null, "found");
      expectInt(test, if (got != null) { got.key.id } else { -1 }, user.id);
      expectInt(test, if (got != null) { sysByteLength(got.value) } else { -1 }, 19);
      expectTrue(test, accountsSessionAuthenticatedAt(db, token) != null, "authenticated_at");
    }

    test("does not return user for invalid token") { test =>
      let db = dbOpen(":memory:");
      userFixture(db);
      expectTrue(test, accountsGetUserBySessionToken(db, "oops") == null, "invalid");
      expectTrue(test, accountsGetUserBySessionToken(db, "") == null, "empty");
    }

    test("does not return user for expired token") { test =>
      let db = dbOpen(":memory:");
      let user = userFixture(db);
      let token = accountsGenerateUserSessionToken(db, user);
      longAgo(db);
      expectTrue(test, accountsGetUserBySessionToken(db, token) == null, "expired");
    }

    test("a session token is good for 14 days and not 15") { test =>
      let db = dbOpen(":memory:");
      let user = userFixture(db);
      let token = accountsGenerateUserSessionToken(db, user);
      ageTokens(db, "-13 days");
      expectTrue(test, accountsGetUserBySessionToken(db, token) != null, "13 days old");
      ageTokens(db, "-15 days");
      expectTrue(test, accountsGetUserBySessionToken(db, token) == null, "past 14 days");
    }

    test("an email-change token is not a session token") { test =>
      let db = dbOpen(":memory:");
      let user = userFixture(db);
      let t = userTokenBuildEmail(db, user.id, user.email, "change:${user.email}");
      expectTrue(test, accountsGetUserBySessionToken(db, t) == null, "not a session");
      expectTrue(test, accountsGetUserBySessionToken(db, sysSha256(t)) == null, "not a session by hash either");
    }

    test("session tokens are due for reissue after 7 days") { test =>
      let db = dbOpen(":memory:");
      let user = userFixture(db);
      let token = accountsGenerateUserSessionToken(db, user);
      let fresh = accountsGetUserBySessionToken(db, token);
      expectFalse(test, accountsSessionNeedsReissue(db, if (fresh != null) { fresh.value } else { "" }), "fresh");
      ageTokens(db, "-6 days");
      let six = accountsGetUserBySessionToken(db, token);
      expectFalse(test, accountsSessionNeedsReissue(db, if (six != null) { six.value } else { "" }), "6 days");
      ageTokens(db, "-8 days");
      let eight = accountsGetUserBySessionToken(db, token);
      expectTrue(test, accountsSessionNeedsReissue(db, if (eight != null) { eight.value } else { "" }), "8 days");
    }

    test("deletes the token") { test =>
      let db = dbOpen(":memory:");
      let user = userFixture(db);
      let token = accountsGenerateUserSessionToken(db, user);
      accountsDeleteUserSessionToken(db, token);
      expectTrue(test, accountsGetUserBySessionToken(db, token) == null, "gone");
      expectInt(test, tokenCount(db, user.id), 0);
    }

    test("deleting one session leaves the others, and only sessions") { test =>
      let db = dbOpen(":memory:");
      let user = userFixture(db);
      let a = accountsGenerateUserSessionToken(db, user);
      let b = accountsGenerateUserSessionToken(db, user);
      accountsDeleteUserSessionToken(db, a);
      expectTrue(test, accountsGetUserBySessionToken(db, a) == null, "a gone");
      expectTrue(test, accountsGetUserBySessionToken(db, b) != null, "b kept");
      accountsDeleteUserSessionToken(db, "never issued");
      expectInt(test, tokenCount(db, user.id), 1);
    }

    test("deleting a user deletes their tokens") { test =>
      let db = dbOpen(":memory:");
      let user = userFixture(db);
      let token = accountsGenerateUserSessionToken(db, user);
      db.exec("DELETE FROM users WHERE id = $1", [user.id.toString()]);
      expectTrue(test, accountsGetUserBySessionToken(db, token) == null, "cascade");
    }

## Guests

    test("a guest is a real row marked as a guest, confirmed, with a password") { test =>
      let db = dbOpen(":memory:");
      let g = accountsCreateGuest(db);
      expectTrue(test, accountsIsGuest(g), "guest");
      expectTrue(test, g.confirmedAt != null, "confirmed");
      expectTrue(test, g.hashedPassword != null, "has a password nobody knows");
      expectFalse(test, g.isAdmin, "not admin");
      expectInt(test, userCount(db), 1);
    }

    test("a guest email is guest-<22 characters>@guest.marginalia.local, and unique") { test =>
      let db = dbOpen(":memory:");
      let a = accountsCreateGuest(db);
      let b = accountsCreateGuest(db);
      expectTrue(test, a.email != b.email, "distinct");
      let parts = a.email.split("@");
      expectText(test, parts[1], "guest.marginalia.local");
      expectInt(test, sysGraphemeLength(parts[0]), 28);
      expectText(test, sysGraphemeTake(parts[0], 6), "guest-");
    }

    test("a guest can be reached by a session token") { test =>
      let db = dbOpen(":memory:");
      let g = accountsCreateGuest(db);
      let token = accountsGenerateUserSessionToken(db, g);
      let got = accountsGetUserBySessionToken(db, token);
      expectInt(test, if (got != null) { got.key.id } else { -1 }, g.id);
    }

    test("claiming a guest account keeps the row and its work") { test =>
      let db = dbOpen(":memory:");
      let g = accountsCreateGuest(db);
      db.insert("INSERT INTO works (user_id, title, body, slug) VALUES ($1, 'T', 'b', 't')", [g.id.toString()]);
      let email = uniqueEmail();
      let r = accountsClaimGuestAccount(db, g, paramsOf(email, validPassword()));
      let user = resultUser(r);
      expectInt(test, user.id, g.id);
      expectText(test, user.email, email);
      expectFalse(test, user.isGuest, "no longer a guest");
      expectTrue(test, user.confirmedAt != null, "confirmed");
      expectInt(test, count(db, "SELECT count(*) AS n FROM works WHERE user_id = ${g.id.toString()}"), 1);
      expectTrue(test, accountsGetUserByEmailAndPassword(db, email, validPassword()) != null, "signs in");
      expectInt(test, userCount(db), 1);
    }

    test("claiming with bad params reports changeset errors and leaves the guest") { test =>
      let db = dbOpen(":memory:");
      let g = accountsCreateGuest(db);
      let r = accountsClaimGuestAccount(db, g, paramsOf("nope", "short"));
      expectText(test, errorsText(r, "email"), "must have the @ sign and no spaces");
      expectText(test, errorsText(r, "password"), "should be at least 12 character(s)");
      expectTrue(test, accountsGetUser(db, g.id).isGuest, "still a guest");
      let taken = userFixture(db);
      let t = accountsClaimGuestAccount(db, g, paramsOf(taken.email, validPassword()));
      expectText(test, errorsText(t, "email"), "has already been taken");
    }

    test("claiming without changing the email is an error") { test =>
      let db = dbOpen(":memory:");
      let g = accountsCreateGuest(db);
      let r = accountsClaimGuestAccount(db, g, passwordOnly(validPassword()));
      expectText(test, errorsText(r, "email"), "did not change");
    }

    test("a user who is not a guest cannot claim") { test =>
      let db = dbOpen(":memory:");
      let user = userFixture(db);
      let r = accountsClaimGuestAccount(db, user, paramsOf(uniqueEmail(), validPassword()));
      expectText(test, orNull(r.error), "not_a_guest");
      expectTrue(test, r.ok == null, "no result user");
      expectText(test, accountsGetUser(db, user.id).email, user.email);
    }

## Tours

    test("a tour is unseen until it is marked") { test =>
      let db = dbOpen(":memory:");
      let user = userFixture(db);
      expectFalse(test, accountsSeenTour(user, "read"), "unseen");
      let marked = accountsMarkTourSeen(db, user, "read");
      expectTrue(test, accountsSeenTour(marked, "read"), "seen");
      expectFalse(test, accountsSeenTour(marked, "graph"), "other tour unseen");
      expectTrue(test, accountsSeenTour(accountsGetUser(db, user.id), "read"), "persisted");
    }

    test("marking a tour twice changes nothing; a new tour goes to the front") { test =>
      let db = dbOpen(":memory:");
      let user = userFixture(db);
      let a = accountsMarkTourSeen(db, user, "read");
      let again = accountsMarkTourSeen(db, a, "read");
      expectText(test, joined(again.seenTours), "read");
      expectText(test, again.updatedAt, a.updatedAt);
      let b = accountsMarkTourSeen(db, again, "graph");
      expectText(test, joined(b.seenTours), "graph|read");
      expectText(test, joined(accountsGetUser(db, user.id).seenTours), "graph|read");
    }

    test("a tour name with quotes survives the JSON column") { test =>
      let db = dbOpen(":memory:");
      let user = userFixture(db);
      let marked = accountsMarkTourSeen(db, user, "a \"b\" \\ c");
      expectText(test, joined(accountsGetUser(db, marked.id).seenTours), "a \"b\" \\ c");
    }

## Owner, admin and the model backend

The owner is `OWNER_EMAIL`, default `bobbbygrayson@gmail.com`; these tests
build a user with whatever email the environment says.

    let ownerFixture(db: Db): User throws Bubble { userAt(db, accountsOwnerEmail()) }

    let withProvider(u: User, provider: String?): User {
      new User(
        u.id, u.email, u.hashedPassword, u.confirmedAt, u.isAdmin, provider,
        u.isGuest, u.seenTours, u.insertedAt, u.updatedAt,
      )
    }

    test("the configured email is the owner, whatever its case") { test =>
      let db = dbOpen(":memory:");
      let owner = ownerFixture(db);
      expectTrue(test, accountsIsOwner(owner), "owner");
      expectTrue(test, accountsIsOwner(new User(0, sysUtf8Upcase(owner.email), null, null, false, null, false, [], "", "")), "case-insensitive");
      let found = accountsOwner(db);
      expectInt(test, if (found != null) { found.id } else { -1 }, owner.id);
    }

    test("an admin who is not the owner is not the owner") { test =>
      let db = dbOpen(":memory:");
      let user = userFixture(db);
      accountsMakeAdmin(db, user.email);
      let admin = accountsGetUser(db, user.id);
      expectTrue(test, accountsIsAdmin(admin), "admin");
      expectFalse(test, accountsIsOwner(admin), "not owner");
      expectTrue(test, accountsOwner(db) == null, "nobody is the owner yet");
    }

    test("make_admin: an unknown email is false and changes nothing") { test =>
      let db = dbOpen(":memory:");
      let user = userFixture(db);
      expectFalse(test, accountsMakeAdmin(db, "nobody@example.com"), "unknown");
      expectTrue(test, accountsMakeAdmin(db, user.email), "known");
      expectFalse(test, accountsIsAdmin(user), "the struct in hand is not updated");
      expectTrue(test, accountsIsAdmin(accountsGetUser(db, user.id)), "the row is");
    }

    test("provider_for: a non-owner gets the deploy default, admin or not") { test =>
      let db = dbOpen(":memory:");
      let user = userFixture(db);
      expectTrue(test, accountsProviderFor(withProvider(user, "openai")) == null, "plain user");
      accountsMakeAdmin(db, user.email);
      expectTrue(test, accountsProviderFor(withProvider(accountsGetUser(db, user.id), "openai")) == null, "admin");
    }

    test("provider_for: the owner gets their chosen backend, or the default") { test =>
      let db = dbOpen(":memory:");
      let owner = ownerFixture(db);
      expectText(test, orNull(accountsProviderFor(withProvider(owner, "openai"))), "openai");
      expectTrue(test, accountsProviderFor(withProvider(owner, null)) == null, "chose nothing");
      expectTrue(test, accountsProviderFor(withProvider(owner, "")) == null, "empty string");
    }

    test("set_llm_provider: a user who is not the owner is silently left alone") { test =>
      let db = dbOpen(":memory:");
      let user = userFixture(db);
      let r = accountsSetLlmProvider(db, user, "openai");
      expectTrue(test, resultUser(r).llmProvider == null, "unchanged");
      expectTrue(test, accountsGetUser(db, user.id).llmProvider == null, "nothing written");
      accountsMakeAdmin(db, user.email);
      let a = accountsSetLlmProvider(db, accountsGetUser(db, user.id), "openai");
      expectTrue(test, a.ok != null, "ok");
      expectTrue(test, accountsGetUser(db, user.id).llmProvider == null, "admin is not enough");
    }

    test("set_llm_provider: the owner can switch, and it persists") { test =>
      let db = dbOpen(":memory:");
      let owner = ownerFixture(db);
      let updated = resultUser(accountsSetLlmProvider(db, owner, "openai"));
      expectText(test, orNull(updated.llmProvider), "openai");
      expectText(test, orNull(accountsProviderFor(accountsGetUser(db, owner.id))), "openai");
      let back = resultUser(accountsSetLlmProvider(db, updated, "deepseek"));
      expectText(test, orNull(back.llmProvider), "deepseek");
    }

    test("set_llm_provider: an unknown provider is refused and writes nothing") { test =>
      let db = dbOpen(":memory:");
      let owner = ownerFixture(db);
      let r = accountsSetLlmProvider(db, owner, "definitely-not-a-provider");
      expectText(test, orNull(r.error), "unknown_provider");
      expectTrue(test, accountsGetUser(db, owner.id).llmProvider == null, "nothing written");
    }

## Records

    test("a user row reads back every column") { test =>
      let db = dbOpen(":memory:");
      let user = userFixture(db);
      expectTrue(test, user.id > 0, "id");
      expectInt(test, sysByteLength(user.insertedAt), 19);
      expectInt(test, sysByteLength(user.updatedAt), 19);
      expectFalse(test, user.isGuest, "default");
      expectFalse(test, user.isAdmin, "default");
      expectTrue(test, user.llmProvider == null, "default");
      expectTrue(test, user.hashedPassword != null, "hash");
    }

    test("the scope helpers read the user's flags") { test =>
      let db = dbOpen(":memory:");
      let user = userFixture(db);
      let g = accountsCreateGuest(db);
      expectTrue(test, scopeFor(user).isReal, "real");
      expectFalse(test, scopeFor(user).isGuest, "not guest");
      expectTrue(test, scopeFor(g).isGuest, "guest");
      expectFalse(test, scopeFor(g).isReal, "guest is not real");
      expectFalse(test, noScope().isReal, "visitor");
      expectFalse(test, noScope().isAdmin, "visitor");
    }
