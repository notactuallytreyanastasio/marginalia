# Tests for PDF page text

Ported from `test/marginalia/reflow_test.exs`. The page is the opening of
the Landor opinion as `pdftotext` handed it over, page furniture and all.

    let landor = [
      "JUSTICE GORSUCH delivered the opinion of the Court.",
      "This case concerns whether the Religious Land Use and",
      "Institutionalized Persons Act of 2000 permits plaintiffs to",
      "sue nonconsenting state employees in their private capaci-",
      "ties for damages.",
      "I",
      "Today, Congress offers financial support to all 50 States",
      "and many other entities. Much of that support comes with",
      "strings attached. So, for example, Congress has conditioned",
      "receipt of federal highway funds on a State's agreement to",
      "maintain laws setting a minimum drinking age of 21. See",
      "South Dakota v. Dole, 483 U. S. 203 (1987). Likewise, Con-",
      "gress has conditioned federal Medicaid funds on a State's",
      "willingness to administer its healthcare programs con-",
      "sistent with various rules.",
      "2 LANDOR v. LOUISIANA DEPT. OF CORRECTIONS AND",
      "PUBLIC SAFETY",
      "In each of these contexts and many others, the penalty for",
      "noncompliance is straightforward: Congress may termi-",
      "nate funds if a recipient fails to abide by the conditions",
      "associated with its grants.",
    ].join("\n") { (line): String => line };

    let paragraphsOf(page: String): List<String> {
      reflowPage(page).split("\n\n")
    }

    let wrappedIs(test: Test, text: String, want: Boolean): Void {
      assert(isWrapped(text) == want) { "isWrapped: wanted ${want}" }
    }

    test("hard-wrapped text with no blank lines is page text") { test =>
      wrappedIs(test, landor, true);
    }

    test("text that already has paragraphs is left alone") { test =>
      let para = repeated("word ", 30);
      let prose = "Paragraph 1. ${para}\n\nParagraph 2. ${para}\n\nParagraph 3. ${para}\n\nParagraph 4. ${para}";
      wrappedIs(test, prose, false);
      expectText(test, reflowPage(prose), prose);
    }

    test("the typesetter's hyphens are closed up, and the running head is dropped") { test =>
      let out = reflowPage(landor);
      assert(includes(out, "private capacities for damages")) { out }
      assert(includes(out, "Congress has conditioned federal Medicaid")) { out }
      assert(!includes(out, "LANDOR v. LOUISIANA")) { out }
    }

    test("the division numeral stands alone") { test =>
      let paragraphs = paragraphsOf(landor);
      var found = false;
      for (var i = 0; i < paragraphs.length; i += 1) {
        if (paragraphs[i] == "I") { found = true; }
      }
      assert(found) { paragraphs.join("\n--\n") { (p): String => p } }
    }

