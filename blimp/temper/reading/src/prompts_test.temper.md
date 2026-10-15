# Tests for the prompts

The system prompts and the tool schemas are the Elixir module attributes
evaluated and written out (`prompts.temper.md`). These pin them by size and by
SHA-256 against the same strings evaluated by Elixir 1.19 when the port was made
(`:json.encode` of each tool's `parameters`, keys in map order), so a prompt
cannot drift by a character without a test saying so.

    let { sysSha256, sysByteLength, sysJoin } = import("sys/src");
    let { JsonSyntaxTree } = import("std/json");

    let pinned(test: Test, what: String, text: String, bytes: Int, hash: String): Void {
      rdInt(test, sysByteLength(text), bytes);
      rdText(test, sysSha256(text), hash);
    }

    test("prompts: the section summary prompt and tool are the Elixir's") { test =>
      pinned(test, "prompt", summaryPrompt(), 621, "b0dac88233a30074adc55d1d48ef17dadac7bf37ed64bfa6848f1a749d18013c");
      pinned(test, "tool", summaryToolParameters(), 1351, "d473fcd367513f19a50692e46165326eed7ff68fc7830c126594351fb17f6983");
      rdText(test, summaryToolName(), "report_section");
    }

    test("prompts: the rewrite prompt and tool are the Elixir's") { test =>
      pinned(test, "prompt", rewritePrompt(), 1694, "26462f63c74f89ee0dbde9929f4e9c988cacd315e243727620af5a007e00664c");
      pinned(test, "tool", rewriteToolParameters(), 645, "b9cbf3aad60d8e3fbd5143f45ba81656c5e2d79b0018a097cc67f9713566174b");
      rdText(test, rewriteToolName(), "propose_rewrites");
    }

    test("prompts: the document composition prompt and tool are the Elixir's") { test =>
      pinned(test, "prompt", documentComposePrompt(), 529, "ad9020cd87c4e3128cc0f8ce1650cd7c79c5535289f2b082b8825b389a74d9cc");
      pinned(test, "tool", documentComposeToolParameters(), 1386, "21909bf0d2c90d0d2b461d42b3bb55a20226a6036299ddb1b9687486d83af5d3");
      rdText(test, documentComposeToolName(), "report_composition");
    }

    test("prompts: the document guidelines prompt and tool are the Elixir's") { test =>
      pinned(test, "prompt", documentGuidePrompt(), 498, "1302f91a27d2356bb550f896ae653959a3d9197af5b8cbc0f2073a81da51ade7");
      pinned(test, "tool", documentGuideToolParameters(), 1382, "ad0bedad214d2b28648da7ea55bf41388c42aa7327ae7fa9e66eb04a76729255");
      rdText(test, documentGuideToolName(), "report_guidelines");
    }

    test("prompts: the schemas are valid JSON with the required lists the validators rely on") { test =>
      let summary = rdJson(summaryToolParameters());
      rdText(
        test,
        sysJoin(readingElements(summary, "required").map { (e: JsonSyntaxTree): String => readingInspect(e) }, ","),
        "\"summary\",\"covers\",\"follows_from\",\"sets_up\"",
      );
      let guide = rdJson(documentGuideToolParameters());
      rdText(
        test,
        sysJoin(readingElements(guide, "required").map { (e: JsonSyntaxTree): String => readingInspect(e) }, ","),
        "\"guidelines\",\"tensions\"",
      );
    }

    test("prompts: the intent line is there when the draft has one and empty when it does not") { test =>
      rdText(test, promptsIntent(null), "");
      rdText(test, promptsIntent(""), "");
      rdText(test, promptsIntent("To unsettle."), "What it is meant to do to a reader: To unsettle.\n");
    }

    test("prompts: the user messages are the Elixir templates") { test =>
      rdText(
        test, promptsComposeUser("T", "I", 2, "1. A\ns"),
        "Document: T\nWhat it is meant to do to a reader: I\n\n2 sections, summarised, in order:\n\n1. A\ns\n",
      );
      rdText(
        test, promptsGuideUser("T", null, "1. A", "1. s"),
        "Document: T\n\nIts sections:\n1. A\n\nWhat each section does:\n1. s\n",
      );
      rdText(
        test, promptsRewriteUser("T", null, "", "", "span", ""),
        "Manuscript: T\n\nTHE SELECTED SPAN, to be replaced:\n\nspan\n\n\n",
      );
    }

    test("prompts: the scale notes are given at 61 and 401 words, not before") { test =>
      rdText(test, rewriteScale(60), "");
      rdHas(test, rewriteScale(61), "This span is 61 words — several sentences.");
      rdHas(test, rewriteScale(400), "several sentences");
      rdHas(test, rewriteScale(401), "This span is 401 words — a section, not a sentence.");
    }
