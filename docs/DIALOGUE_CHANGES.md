# Dialogue changes

`tools/dialogue_overrides.json` changes only displayed string literals while the
story is compiled. Replacements are scoped to each source script, so short phrases
cannot match dialogue in another scene. It does not alter branches, choices' result
values, commands, variables, inventory, map transitions, or source assets. The
original FreeDink data and its licence notices remain in `licenses/`.

The replacements below remove gendered insults, sexual harassment, incest jokes,
victim-blaming, and a rumor that slurs Dink's mother. They keep the original scene,
speaker, and outcome intact.

| Source script | Original scene | Revision |
| --- | --- | --- |
| `S1-H2-O.c` | Dink mocks Ethel's drinking and sex life. | He asks about her bottle collection instead. |
| `S1-H3-L.c` | Dink makes a sexual insinuation about Libby's father. | The line becomes a non-sexual, still-insensitive question about control. |
| `S1-H3-L.c` | Dink calls violence against Libby a pet name. | He acknowledges that attacking her is wrong. |
| `S1-BLOVE.c`, `S1-MH-M.c` | Dink calls women “chicks.” | He says “people” and asks about making a feast. |
| `S1-WAND2.c` | A traveler repeats a slur about Dink's mother, then laughs. | The traveler admits repeating a cruel rumor was wrong. |
| `S2-NA1.c` | A bed is called dirty because it belongs to a woman. | The bed is identified as Nadine's and described neutrally. |
| `S2-BAR.c`, `S2-WENCH.c` | The bartender is called a wench and propositioned. | Patrons address the bartender respectfully and order beer. |
| `S2-AUNTP.c`, `S2-JACK.c` | Player choices and lines invite or praise Jack's abuse of Maria. | They ask him to stop, support Maria, and remove incest humor. |
| `S7-MIL.c` | Milder uses a gendered insult. | He calls Dink a coward instead. |
| `SPICE.c` | Dink objectifies the Spice Girls parody. | He introduces himself and asks about the group. |

The compiler applies each replacement by exact literal match. Its
`report.dialogue_overrides` map reports the number applied in each source script, so
an upstream source change cannot silently make this policy incomplete. The original
phrases remain in this source-controlled override file and are not copied into the
generated game data. The bundled campaign currently applies 41 replacements.
