# Tokens

Ported from `Marginalia.Accounts.UserToken`: the `users_tokens` table, the
two kinds of token that are used, and the windows they are valid for.

    let { DbRow, Db } = import("db/src");
    let { sysRandomToken, sysSha256, sysGraphemeTake } = import("sys/src");

## The record

Mirrors `users_tokens`. `token` is `TEXT` here (it was `bytea`): a session
token is stored as the raw url-safe string the cookie carries, an emailed
token as the SHA-256 hex of the string that was mailed. There is no
`updated_at`.

    export class UserToken(
      public id: Int,
      public userId: Int,
      public token: String,
      public context: String,
      public sentTo: String?,
      public authenticatedAt: String?,
      public insertedAt: String,
    ) {
      public static fromRow(row: DbRow): UserToken throws Bubble {
        new UserToken(
          row.int("id"),
          row.int("user_id"),
          row.str("token"),
          row.str("context"),
          row.strOrNull("sent_to"),
          row.strOrNull("authenticated_at"),
          row.str("inserted_at"),
        )
      }
    }

    export let userTokenColumns = "id, user_id, token, context, sent_to, authenticated_at, inserted_at";

## Windows

The Elixir constants. The magic-link window (15 minutes) is not here: no
`Accounts` function ever built or consumed a `login` token.

    export let userTokenSessionValidityDays(): Int { 14 }
    export let userTokenChangeEmailValidityDays(): Int { 7 }

The web layer reissues a session token once it is older than this many days
(the cookie's max age is `userTokenSessionValidityDays`).

    export let userTokenSessionReissueDays(): Int { 7 }

## Session tokens

A session token is `sysRandomToken()` (32 random bytes, url-safe), stored
raw, context `session`, with the `authenticated_at` of the login that made
it. Returns the token.

    export let userTokenInsertSession(db: Db, userId: Int, authenticatedAt: String, insertedAt: String): String throws Bubble {
      let token = sysRandomToken();
      db.insert(
        "INSERT INTO users_tokens (user_id, token, context, authenticated_at, inserted_at) VALUES ($1, $2, 'session', $3, $4)",
        [userId.toString(), token, authenticatedAt, insertedAt],
      );
      token
    }

The row for a session token still inside its 14 days, or null. Validity is
`inserted_at > now - 14 days`, enforced in the query.

    export let userTokenSessionRow(db: Db, token: String): UserToken? throws Bubble {
      let row = db.one(
        "SELECT ${userTokenColumns} FROM users_tokens WHERE token = $1 AND context = 'session' AND inserted_at > datetime('now', '-${userTokenSessionValidityDays().toString()} days')",
        [token],
      );
      if (row != null) { UserToken.fromRow(row) } else { null }
    }

Whether a token inserted at `insertedAt` is old enough to be reissued: 7
days or more. Both sides are "YYYY-MM-DD HH:MM:SS" UTC, so SQLite does the
date arithmetic.

    export let userTokenNeedsReissue(db: Db, insertedAt: String): Boolean throws Bubble {
      let row = db.one(
        "SELECT ($1 <= datetime('now', '-${userTokenSessionReissueDays().toString()} days')) AS old",
        [insertedAt],
      );
      if (row != null) { row.bool("old") } else { false }
    }

## Emailed tokens

`userTokenBuildEmail` makes a token for an email flow: 32 random bytes as a
url-safe string (this is what goes in the URL), and stores its SHA-256 hex.
The Elixir stored the SHA-256 of the raw bytes and mailed their base64url;
Blimp strings are text, so the url-safe string is the token and the hash is
of that text. Reading the database does not give the token. `sent_to` is
`userEmail`.

    export let userTokenBuildEmail(db: Db, userId: Int, userEmail: String, context: String): String throws Bubble {
      let token = sysRandomToken();
      db.insert(
        "INSERT INTO users_tokens (user_id, token, context, sent_to) VALUES ($1, $2, $3, $4)",
        [userId.toString(), sysSha256(token), context, userEmail],
      );
      token
    }

The row for a change-email token, or null: the hash matches, the context
matches, the context starts with `change:`, and it is under 7 days old.

    export let userTokenChangeEmailRow(db: Db, token: String, context: String): UserToken? throws Bubble {
      if (sysGraphemeTake(context, 7) != "change:") { return null; }
      let row = db.one(
        "SELECT ${userTokenColumns} FROM users_tokens WHERE token = $1 AND context = $2 AND inserted_at > datetime('now', '-${userTokenChangeEmailValidityDays().toString()} days')",
        [sysSha256(token), context],
      );
      if (row != null) { UserToken.fromRow(row) } else { null }
    }