The cases below are not ASCII. Their expected text was produced by running
the Elixir this library replaced (`Old.Reflow`) on the same input.

    let pageIs(test: Test, page: String, want: String): Void {
      expectText(test, reflowPage(page), want);
    }

    test("reflow: the typesetter's hyphens are mended through accented letters") { test =>
      let page = [
        "Les éditions étaient bien connues dans la région pour leur élé-",
        "gance et leur naïveté, disait le curé de la paroisse où il avait con-",
        "nu une co-opération rare, et un well-known usage, car le mot well-",
        "known revenait sans cesse dans la bouche du vieux maître d'école, et",
        "personne ne se souvenait plus du well-known usage ni de leurs affai-",
        "res. On parlait de l'été, de la crème, de l'hôtel et de la forêt de",
        "Fontainebleau avec une tendresse que seuls les exilés connaissent, et",
        "les étoiles se levèrent une à une au-dessus des toits de l'école aban-",
        "donnée, tandis que le silence des grandes plaines froides s'étendait",
        "sur tout le pays, jusqu'aux montagnes lointaines où dormaient les ours",
        "et les loups, dans l'attente patiente de l'hiver qui devait enfin ve-",
        "nir, ce soir-là, après tant d'années d'attente et de souvenirs de co-",
        "opération entre les hommes. Voilà.",
      ].join("\n") { (line): String => line };
      wrappedIs(test, page, true);
      pageIs(test, page, "Les éditions étaient bien connues dans la région pour leur élégance et leur naïveté, disait le curé de la paroisse où il avait connu une co-opération rare, et un well-known usage, car le mot well-known revenait sans cesse dans la bouche du vieux maître d'école, et personne ne se souvenait plus du well-known usage ni de leurs affaires. On parlait de l'été, de la crème, de l'hôtel et de la forêt de Fontainebleau avec une tendresse que seuls les exilés connaissent, et les étoiles se levèrent une à une au-dessus des toits de l'école abandonnée, tandis que le silence des grandes plaines froides s'étendait sur tout le pays, jusqu'aux montagnes lointaines où dormaient les ours et les loups, dans l'attente patiente de l'hiver qui devait enfin venir, ce soir-là, après tant d'années d'attente et de souvenirs de co-opération entre les hommes. Voilà.");
    }

    test("reflow: an accented capitals running head is dropped, a Greek one too") { test =>
      let page = [
        "Le tribunal a jugé que la décision de l'agence était arbitraire et",
        "capricieuse au regard de la loi, et que les requérants avaient raison.",
        "ÉCOLE NORMALE SUPÉRIEURE DE LA RÉPUBLIQUE",
        "La Cour a ensuite examiné la question de la compétence, qui n'était pas",
        "contestée par les parties, et qui ne soulevait aucune difficulté sérieuse.",
        "ΟΔΟΣ ΣΟΦΙΑΣ ΚΑΙ ΑΡΕΤΗΣ ΤΟΥ ΔΙΚΑΣΤΗΡΙΟΥ 12",
        "Elle a donc rejeté le pourvoi, avec dépens, et ordonné la restitution du",
        "dépôt de garantie versé par les demandeurs au début de la procédure.",
        "Fin de l'arrêt rendu à Paris, le premier jour de mai, en audience publique.",
        "Suivent les signatures des juges et du greffier qui ont siégé ce jour-là.",
        "Il fut signifié le lendemain aux parties, comme la loi le demande en pareil cas.",
        "Fin.",
        "Annexe : la liste des pièces versées au dossier par chacune des deux parties.",
      ].join("\n") { (line): String => line };
      wrappedIs(test, page, true);
      pageIs(test, page, "Le tribunal a jugé que la décision de l'agence était arbitraire et capricieuse au regard de la loi, et que les requérants avaient raison. La Cour a ensuite examiné la question de la compétence, qui n'était pas contestée par les parties, et qui ne soulevait aucune difficulté sérieuse. Elle a donc rejeté le pourvoi, avec dépens, et ordonné la restitution du dépôt de garantie versé par les demandeurs au début de la procédure. Fin de l'arrêt rendu à Paris, le premier jour de mai, en audience publique. Suivent les signatures des juges et du greffier qui ont siégé ce jour-là. Il fut signifié le lendemain aux parties, comme la loi le demande en pareil cas. Fin.\n\nAnnexe : la liste des pièces versées au dossier par chacune des deux parties.");
    }

    test("reflow: a Cyrillic line and a mixed-case caption are told apart") { test =>
      let page = [
        "Суд постановил, что решение агентства было произвольным и необоснованным",
        "по смыслу закона, и что заявители были совершенно правы в своём иске.",
        "ВЕРХОВНЫЙ СУД РОССИЙСКОЙ ФЕДЕРАЦИИ",
        "Далее суд рассмотрел вопрос о подсудности, который не оспаривался",
        "сторонами и не вызывал никаких серьёзных затруднений при рассмотрении.",
        "The Straße Café Résumé Über Ångström Östra Ñandú Şehir Çarşı Ürün 1983",
        "Поэтому суд отклонил жалобу, с отнесением издержек на заявителей, и",
        "приказал вернуть залог, внесённый ими в начале всего этого разбирательства.",
        "Конец решения, вынесенного в Москве, в первый день мая, в открытом заседании.",
        "Следуют подписи судей и секретаря, которые заседали в этот самый день.",
        "Оно было вручено сторонам на следующий день, как этого требует закон.",
        "Всё.",
        "Приложение: перечень документов, представленных каждой из двух сторон.",
      ].join("\n") { (line): String => line };
      wrappedIs(test, page, true);
      pageIs(test, page, "Суд постановил, что решение агентства было произвольным и необоснованным по смыслу закона, и что заявители были совершенно правы в своём иске. Далее суд рассмотрел вопрос о подсудности, который не оспаривался сторонами и не вызывал никаких серьёзных затруднений при рассмотрении. The Straße Café Résumé Über Ångström Östra Ñandú Şehir Çarşı Ürün 1983 Поэтому суд отклонил жалобу, с отнесением издержек на заявителей, и приказал вернуть залог, внесённый ими в начале всего этого разбирательства. Конец решения, вынесенного в Москве, в первый день мая, в открытом заседании. Следуют подписи судей и секретаря, которые заседали в этот самый день. Оно было вручено сторонам на следующий день, как этого требует закон. Всё.\n\nПриложение: перечень документов, представленных каждой из двух сторон.");
    }

    test("reflow: a quote is mended against its source, accents and all") { test =>
      expectText(test, align("the élé-\ngance of the well-\nknown thing, naïve.", "the well-known école was naïve. The élé-\ngance of the well-known thing."), "the élégance of the well-known thing, naïve.");
    }
