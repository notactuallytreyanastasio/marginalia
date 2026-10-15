# SQL Data Model

We build an abstract model that can be rendered to different dialects.

## SqlFragment

The fragment class supports semi-structured raw SQL text and data values, which
then can be escaped differently for different dbs. And while called a
"fragment", an instance can also represent a full statement.

    export class SqlFragment(
      public parts: List<SqlPart>,
    ) {

      // toSource: freeze to string source content marked as safe SQL
      public toSource(): SqlSource {
        new SqlSource(toString())
      }

      // toString
      public toString(): String {
        let builder = new StringBuilder();
        for (var i = 0; i < parts.length; ++i) {
          parts[i].formatTo(builder);
        }
        builder.toString()
      }

      // toParameterized: the SQL text with a numbered placeholder ($1, $2,
      // ...) where each value goes, and the values, in order, as text
      public toParameterized(): ParameterizedSql {
        let text = new StringBuilder();
        let params = new ListBuilder<String>();
        for (var i = 0; i < parts.length; ++i) {
          parts[i].formatParameterized(text, params);
        }
        new ParameterizedSql(text.toString(), params.toList())
      }

    }

## ParameterizedSql

`toString` puts each value into the SQL as an escaped literal. A driver that
can bind parameters would rather have the values kept apart, so that no
escaping is involved at all: `toParameterized` gives the text with `$1`,
`$2`, ... in place of the values, and the values as strings in the same
order.

SQLite accepts `$AAAA` as a named parameter (a `$` followed by an
identifier; digits are valid identifier characters after the `$`). Named
parameters that are not `?NNN` get their index in order of first appearance,
so `$1, $2, $3` written in order become parameters 1, 2, 3, and a driver that
binds by index in `params` order is correct. This holds only because Alloy
numbers placeholders in order and never reuses one: a statement written by
hand as `$2 ... $1` would bind backwards. The driver binds every value as
text, so a comparison of an integer column with a text parameter relies on
SQLite's column affinity (`INTEGER` affinity converts `'7'` before comparing).
Booleans are `1`/`0` in the text and dates are quoted ISO text, as in
`toString`.

Only data goes into `params`. What Alloy already knows is safe (identifiers,
keywords, booleans, `DEFAULT`, and `NULL` for a float that has no SQL
literal) stays in the text, as `toString` writes it.

    export class ParameterizedSql(
      public text: String,
      public params: List<String>,
    ) {}

    let placeholder(text: StringBuilder, params: ListBuilder<String>, value: String): Void {
      params.add(value);
      text.append("$");
      text.append(params.length.toString());
    }

## SqlPart

Each part of a SQL fragment is either raw known-safe SQL source or else a value
needing escaped and/or represented properly for a particular DB dialect.

    export sealed interface SqlPart {

      // formatTo: enables using a single StringBuilder across multiple parts
      public formatTo(builder: StringBuilder): Void;

      // formatParameterized: data as a placeholder plus a parameter, the
      // rest as text
      public formatParameterized(text: StringBuilder, params: ListBuilder<String>): Void;

    }

## SqlSource

`SqlSource` represents known-safe SQL source code that doesn't need escaped.

    export class SqlSource(public source: String) extends SqlPart {

      // formatTo
      public formatTo(builder: StringBuilder): Void {
        builder.append(source);
      }


      // formatParameterized
      public formatParameterized(text: StringBuilder, params: ListBuilder<String>): Void {
        text.append(source);
      }
    }

## SqlBoolean

SQLite has no boolean type. `TRUE` and `FALSE` only parse from 3.23 (2018), so a
boolean renders as the integer `1` or `0`, which every build accepts and which
is what a boolean column stores anyway.

    export class SqlBoolean(public value: Boolean) extends SqlPart {

      // formatTo
      public formatTo(builder: StringBuilder): Void {
        builder.append(if (value) { "1" } else { "0" });
      }


      // formatParameterized
      public formatParameterized(text: StringBuilder, params: ListBuilder<String>): Void {
        formatTo(text);
      }
    }

## SqlDate

    export class SqlDate(public value: Date) extends SqlPart {

      // formatTo: quote-wraps with escaping (defense-in-depth against future Date formats)
      public formatTo(builder: StringBuilder): Void {
        builder.append("'");
        for (let c of value.toString()) {
          if (c == char'\'') {
            builder.append("''");
          } else {
            builder.appendCodePoint(c) orelse panic();
          }
        }
        builder.append("'");
      }


      // formatParameterized
      public formatParameterized(text: StringBuilder, params: ListBuilder<String>): Void {
        placeholder(text, params, value.toString());
      }
    }

## SqlFloat64

    export class SqlFloat64(public value: Float64) extends SqlPart {

      // formatTo: rejects NaN/Infinity which are not valid SQL literals (CWE-20)
      public formatTo(builder: StringBuilder): Void {
        let s = value.toString();
        if (s == "NaN" || s == "Infinity" || s == "-Infinity") {
          builder.append("NULL");
        } else {
          builder.append(s);
        }
      }


      // formatParameterized
      public formatParameterized(text: StringBuilder, params: ListBuilder<String>): Void {
        let s = value.toString();
        if (s == "NaN" || s == "Infinity" || s == "-Infinity") {
          text.append("NULL");
        } else {
          placeholder(text, params, s);
        }
      }
    }

## SqlInt32

    export class SqlInt32(public value: Int32) extends SqlPart {

      // formatTo
      public formatTo(builder: StringBuilder): Void {
        builder.append(value.toString());
      }


      // formatParameterized
      public formatParameterized(text: StringBuilder, params: ListBuilder<String>): Void {
        placeholder(text, params, value.toString());
      }
    }

## SqlInt64

    export class SqlInt64(public value: Int64) extends SqlPart {

      // formatTo
      public formatTo(builder: StringBuilder): Void {
        builder.append(value.toString());
      }


      // formatParameterized
      public formatParameterized(text: StringBuilder, params: ListBuilder<String>): Void {
        placeholder(text, params, value.toString());
      }
    }

## SqlDefault

`SqlDefault` renders the literal SQL keyword `DEFAULT`. SQLite has no
`DEFAULT` in a `VALUES` list, so this text is invalid there and SQLite will
reject it, loudly. The changeset never emits it: `toInsertSql` leaves a
`SqlDefault` column out of the column list, and the column's own `DEFAULT`
clause in the `CREATE TABLE` fills it. Only a hand-built fragment can still
put the keyword in the text.

    export class SqlDefault() extends SqlPart {

      // formatTo
      public formatTo(builder: StringBuilder): Void {
        builder.append("DEFAULT");
      }


      // formatParameterized
      public formatParameterized(text: StringBuilder, params: ListBuilder<String>): Void {
        formatTo(text);
      }
    }

## SqlString

`SqlString` represents text data that needs escaped.

    export class SqlString(public value: String) extends SqlPart {

      // formatTo
      public formatTo(builder: StringBuilder): Void {
        builder.append("'");
        for (let c of value) {
          if (c == char'\'') {
            builder.append("''");
          } else {
            builder.appendCodePoint(c) orelse panic();
          }
        }
        builder.append("'");
      }


      // formatParameterized
      public formatParameterized(text: StringBuilder, params: ListBuilder<String>): Void {
        placeholder(text, params, value);
      }
    }
