# Upload rules

`Marginalia.Works.Upload`: what an upload form sent, checked and turned into
the attributes `worksCreateWork` takes. Two forms arrive at the same place,
and they have to agree about the word limit and about what counts as an empty
draft, so the rule lives here once.

    let { wordCount } = import("html/src");
    let { sysJoin } = import("sys/src");

Roughly a long novel. Not a technical limit: a read of this costs real money
per section.

    let uploadMaxWordsLimit = 120000;

    export let uploadMaxWords(): Int { uploadMaxWordsLimit }

## The result

`ok` is set when the upload is acceptable; otherwise `problem` is `"empty"` or
`"too_long"` (with `words` the count that was too long). `title` is never
blank in an accepted upload and `body` is the text as it arrived, untrimmed.

    export class UploadResult(
      public ok: UploadParams?,
      public problem: String?,
      public words: Int,
    ) {}

    export class UploadParams(
      public title: String,
      public body: String,
      public intent: String?,
    ) {}

## prepare

A title that is nothing but whitespace is no title; the caller has usually
already chosen a better fallback than "Untitled draft" (an attached file's
name, say).

    export let uploadPrepare(title: String?, body: String?, intent: String?): UploadResult {
      let text = if (body != null) { body } else { "" };
      let n = wordCount(text);
      if (n == 0) { return new UploadResult(null, "empty", 0); }
      if (n > uploadMaxWordsLimit) { return new UploadResult(null, "too_long", n); }
      let t = uploadBlank(title);
      let chosen = if (t != null) { t } else { "Untitled draft" };
      new UploadResult(new UploadParams(chosen, text, uploadBlank(intent)), null, n)
    }

Trimmed (Unicode whitespace), or null if there was nothing but whitespace.

    export let uploadBlank(s: String?): String? {
      if (s != null) {
        let trimmed = worksTrim(s);
        if (trimmed.isEmpty) { null } else { trimmed }
      } else {
        null
      }
    }

## The sentence shown for a draft over the limit

    export let uploadTooLongMessage(words: Int): String {
      "That's ${uploadCommas(words)} words, and the limit is ${uploadCommas(uploadMaxWordsLimit)} for now. Split it and upload the first part."
    }

Thousands separators: `120000` is `120,000`.

    let uploadCommas(n: Int): String {
      let digits = n.toString();
      let len = digits.countBetween(String.begin, digits.end);
      let groups = new ListBuilder<String>();
      var end = len;
      while (end > 0) {
        let start = if (end > 3) { end - 3 } else { 0 };
        groups.add(worksSliceCp(digits, start, end - start));
        end = start;
      }
      let reversed = new ListBuilder<String>();
      var i = groups.length - 1;
      while (i >= 0) { reversed.add(groups[i]); i -= 1; }
      sysJoin(reversed.toList(), ",")
    }
