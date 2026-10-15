# Who is asking

Every context takes a `Scope` after the database: the user making the
request, or nobody. The Elixir `Marginalia.Accounts.Scope` was a struct with
one field, `user`; the flags the pages read (`is_admin`, `is_guest`) are on
the user. These two classes are the contract between `accounts` and
everything else, and are written first so the other contexts can compile
against them while `accounts` is still being ported.

    let { DbRow } = import("db/src");

## User

Mirrors the `users` table column for column. `hashedPassword` is null for a
guest, who has no password. `seenTours` is a JSON array column.

    export class User(
      public id: Int,
      public email: String,
      public hashedPassword: String?,
      public confirmedAt: String?,
      public isAdmin: Boolean,
      public llmProvider: String?,
      public isGuest: Boolean,
      public seenTours: List<String>,
      public insertedAt: String,
      public updatedAt: String,
    ) {
      public static fromRow(row: DbRow): User throws Bubble {
        new User(
          row.int("id"),
          row.str("email"),
          row.strOrNull("hashed_password"),
          row.strOrNull("confirmed_at"),
          row.bool("is_admin"),
          row.strOrNull("llm_provider"),
          row.bool("is_guest"),
          row.strList("seen_tours"),
          row.str("inserted_at"),
          row.str("updated_at"),
        )
      }
    }

The SELECT list every query over `users` uses, so `fromRow` always finds
its columns.

    export let userColumns = "id, email, hashed_password, confirmed_at, is_admin, llm_provider, is_guest, seen_tours, inserted_at, updated_at";

## Scope

`user` is null for a visitor with no session at all (the public pages), a
guest user for the guest-or-user pages, and a real account otherwise.

    export class Scope(public user: User?) {
      public get userId(): Int throws Bubble {
        let u = user;
        if (u != null) { u.id } else { bubble() }
      }
      public get isAdmin(): Boolean {
        let u = user;
        if (u != null) { u.isAdmin } else { false }
      }
      public get isGuest(): Boolean {
        let u = user;
        if (u != null) { u.isGuest } else { false }
      }
      public get isReal(): Boolean {
        let u = user;
        if (u != null) { !u.isGuest } else { false }
      }
    }

    export let scopeFor(user: User?): Scope { new Scope(user) }
    export let noScope(): Scope { new Scope(null) }
